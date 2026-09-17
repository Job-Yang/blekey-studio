import AppKit
import Testing

@testable import BleKeyStudioFeature

@Test func newProfileDoesNotOverwriteSleep() throws {
  let profile = DeviceProfile()
  #expect(!profile.shouldManageSleep)
  #expect(!profile.isSleepDirty)
  #expect(try XKeyProtocol.commands(for: profile).isEmpty)
  var edited = profile
  edited.setAssignment(KeyAssignment(actionID: "key.k"), at: MappingAddress(layer: 1, key: 1))
  #expect(
    try XKeyProtocol.commands(for: edited).map(\.target) == [
      .mapping(MappingAddress(layer: 1, key: 1))
    ])
}

@Test func writeCompletionUsesSnapshotNotCurrentDraft() throws {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
  let store = ProfileStore(storageURL: url)
  let address = MappingAddress(layer: 1, key: 1)
  store.updateSelectedProfile {
    $0.setAssignment(KeyAssignment(actionID: "key.a"), at: address)
    $0.managesSleep = true
    $0.sleepTimeout = .fiveMinutes
  }
  let snapshot = store.selectedProfile
  let commands = try XKeyProtocol.commands(for: snapshot)
  store.updateSelectedProfile {
    $0.setAssignment(KeyAssignment(actionID: "key.b"), at: address)
    $0.sleepTimeout = .oneHour
  }
  _ = store.createProfile(name: "Other")
  for command in commands { store.recordSent(command, from: snapshot) }
  #expect(store.selectedProfile.name == "Other")
  try store.selectProfile(id: snapshot.id)
  #expect(store.selectedProfile.lastSentAssignment(at: address)?.actionID == "key.a")
  #expect(store.selectedProfile.assignment(at: address)?.actionID == "key.b")
  #expect(store.selectedProfile.lastSentSleepTimeout == .fiveMinutes)
  #expect(store.selectedProfile.isSleepDirty)
  #expect(store.selectedProfile.dirtyAddresses == [address])
}

@Test func switchingDevicesInvalidatesSentBaseline() {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
  let store = ProfileStore(storageURL: url)
  let address = MappingAddress(layer: 1, key: 1)
  store.bindSelectedProfile(deviceIdentifier: UUID(), deviceName: "First", keyCount: 3)
  store.updateSelectedProfile {
    $0.setAssignment(KeyAssignment(actionID: "key.a"), at: address)
    $0.markSent(at: address)
  }
  store.bindSelectedProfile(deviceIdentifier: UUID(), deviceName: "Second", keyCount: 3)
  #expect(store.selectedProfile.lastSentMappings.isEmpty)
  #expect(store.selectedProfile.dirtyAddresses == [address])
}

@Test @MainActor func demoReadbackNeverClaimsHardwareData() {
  let controller = BluetoothController(demoMode: true)
  var writes = 0
  controller.onCommandResult = { _, _ in writes += 1 }
  controller.inspectReadback()
  #expect(controller.readbackSummary.contains("演示模式"))
  #expect(writes == 0)
  controller.disconnect()
  #expect(!controller.canWrite)
}

@Suite(.serialized) @MainActor
struct WorkspaceRegressionTests {
  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  @Test func profileMenuKeepsVisibleAndActualTargetAligned() throws {
    _ = NSApplication.shared
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
    let store = ProfileStore(storageURL: url)
    let firstID = store.selectedProfile.id
    let second = store.createProfile(name: "Second")
    try store.selectProfile(id: firstID)
    let controller = WorkspaceViewController(
      profileStore: store, bluetooth: BluetoothController(demoMode: true))
    let views = descendants(controller.view)
    let table = try #require(views.compactMap { $0 as? NSTableView }.first)
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    let menuItem = try #require(
      views.compactMap { $0 as? NSPopUpButton }
        .flatMap(\.itemArray).first { $0.representedObject as? String == second.id.uuidString })
    #expect(NSApp.sendAction(try #require(menuItem.action), to: menuItem.target, from: menuItem))
    #expect(table.selectedRow == 0)
    let key = try #require(views.first { $0.identifier?.rawValue == "keycap.key.k" } as? NSButton)
    key.performClick(nil)
    #expect(store.selectedProfile.id == second.id)
    #expect(
      store.selectedProfile.assignment(at: MappingAddress(layer: 1, key: 1))?.actionID == "key.k")
    #expect(store.selectedProfile.assignment(at: MappingAddress(layer: 1, key: 2)) == nil)
  }

  @Test func mappingControlsAndNavigationRemainFunctional() throws {
    _ = NSApplication.shared
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json")
    let store = ProfileStore(storageURL: url)
    let controller = WorkspaceViewController(
      profileStore: store, bluetooth: BluetoothController(demoMode: true))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1120, height: 820),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentViewController = controller
    controller.view.layoutSubtreeIfNeeded()
    let initialViews = descendants(controller.view)
    #expect(initialViews.filter { $0.identifier?.rawValue == "applyChanges" }.count == 1)
    let table = try #require(initialViews.compactMap { $0 as? NSTableView }.first)
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    let key = try #require(
      initialViews.first { $0.identifier?.rawValue == "keycap.key.k" } as? NSButton)
    key.performClick(nil)
    let address = MappingAddress(layer: 1, key: 2)
    #expect(store.selectedProfile.assignment(at: address)?.actionID == "key.k")
    controller.undo(nil)
    #expect(store.selectedProfile.assignment(at: address) == nil)
    controller.redo(nil)
    #expect(store.selectedProfile.assignment(at: address)?.actionID == "key.k")

    let settings = try #require(
      initialViews.first { $0.identifier?.rawValue == "navigation.1" } as? NSButton)
    settings.performClick(nil)
    #expect(
      descendants(controller.view).compactMap { $0 as? NSTextField }.contains {
        $0.stringValue == "设备配置读取"
      })
    let mappings = try #require(
      initialViews.first { $0.identifier?.rawValue == "navigation.0" } as? NSButton)
    mappings.performClick(nil)
    #expect(descendants(controller.view).contains { $0 === table })
    #expect(table.numberOfRows == 3)
    #expect(table.numberOfColumns == 4)

    let recorder = try #require(
      descendants(controller.view).compactMap { $0 as? ShortcutRecorderView }.first)
    window.makeFirstResponder(recorder)
    let event = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: "Q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12))
    #expect(recorder.performKeyEquivalent(with: event))
    #expect(store.selectedProfile.assignment(at: address)?.actionID == "key.q")
    #expect(
      store.selectedProfile.assignment(at: address)?.modifierSet == [.leftCommand, .leftShift])
    window.contentViewController = nil
  }
}
