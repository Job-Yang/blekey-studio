import Foundation

public enum ProfileStoreError: LocalizedError {
  case profileNotFound
  case cannotDeleteLastProfile
  case unsupportedDocumentVersion(Int)
  case invalidDocument(String)
  case libraryNotLoaded

  public var errorDescription: String? {
    switch self {
    case .profileNotFound:
      "找不到所选方案。"
    case .cannotDeleteLastProfile:
      "至少需要保留一个方案。"
    case .unsupportedDocumentVersion(let version):
      "方案版本 \(version) 暂不支持。"
    case .invalidDocument(let reason):
      "方案文件无效：\(reason)"
    case .libraryNotLoaded:
      "本地方案未能读取，原文件已保护。请先重新读取。"
    }
  }
}

public enum ProfilePersistenceState: Equatable {
  case ready
  case loadFailed(String)
  case saveFailed(String)
}

public final class ProfileStore {
  public private(set) var library: ProfileLibrary
  public private(set) var persistenceState: ProfilePersistenceState = .ready
  public private(set) var hasUnsavedChanges = false
  public private(set) var hasSavedLibrary = false
  public var onChange: (() -> Void)?

  public var canEdit: Bool {
    if case .loadFailed = persistenceState { return false }
    return true
  }

  public var canApplyToDevice: Bool {
    persistenceState == .ready && !hasUnsavedChanges
  }

