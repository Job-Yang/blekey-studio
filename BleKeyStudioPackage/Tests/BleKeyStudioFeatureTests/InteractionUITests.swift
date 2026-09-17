import AppKit
import Testing

@testable import BleKeyStudioFeature

@Suite(.serialized) @MainActor
struct InteractionUITests {
  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func find<T: NSView>(_ id: String, in view: NSView, as type: T.Type) throws -> T {
    try #require(descendants(view).first { $0.identifier?.rawValue == id } as? T)
  }

  private func key(
    _ code: UInt16, characters: String = "", flags: NSEvent.ModifierFlags = [],
    type: NSEvent.EventType = .keyDown, window: NSWindow
  ) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
  }

  private func makeWindow(
    _ controller: NSViewController, width: CGFloat = 1120, height: CGFloat = 860
  ) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: width, height: height))
    controller.view.layoutSubtreeIfNeeded()
    return window
  }

  private func storeURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("profiles.json")
  }

  @Test func recordingPreviewsModifiersCancelsAndPreservesEscape() throws {
    let store = ProfileStore(storageURL: storeURL())
    let address = MappingAddress(layer: 1, key: 1)
    let original = KeyAssignment(actionID: "key.k", modifiers: [.leftCommand])
    store.updateSelectedProfile { $0.setAssignment(original, at: address) }
    let controller = WorkspaceViewController(
      profileStore: store, bluetooth: BluetoothController(demoMode: true))
    let window = makeWindow(controller)
    defer { window.contentViewController = nil }
    let recorder = try find("shortcutRecorder", in: controller.view, as: ShortcutRecorderView.self)
    let cancel = try find("cancelRecording", in: controller.view, as: NSButton.self)
    let table = try find("mappingTable", in: controller.view, as: MappingTableView.self)
    window.makeFirstResponder(table)
    table.keyDown(with: try key(36, window: window))
    #expect(recorder.isRecording)
    recorder.flagsChanged(
      with: try key(55, flags: [.command, .shift], type: .flagsChanged, window: window))
    #expect(recorder.heldModifiers == [.leftCommand, .leftShift])
    #expect(store.selectedProfile.assignment(at: address) == original)
    #expect(!cancel.isHidden)
    try snapshot(controller.view, name: "recording-modifiers")
    recorder.flagsChanged(with: try key(56, flags: [.command], type: .flagsChanged, window: window))
    #expect(recorder.heldModifiers == [.leftCommand])
    cancel.performClick(nil)
    #expect(!recorder.isRecording)
    #expect(store.selectedProfile.assignment(at: address) == original)
    #expect(cancel.isHidden)

    recorder.startRecording()
    #expect(recorder.performKeyEquivalent(with: try key(53, characters: "\u{1b}", window: window)))
    #expect(store.selectedProfile.assignment(at: address)?.actionID == "key.escape")
    #expect(!recorder.isRecording)
    recorder.startRecording()
    #expect(recorder.performKeyEquivalent(with: try key(36, characters: "\r", window: window)))
    #expect(store.selectedProfile.assignment(at: address)?.actionID == "key.return")

    recorder.startRecording()
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    #expect(!recorder.isRecording)
    #expect(!recorder.performKeyEquivalent(with: try key(0, characters: "a", window: window)))
    #expect(store.selectedProfile.assignment(at: MappingAddress(layer: 1, key: 2)) == nil)
    recorder.startRecording()
    let layer = try find("layerSelector", in: controller.view, as: NSPopUpButton.self)
    layer.selectItem(withTag: 2)
    _ = layer.sendAction(layer.action, to: layer.target)
    #expect(!recorder.isRecording)
    recorder.startRecording()
    NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
    #expect(!recorder.isRecording)
  }

  @Test func searchSelectionRequiresConfirmationAndSupportsKeyboardNavigation() throws {
    let picker = ActionPickerViewController(category: .keyboard, selectedActionID: "key.k")
    let window = makeWindow(picker, width: 340, height: 342)
    defer { window.contentViewController = nil }
    var selected: [String] = []
    var cancelled = false
    picker.onSelected = { selected.append($0.id) }
    picker.onCancel = { cancelled = true }
    picker.searchField.stringValue = "Page"
    picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    #expect(picker.results.map(\.id) == ["key.pageUp", "key.pageDown"])
    #expect(selected.isEmpty)
    try snapshot(picker.view, name: "action-search-page")
    let editor = NSTextView()
    #expect(
      picker.control(
        picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
    #expect(picker.table.selectedRow == 1)
    #expect(selected.isEmpty)
    #expect(
      picker.control(
        picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    )
    #expect(selected == ["key.pageDown"])
    picker.searchField.stringValue = "none-matches"
    picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    #expect(picker.results.isEmpty)
    _ = picker.control(
      picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
    #expect(selected.count == 1)
    try snapshot(picker.view, name: "action-search-empty")
    picker.searchField.stringValue = ""
    picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    #expect(picker.results == ActionCatalog.keyboard)
    _ = picker.control(
      picker.searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    #expect(cancelled)
    #expect(selected.count == 1)
  }

  @Test func searchPopoverCommitsOnlyTheChosenActionToTheSelectedKey() throws {
    let store = ProfileStore(storageURL: storeURL())
    let controller = WorkspaceViewController(
      profileStore: store, bluetooth: BluetoothController(demoMode: true))
    let window = makeWindow(controller)
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentViewController = nil
    }
    let table = try find("mappingTable", in: controller.view, as: NSTableView.self)
    table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    let button = try find("openActionSearch", in: controller.view, as: NSButton.self)
    button.performClick(nil)
    let search = try #require(
      NSApp.windows.compactMap(\.contentView).flatMap { descendants($0) }
        .first { $0.identifier?.rawValue == "actionSearch" } as? NSSearchField)
    let picker = try #require(search.delegate as? ActionPickerViewController)
    search.stringValue = "volume up"
    picker.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    #expect(store.selectedProfile.mappings.isEmpty)
    #expect(picker.results.map(\.id) == ["media.volumeUp"])
    try snapshot(picker.view, name: "action-search-popover")
    _ = picker.control(
      search, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    let address = MappingAddress(layer: 1, key: 2)
    #expect(store.selectedProfile.assignment(at: address)?.actionID == "media.volumeUp")
    #expect(store.selectedProfile.assignment(at: address)?.modifiers.isEmpty == true)
    #expect(store.selectedProfile.assignment(at: MappingAddress(layer: 1, key: 1)) == nil)
    #expect(button.title == ActionCatalog.action(id: "media.volumeUp")?.name)
    controller.undo(nil)
    #expect(store.selectedProfile.assignment(at: address) == nil)
  }

  @Test func footerSeparatesLocalStorageFromDeviceDelivery() async throws {
    let file = storeURL()
    let store = ProfileStore(storageURL: file)
    let bluetooth = BluetoothController(demoMode: true)
    let controller = WorkspaceViewController(profileStore: store, bluetooth: bluetooth)
    let window = makeWindow(controller, width: 960, height: 700)
    defer { window.contentViewController = nil }
    let summary = try find("saveSummary", in: controller.view, as: NSTextField.self)
    let detail = try find("deviceWriteStatus", in: controller.view, as: NSTextField.self)
    let apply = try find("applyChanges", in: controller.view, as: NSButton.self)
    #expect(!store.hasSavedLibrary)
    #expect(summary.stringValue.hasPrefix("本地草稿"))
    let key = try find("keycap.key.k", in: controller.view, as: NSButton.self)
    key.performClick(nil)
    #expect(summary.stringValue == "已保存到本地 · 1 项待写入设备")
    #expect(detail.stringValue.contains("演示模式"))
    controller.view.layoutSubtreeIfNeeded()
    let applyFrame = apply.convert(apply.bounds, to: controller.view)
    #expect(abs(applyFrame.maxX - (controller.view.bounds.width - 14)) < 1)
    #expect(summary.frame.width > summary.intrinsicContentSize.width - 1)
    bluetooth.disconnect()
    #expect(detail.stringValue == "连接设备后可应用")
    #expect(!apply.isEnabled)
    try snapshot(controller.view, name: "saved-offline")
    bluetooth.connect(deviceID: try #require(bluetooth.devices.first?.id))
    apply.performClick(nil)
    #expect(detail.stringValue == "演示发送 1/1")
    #expect(!apply.isEnabled)
    for _ in 0..<50 where bluetooth.isBusy { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!bluetooth.isBusy)
    #expect(summary.stringValue == "已保存到本地 · 无待写入更改")
    #expect(detail.stringValue == "演示发送完成；未写入真实设备")
    try snapshot(controller.view, name: "demo-sent")

    let parent = file.deletingLastPathComponent()
    let backup = parent.appendingPathExtension("backup")
    try FileManager.default.moveItem(at: parent, to: backup)
    try Data("obstruction".utf8).write(to: parent)
    let otherKey = try find("keycap.key.a", in: controller.view, as: NSButton.self)
    otherKey.performClick(nil)
    #expect(summary.stringValue.hasPrefix("编辑未保存到本地"))
    #expect(detail.stringValue == "先恢复本地保存，再应用到设备")
    #expect(!apply.isEnabled)
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
