import Foundation
import Testing

@testable import BleKeyStudioFeature

@Suite struct ProfileStoreTests {
  private func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  @Test func loadFailurePreservesOriginalBytes() throws {
    let url = try directory().appendingPathComponent("profiles.json")
    let original = Data("{incomplete".utf8)
    try original.write(to: url)
    let store = ProfileStore(storageURL: url)

    store.renameSelectedProfile(to: "Recovered")

    #expect(try Data(contentsOf: url) == original)
  }

  @Test func missingLibraryCreatesAndPersistsNormally() throws {
    let url = try directory().appendingPathComponent("profiles.json")
    let store = ProfileStore(storageURL: url)
    #expect(store.profiles.count == 1)
    store.renameSelectedProfile(to: "Editing")
    let reloaded = ProfileStore(storageURL: url)
    #expect(reloaded.selectedProfile.name == "Editing")
    #expect(reloaded.selectedProfile.id == store.selectedProfile.id)
  }

  @Test func importSaveFailureIsReportedWithoutPartialInsertion() throws {
    let root = try directory()
    let parent = root.appendingPathComponent("storage")
    let storage = parent.appendingPathComponent("library.json")
    let store = ProfileStore(storageURL: storage)
    store.renameSelectedProfile(to: "Existing")
    let before = try store.encodeLibrary()
    let imported = root.appendingPathComponent("import.json")
    try encode(DeviceProfile(name: "Imported")).write(to: imported)
    let preserved = root.appendingPathComponent("preserved")
    try FileManager.default.moveItem(at: parent, to: preserved)
    try Data("not a directory".utf8).write(to: parent)

    #expect(throws: (any Error).self) {
      try store.importProfile(from: imported)
    }
    #expect(try store.encodeLibrary() == before)
    #expect(try Data(contentsOf: preserved.appendingPathComponent("library.json")) == before)
  }

  enum InvalidInput: String, CaseIterable {
    case zeroKeys, tooManyKeys, invalidLayer, invalidKey, duplicateAddress
    case unknownAction, mediaModifiers, duplicateModifiers
  }

  @Test(arguments: InvalidInput.allCases)
  func importRejectsInvalidDataWithoutChangingLibrary(_ input: InvalidInput) throws {
    let root = try directory()
    let store = ProfileStore(storageURL: root.appendingPathComponent("library.json"))
    let before = try store.encodeLibrary()
    let address = MappingAddress(layer: 1, key: 1)
    let record = MappingRecord(address: address, assignment: KeyAssignment(actionID: "key.a"))
    var profile = DeviceProfile(name: "Imported", mappings: [record])
    switch input {
    case .zeroKeys: profile.keyCount = 0
    case .tooManyKeys: profile.keyCount = 25
    case .invalidLayer:
      profile.mappings = [
        MappingRecord(address: MappingAddress(layer: 11, key: 1), assignment: record.assignment)
      ]
    case .invalidKey:
      profile.mappings = [
        MappingRecord(address: MappingAddress(layer: 1, key: 25), assignment: record.assignment)
      ]
    case .duplicateAddress: profile.mappings = [record, record]
    case .unknownAction:
      profile.mappings = [
        MappingRecord(address: address, assignment: KeyAssignment(actionID: "unknown"))
      ]
    case .mediaModifiers:
      profile.mappings = [
        MappingRecord(
          address: address,
          assignment: KeyAssignment(actionID: "media.volumeUp", modifiers: [.leftCommand]))
      ]
    case .duplicateModifiers: break
    }
    var data = try encode(profile)
    if input == .duplicateModifiers {
      var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      var records = try #require(object["mappings"] as? [[String: Any]])
      var assignment = try #require(records[0]["assignment"] as? [String: Any])
      assignment["modifiers"] = [8, 8]
      records[0]["assignment"] = assignment
      object["mappings"] = records
      data = try JSONSerialization.data(withJSONObject: object)
    }
    let file = root.appendingPathComponent("import.json")
    try data.write(to: file)

    #expect(throws: (any Error).self) {
      try store.importProfile(from: file)
    }
    #expect(try store.encodeLibrary() == before)
  }

  @Test(arguments: [1, 24])
  func importPreservesSupportedEdgesAndDropsDeviceState(_ keyCount: Int) throws {
    let root = try directory()
    let store = ProfileStore(storageURL: root.appendingPathComponent("library.json"))
    let record = MappingRecord(
      address: MappingAddress(layer: 10, key: keyCount),
      assignment: KeyAssignment(actionID: "key.k", modifiers: [.rightCommand]))
    let profile = DeviceProfile(
      name: "Imported", deviceIdentifier: UUID(), deviceName: "Device",
      keyCount: keyCount, mappings: [record], lastSentMappings: [record],
      sleepTimeout: .fourHours, lastSentSleepTimeout: .fourHours)
    let file = root.appendingPathComponent("import.json")
    try encode(profile).write(to: file)

    let imported = try store.importProfile(from: file)

    #expect(imported.keyCount == keyCount)
    #expect(imported.mappings == [record])
    #expect(imported.id != profile.id)
    #expect(imported.deviceIdentifier == nil)
    #expect(imported.lastSentMappings.isEmpty)
    #expect(imported.lastSentSleepTimeout == nil)
    #expect(imported.shouldManageSleep)
    #expect(imported.isSleepDirty)
    #expect(try XKeyProtocol.commands(for: imported).count == 2)
  }
}