  private let fileManager: FileManager
  private let storageURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    fileManager: FileManager = .default,
    storageURL: URL? = nil
  ) {
    let demoMode =
      ProcessInfo.processInfo.environment["BLEKEY_DEMO_MODE"] == "1"
      || ProcessInfo.processInfo.arguments.contains("--demo")
    self.fileManager = fileManager
    self.storageURL =
      storageURL
      ?? Self.defaultStorageURL(fileManager: fileManager, demoMode: demoMode)
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    library = demoMode ? .demo() : .starter()
    do {
      let saved = try decoder.decode(ProfileLibrary.self, from: Data(contentsOf: self.storageURL))
      try Self.validate(saved)
      library = saved
      hasSavedLibrary = true
    } catch {
      if !Self.isMissingFile(error) {
        persistenceState = .loadFailed(error.localizedDescription)
      }
    }
  }

  public var profiles: [DeviceProfile] {
    library.profiles
  }

  public var selectedProfile: DeviceProfile {
    get {
      library.profiles.first(where: { $0.id == library.selectedProfileID })
        ?? library.profiles[0]
    }
    set {
      guard canEdit else {
        onChange?()
        return
      }
      do {
        try Self.validate(newValue)
      } catch {
        persistenceState = .saveFailed(error.localizedDescription)
        onChange?()
        return
      }
      if let index = library.profiles.firstIndex(where: { $0.id == newValue.id }) {
        library.profiles[index] = newValue
      } else {
        library.profiles.append(newValue)
      }
      library.selectedProfileID = newValue.id
      persistAndNotify()
    }
  }

  public func selectProfile(id: UUID) throws {
    guard canEdit else { throw ProfileStoreError.libraryNotLoaded }
    guard library.profiles.contains(where: { $0.id == id }) else {
      throw ProfileStoreError.profileNotFound
    }
    library.selectedProfileID = id
    persistAndNotify()
  }

  @discardableResult
  public func createProfile(name: String = "新方案") -> DeviceProfile {
    guard canEdit else { return selectedProfile }
    let profile = DeviceProfile(name: uniqueName(basedOn: name))
    library.profiles.append(profile)
    library.selectedProfileID = profile.id
    persistAndNotify()
    return profile
  }

  @discardableResult
  public func duplicateSelectedProfile() -> DeviceProfile {
    guard canEdit else { return selectedProfile }
    var copy = selectedProfile
    copy.id = UUID()
    copy.name = uniqueName(basedOn: "\(copy.name) 副本")
    copy.managesSleep = copy.shouldManageSleep
    copy.lastSentMappings = []
    copy.lastSentSleepTimeout = nil
    copy.updatedAt = Date()
    library.profiles.append(copy)
    library.selectedProfileID = copy.id
    persistAndNotify()
    return copy
  }

  public func renameSelectedProfile(to name: String) {
    var profile = selectedProfile
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.name = trimmed.isEmpty ? profile.name : trimmed
    selectedProfile = profile
  }

  public func deleteSelectedProfile() throws {
    guard canEdit else { throw ProfileStoreError.libraryNotLoaded }
    guard library.profiles.count > 1 else {
      throw ProfileStoreError.cannotDeleteLastProfile
    }
    library.profiles.removeAll { $0.id == library.selectedProfileID }
    library.selectedProfileID = library.profiles[0].id
    persistAndNotify()
  }

  public func updateSelectedProfile(_ mutation: (inout DeviceProfile) -> Void) {
    var profile = selectedProfile
    mutation(&profile)
    selectedProfile = profile
  }

  public func bindSelectedProfile(
    deviceIdentifier: UUID,
    deviceName: String,
    keyCount: Int
  ) {
    updateSelectedProfile {
      if $0.deviceIdentifier != deviceIdentifier {
        $0.managesSleep = $0.shouldManageSleep
        $0.lastSentMappings = []
        $0.lastSentSleepTimeout = nil
      }
      $0.deviceIdentifier = deviceIdentifier
      $0.deviceName = deviceName
      $0.keyCount = max(1, min(24, keyCount))
    }
  }

  public func recordSent(_ command: XKeyCommand, from snapshot: DeviceProfile) {
    guard canEdit else { return }
    guard
      let index = library.profiles.firstIndex(where: {
        $0.id == snapshot.id && $0.deviceIdentifier == snapshot.deviceIdentifier
      })
    else { return }
    switch command.target {
    case .mapping(let address):
      library.profiles[index].markSent(snapshot.assignment(at: address), at: address)
    case .sleep:
      library.profiles[index].lastSentSleepTimeout = snapshot.sleepTimeout
    }
    // Another plan's sent baseline is stale once this plan changes the same device.
    for other in library.profiles.indices where other != index {
      guard let device = snapshot.deviceIdentifier,
        library.profiles[other].deviceIdentifier == device
      else { continue }
      library.profiles[other].managesSleep = library.profiles[other].shouldManageSleep
      library.profiles[other].lastSentMappings = []
      library.profiles[other].lastSentSleepTimeout = nil
    }
    persistAndNotify()
  }

  public func exportSelectedProfile(to url: URL) throws {
    guard canEdit else { throw ProfileStoreError.libraryNotLoaded }
    try requireCopyDestination(url)
    try Self.validate(selectedProfile)
    let data = try encoder.encode(selectedProfile)
    try data.write(to: url, options: .atomic)
  }

  @discardableResult
  public func importProfile(from url: URL) throws -> DeviceProfile {
    try importProfiles(from: url)[0]
  }

  @discardableResult
  public func importProfiles(from url: URL) throws -> [DeviceProfile] {
    guard canEdit else { throw ProfileStoreError.libraryNotLoaded }
    let document = try decoder.decode(ImportDocument.self, from: Data(contentsOf: url))
    var candidate = library
    var imported: [DeviceProfile] = []
    for profile in document.profiles {
      var copy = Self.unboundCopy(profile)
      copy.name = uniqueName(basedOn: copy.name, in: candidate.profiles)
      candidate.profiles.append(copy)
      imported.append(copy)
    }
    candidate.selectedProfileID = imported[0].id
    do {
      try write(candidate)
    } catch {
      persistenceState = .saveFailed(error.localizedDescription)
      onChange?()
      throw error
    }
    library = candidate
    hasUnsavedChanges = false
    persistenceState = .ready
    onChange?()
    return imported
  }

  public func encodeLibrary() throws -> Data {
    try encoder.encode(library)
  }

  public func exportLibrary(to url: URL) throws {
    guard canEdit else { throw ProfileStoreError.libraryNotLoaded }
    try requireCopyDestination(url)
    try Self.validate(library)
    try encoder.encode(library).write(to: url, options: .atomic)
  }

  // Recovery is explicit and preserves the unreadable original before replacing it.
  @discardableResult
  public func restoreLibrary(from url: URL) throws -> URL? {
    guard !canEdit else {
      throw ProfileStoreError.invalidDocument("当前库可读取，请使用导入合并方案。")
    }
    let document = try decoder.decode(ImportDocument.self, from: Data(contentsOf: url))
    let profiles = document.profiles.map(Self.unboundCopy)
    let candidate = ProfileLibrary(selectedProfileID: profiles[0].id, profiles: profiles)
    var backup: URL?
    if fileManager.fileExists(atPath: storageURL.path) {
      let destination = storageURL.deletingLastPathComponent()
        .appendingPathComponent("profiles-unreadable-\(UUID().uuidString).json")
      try fileManager.copyItem(at: storageURL, to: destination)
      backup = destination
    }
    try write(candidate)
    library = candidate
    persistenceState = .ready
    hasUnsavedChanges = false
    onChange?()
    return backup
  }

  private func requireCopyDestination(_ url: URL) throws {
    guard
      url.standardizedFileURL.resolvingSymlinksInPath()
        != storageURL.standardizedFileURL.resolvingSymlinksInPath()
    else { throw ProfileStoreError.invalidDocument("副本需要保存到其他文件。") }
  }

  private static func unboundCopy(_ profile: DeviceProfile) -> DeviceProfile {
    var copy = profile
    copy.id = UUID()
    copy.documentVersion = 1
    copy.deviceIdentifier = nil
    copy.deviceName = nil
    copy.managesSleep = copy.shouldManageSleep
    copy.lastSentMappings = []
    copy.lastSentSleepTimeout = nil
    copy.updatedAt = Date()
    return copy
  }

  private struct ImportDocument: Decodable {
    let profiles: [DeviceProfile]
    private enum CodingKeys: String, CodingKey { case profiles }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      if container.contains(.profiles) {
        let library = try ProfileLibrary(from: decoder)
        try ProfileStore.validate(library)
        profiles = library.profiles
      } else {
        let profile = try DeviceProfile(from: decoder)
        try ProfileStore.validate(profile)
        profiles = [profile]
      }
    }
  }

  @discardableResult
  public func retryPersistence() -> Bool {
    if case .loadFailed = persistenceState {
      do {
        let saved = try decoder.decode(ProfileLibrary.self, from: Data(contentsOf: storageURL))
        try Self.validate(saved)
        library = saved
        persistenceState = .ready
        hasUnsavedChanges = false
        hasSavedLibrary = true
      } catch {
        persistenceState = .loadFailed(error.localizedDescription)
      }
      onChange?()
    } else {
      persistAndNotify()
    }
    return persistenceState == .ready
  }

  private func persistAndNotify() {
    guard canEdit else {
      onChange?()
      return
    }
    hasUnsavedChanges = true
    do {
      try write(library)
      hasUnsavedChanges = false
      persistenceState = .ready
    } catch {
      persistenceState = .saveFailed(error.localizedDescription)
      NSLog("BleKey Studio profile save failed: %@", error.localizedDescription)
    }
    onChange?()
  }

  private func write(_ library: ProfileLibrary) throws {
    try Self.validate(library)
    try fileManager.createDirectory(
      at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(library).write(to: storageURL, options: .atomic)
    hasSavedLibrary = true
  }

  private static func isMissingFile(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
  }

  private static func validateVersion(_ version: Int?) throws {
    guard version == nil || version == 1 else {
      throw ProfileStoreError.unsupportedDocumentVersion(version!)
    }
  }

  private static func validate(_ library: ProfileLibrary) throws {
    try validateVersion(library.documentVersion)
    guard !library.profiles.isEmpty,
      Set(library.profiles.map(\.id)).count == library.profiles.count,
      library.profiles.contains(where: { $0.id == library.selectedProfileID })
    else { throw ProfileStoreError.invalidDocument("方案列表为空、标识重复或选中项不存在。") }
    for profile in library.profiles { try validate(profile) }
  }

  private static func validate(_ profile: DeviceProfile) throws {
    try validateVersion(profile.documentVersion)
    guard (1...24).contains(profile.keyCount) else {
      throw ProfileStoreError.invalidDocument("实体按键数量必须为 1 到 24。")
    }
    guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ProfileStoreError.invalidDocument("方案名称不能为空。")
    }
    for records in [profile.mappings, profile.lastSentMappings] {
      var addresses = Set<MappingAddress>()
      for record in records {
        guard addresses.insert(record.address).inserted else {
          throw ProfileStoreError.invalidDocument("同一层的按键不能重复。")
        }
        _ = try XKeyProtocol.mappingCommand(address: record.address, assignment: record.assignment)
        let modifiers = record.assignment.modifiers
        guard Set(modifiers).count == modifiers.count,
          modifiers.isEmpty
            || ActionCatalog.action(id: record.assignment.actionID)?.category == .keyboard
        else { throw ProfileStoreError.invalidDocument("修饰键重复，或非键盘动作包含修饰键。") }
      }
    }
  }

  private func uniqueName(basedOn proposedName: String, in profiles: [DeviceProfile]? = nil)
    -> String
  {
    let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = trimmed.isEmpty ? "新方案" : trimmed
    let existing = Set((profiles ?? library.profiles).map(\.name))
    guard existing.contains(name) else { return name }
    var index = 2
    while existing.contains("\(name) \(index)") {
      index += 1
    }
    return "\(name) \(index)"
  }

  private static func defaultStorageURL(
    fileManager: FileManager,
    demoMode: Bool
  ) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return
      root
      .appendingPathComponent("BleKey Studio", isDirectory: true)
      .appendingPathComponent(demoMode ? "profiles-demo.json" : "profiles.json")
  }
}
