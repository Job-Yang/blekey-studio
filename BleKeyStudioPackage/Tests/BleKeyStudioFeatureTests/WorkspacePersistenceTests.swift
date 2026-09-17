import AppKit
import Testing

@testable import BleKeyStudioFeature

@Suite(.serialized) @MainActor
struct WorkspacePersistenceTests {
  private func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func encode<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(value)
  }

  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func control<T: NSView>(_ id: String, in view: NSView, as type: T.Type) throws -> T {
    try #require(descendants(view).first { $0.identifier?.rawValue == id } as? T)
  }

  private func workspace(_ store: ProfileStore) -> (WorkspaceViewController, NSWindow) {
    _ = NSApplication.shared
    let controller = WorkspaceViewController(
      profileStore: store, bluetooth: BluetoothController(demoMode: true))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 960, height: 700))
    controller.view.layoutSubtreeIfNeeded()
    return (controller, window)
  }

  @Test func unreadableLibraryBlocksEditingAndRecoversThroughButton() throws {
    let root = try directory()
    let file = root.appendingPathComponent("library.json")
    let original = Data("{incomplete".utf8)
    try original.write(to: file)
    let store = ProfileStore(storageURL: file)
    let (controller, window) = workspace(store)
    defer { window.contentViewController = nil }
    let banner = try control("persistenceBanner", in: controller.view, as: NSView.self)
    let apply = try control("applyChanges", in: controller.view, as: NSButton.self)
    let key = try control("keycap.key.k", in: controller.view, as: NSButton.self)
    #expect(!banner.isHidden)
    #expect(!store.canEdit)
    #expect(!apply.isEnabled)
    let before = try store.encodeLibrary()
    key.performClick(nil)
    #expect(try store.encodeLibrary() == before)
    #expect(try Data(contentsOf: file) == original)
    #expect(!store.retryPersistence())
    try snapshot(controller.view, name: "persistence-load-failed")

    var recovered = ProfileLibrary.starter()
    recovered.profiles[0].name = "Recovered"
    // This fixture represents a file repaired outside the application.
    try encode(recovered).write(to: file)
    let retry = try control("retryPersistence", in: controller.view, as: NSButton.self)
    retry.performClick(nil)
    #expect(store.canEdit)
    #expect(banner.isHidden)
    #expect(store.selectedProfile.name == "Recovered")
    key.performClick(nil)
    #expect(
      store.selectedProfile.assignment(at: MappingAddress(layer: 1, key: 1))?.actionID == "key.k")
    #expect(apply.isEnabled)
  }

  @Test func saveFailureKeepsDraftAndRescueCopyUntilRetrySucceeds() throws {
    let root = try directory()
    let parent = root.appendingPathComponent("storage")
    let file = parent.appendingPathComponent("library.json")
    let store = ProfileStore(storageURL: file)
    store.renameSelectedProfile(to: "First")
    _ = store.createProfile(name: "Second")
    let (controller, window) = workspace(store)
    defer { window.contentViewController = nil }
    let preserved = root.appendingPathComponent("preserved")
    try FileManager.default.moveItem(at: parent, to: preserved)
    try Data("not a directory".utf8).write(to: parent)
    let key = try control("keycap.key.k", in: controller.view, as: NSButton.self)
    key.performClick(nil)
    #expect(store.hasUnsavedChanges)
    #expect(!store.canApplyToDevice)
    let banner = try control("persistenceBanner", in: controller.view, as: NSView.self)
    let apply = try control("applyChanges", in: controller.view, as: NSButton.self)
    #expect(!banner.isHidden)
    #expect(!apply.isEnabled)
    let rescue = try control("exportRecovery", in: controller.view, as: NSButton.self)
    #expect(!rescue.isHidden)
    controller.view.layoutSubtreeIfNeeded()
    let retry = try control("retryPersistence", in: controller.view, as: NSButton.self)
    #expect(!retry.frame.intersects(rescue.frame))
    let copy = root.appendingPathComponent("rescue.json")
    try store.exportLibrary(to: copy)
    #expect(store.hasUnsavedChanges)
    #expect(throws: (any Error).self) { try store.exportLibrary(to: file) }
    #expect(throws: (any Error).self) { try store.exportSelectedProfile(to: file) }
    let importedStore = ProfileStore(storageURL: root.appendingPathComponent("other.json"))
    let imported = try importedStore.importProfiles(from: copy)
    #expect(imported.map(\.name) == ["First", "Second"])
    #expect(imported.last?.assignment(at: MappingAddress(layer: 1, key: 1))?.actionID == "key.k")
    try snapshot(controller.view, name: "persistence-save-failed")

    try FileManager.default.moveItem(at: parent, to: root.appendingPathComponent("obstruction"))
    try FileManager.default.moveItem(at: preserved, to: parent)
    retry.performClick(nil)
    #expect(!store.hasUnsavedChanges)
    #expect(store.persistenceState == .ready)
    #expect(banner.isHidden)
    #expect(apply.isEnabled)
    let reloaded = ProfileStore(storageURL: file)
    #expect(
      reloaded.selectedProfile.assignment(at: MappingAddress(layer: 1, key: 1))?.actionID == "key.k"
    )
    #expect(reloaded.profiles.count == 2)
  }

  @Test func recoveryPreservesUnreadableFileAndClearsDeviceBaselines() throws {
    let root = try directory()
    let file = root.appendingPathComponent("library.json")
    let original = Data("corrupted".utf8)
    try original.write(to: file)
    let store = ProfileStore(storageURL: file)
    var source = ProfileLibrary.demo()
    source.profiles[0].deviceIdentifier = UUID()
    source.profiles[0].lastSentMappings = source.profiles[0].mappings
    let copy = root.appendingPathComponent("rescue.json")
    try encode(source).write(to: copy)
    let backup = try #require(try store.restoreLibrary(from: copy))
    #expect(try Data(contentsOf: backup) == original)
    #expect(store.persistenceState == .ready)
    #expect(store.profiles.count == 1)
    #expect(store.selectedProfile.mappings == source.profiles[0].mappings)
    #expect(store.selectedProfile.deviceIdentifier == nil)
    #expect(store.selectedProfile.lastSentMappings.isEmpty)
    #expect(store.selectedProfile.dirtyAddresses.count == 3)
    let reloaded = ProfileStore(storageURL: file)
    #expect(reloaded.selectedProfile.id == store.selectedProfile.id)
  }

  enum InvalidLibrary: CaseIterable {
    case empty, duplicateID, missingSelection, futureVersion, invalidProfile
  }

  @Test(arguments: InvalidLibrary.allCases)
  func invalidLibraryRemainsProtected(_ input: InvalidLibrary) throws {
    let root = try directory()
    let file = root.appendingPathComponent("library.json")
    var library = ProfileLibrary.starter()
    switch input {
    case .empty: library.profiles = []
    case .duplicateID: library.profiles.append(library.profiles[0])
    case .missingSelection: library.selectedProfileID = UUID()
    case .futureVersion: library.documentVersion = 99
    case .invalidProfile: library.profiles[0].keyCount = 0
    }
    let bytes = try encode(library)
    try bytes.write(to: file)
    let store = ProfileStore(storageURL: file)
    #expect(!store.canEdit)
    store.renameSelectedProfile(to: "Changed")
    #expect(!store.retryPersistence())
    #expect(throws: (any Error).self) { try store.restoreLibrary(from: file) }
    #expect(try Data(contentsOf: file) == bytes)
  }

  @Test func legacyVersionlessLibrariesAndProfilesRemainReadable() throws {
    let root = try directory()
    var library = ProfileLibrary.demo()
    library.documentVersion = nil
    library.profiles[0].documentVersion = nil
    let file = root.appendingPathComponent("library.json")
    try encode(library).write(to: file)
    let store = ProfileStore(storageURL: file)
    #expect(store.persistenceState == .ready)
    #expect(store.selectedProfile.mappings == library.profiles[0].mappings)
    let profileFile = root.appendingPathComponent("profile.json")
    try encode(library.profiles[0]).write(to: profileFile)
    #expect(try store.importProfile(from: profileFile).mappings == library.profiles[0].mappings)
  }

  enum CloseChoice: CaseIterable {
    case cancel, retryFailure, retrySuccess, discard
  }

  @Test(arguments: CloseChoice.allCases)
  func unsavedCloseRequiresAnExplicitDecision(_ choice: CloseChoice) throws {
    for useWindowDelegate in [false, true] {
      let root = try directory()
      let parent = root.appendingPathComponent("storage")
      let file = parent.appendingPathComponent("library.json")
      let store = ProfileStore(storageURL: file)
      store.renameSelectedProfile(to: "Saved")
      let original = try Data(contentsOf: file)
      let preserved = root.appendingPathComponent("preserved")
      try FileManager.default.moveItem(at: parent, to: preserved)
      try Data("obstruction".utf8).write(to: parent)
      store.renameSelectedProfile(to: "Draft")
      let (controller, window) = workspace(store)
      defer { window.contentViewController = nil }
      let coordinator = AppCoordinator(windowController: NSWindowController(window: window))
      if choice == .retrySuccess {
        try FileManager.default.moveItem(at: parent, to: root.appendingPathComponent("obstruction"))
        try FileManager.default.moveItem(at: preserved, to: parent)
      }
      let response: NSApplication.ModalResponse
      switch choice {
      case .cancel: response = .alertSecondButtonReturn
      case .discard: response = .alertThirdButtonReturn
      case .retrySuccess, .retryFailure: response = .alertFirstButtonReturn
      }
      var clicked = false
      let timer = Timer(timeInterval: 0.05, repeats: false) { _ in
        MainActor.assumeIsolated {
          guard let content = NSApp.modalWindow?.contentView,
            let button = self.descendants(content).compactMap({ $0 as? NSButton })
              .first(where: { $0.tag == response.rawValue })
          else {
            Issue.record("Modal decision button was not found")
            NSApp.stopModal(withCode: .abort)
            return
          }
          clicked = true
          button.performClick(nil)
        }
      }
      RunLoop.main.add(timer, forMode: .modalPanel)
      let watchdog = Timer(timeInterval: 2, repeats: false) { _ in
        MainActor.assumeIsolated {
          Issue.record("Close confirmation timed out")
          NSApp.stopModal(withCode: .abort)
        }
      }
      RunLoop.main.add(watchdog, forMode: .modalPanel)
      let allowed =
        useWindowDelegate ? coordinator.windowShouldClose(window) : coordinator.shouldTerminate()
      timer.invalidate()
      watchdog.invalidate()
      #expect(clicked)
      #expect(allowed == (choice == .retrySuccess || choice == .discard))
      #expect(store.selectedProfile.name == "Draft")
      #expect(store.hasUnsavedChanges == (choice != .retrySuccess))
      if choice == .retrySuccess {
        #expect(ProfileStore(storageURL: file).selectedProfile.name == "Draft")
      } else {
        #expect(try Data(contentsOf: preserved.appendingPathComponent("library.json")) == original)
      }
      withExtendedLifetime(controller) {}
    }
  }

  @Test func activeDemoWritePreventsQuitAndWindowClose() throws {
    _ = NSApplication.shared
    let root = try directory()
    let store = ProfileStore(storageURL: root.appendingPathComponent("library.json"))
    let bluetooth = BluetoothController(demoMode: true)
    let controller = WorkspaceViewController(profileStore: store, bluetooth: bluetooth)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentViewController = controller
    defer { window.contentViewController = nil }
    let coordinator = AppCoordinator(windowController: NSWindowController(window: window))
    #expect(bluetooth.send([XKeyProtocol.sleepCommand(.fiveMinutes)]))
    #expect(bluetooth.isBusy)
    #expect(!coordinator.shouldTerminate())
    if let sheet = window.attachedSheet { window.endSheet(sheet) }
    #expect(!coordinator.windowShouldClose(window))
    if let sheet = window.attachedSheet { window.endSheet(sheet) }
    bluetooth.disconnect()
    #expect(!bluetooth.isBusy)
  }

  private func snapshot(_ view: NSView, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["BLEKEY_SNAPSHOT_DIR"] else { return }
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    let root = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try data.write(to: root.appendingPathComponent("\(name).png"), options: .atomic)
  }
}
