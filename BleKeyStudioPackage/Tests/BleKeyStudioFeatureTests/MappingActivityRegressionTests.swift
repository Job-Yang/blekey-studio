import AppKit
import Testing

@testable import BleKeyStudioFeature

@Suite(.serialized) @MainActor
struct MappingActivityRegressionTests {
  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func find<T: NSView>(_ id: String, in view: NSView, as type: T.Type) throws -> T {
    try #require(descendants(view).first { $0.identifier?.rawValue == id } as? T)
  }

  @Test func modifierOnlyAndPrimaryKeyToggleAreStoredForTheSelectedPhysicalKey() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let store = ProfileStore(storageURL: root.appendingPathComponent("profiles.json"))
    let controller = WorkspaceViewController(
      profileStore: store,
      bluetooth: BluetoothController(demoMode: true),
      activityLogStore: ActivityLogStore(storageURL: root.appendingPathComponent("activity.log")))
    let window = makeWindow(controller)
    defer { window.contentViewController = nil }

    let table = try find("mappingTable", in: controller.view, as: NSTableView.self)
    table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
    let address = MappingAddress(layer: 1, key: 3)
    let option = try find(
      "keycap.modifier.\(KeyModifier.rightOption.rawValue)",
      in: controller.view,
      as: NSButton.self)
    let letter = try find("keycap.key.l", in: controller.view, as: NSButton.self)

    option.performClick(nil)
    #expect(
      store.selectedProfile.assignment(at: address)?.actionID == ActionCatalog.modifierOnly.id)
    #expect(store.selectedProfile.assignment(at: address)?.modifierSet == [.rightOption])
    #expect(store.selectedProfile.assignment(at: MappingAddress(layer: 1, key: 1)) == nil)

    letter.performClick(nil)
    #expect(store.selectedProfile.assignment(at: address)?.actionID == "key.l")
    #expect(store.selectedProfile.assignment(at: address)?.modifierSet == [.rightOption])

    letter.performClick(nil)
    #expect(
      store.selectedProfile.assignment(at: address)?.actionID == ActionCatalog.modifierOnly.id)
    try snapshot(controller.view, name: "modifier-only-mapping")
    #expect(store.selectedProfile.assignment(at: address)?.modifierSet == [.rightOption])
    option.performClick(nil)

    #expect(store.selectedProfile.assignment(at: address) == nil)
  }

  @Test func activityShowsAndPersistsLocalEditsAndTransportEvents() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    let logStore = ActivityLogStore(storageURL: root.appendingPathComponent("activity.log"))
    let store = ProfileStore(storageURL: root.appendingPathComponent("profiles.json"))
    let bluetooth = BluetoothController(demoMode: true)
    let device = try #require(bluetooth.devices.first)
    store.bindSelectedProfile(
      deviceIdentifier: device.id, deviceName: device.name, keyCount: device.inferredKeyCount)
    let controller = WorkspaceViewController(
      profileStore: store, bluetooth: bluetooth, activityLogStore: logStore)
    let window = makeWindow(controller)
    defer { window.contentViewController = nil }

    let letter = try find("keycap.key.l", in: controller.view, as: NSButton.self)
    letter.performClick(nil)
    let apply = try find("applyChanges", in: controller.view, as: NSButton.self)
    apply.performClick(nil)
    for _ in 0..<50 where bluetooth.isBusy {
      try await Task.sleep(for: .milliseconds(20))
    }

    let activity = try find("navigation.2", in: controller.view, as: NSButton.self)
    activity.performClick(nil)
    controller.view.layoutSubtreeIfNeeded()
    let textView = try find("activityLogView", in: controller.view, as: NSTextView.self)
    #expect(textView.frame.width > 0)
    #expect(textView.string.contains("本地修改"))
    #expect(textView.string.contains("发送"))
    #expect(textView.string.contains("写入完成"))
    try snapshot(controller.view, name: "activity-log-visible")

    let persisted = try String(contentsOf: logStore.storageURL, encoding: .utf8)
    #expect(persisted.contains("本地修改"))
    #expect(persisted.contains("发送"))
    #expect(persisted.contains("写入完成"))
  }

  private func makeWindow(_ controller: NSViewController) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1120, height: 860),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1120, height: 860))
    controller.view.layoutSubtreeIfNeeded()
    return window
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
