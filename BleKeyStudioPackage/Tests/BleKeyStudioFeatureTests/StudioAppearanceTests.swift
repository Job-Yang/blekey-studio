import AppKit
import Testing

@testable import BleKeyStudioFeature

@Suite(.serialized) @MainActor
struct StudioAppearanceTests {
  private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
  }

  private func contrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
    func luminance(_ color: NSColor) -> CGFloat {
      let rgb = color.usingColorSpace(.sRGB)!
      func linear(_ value: CGFloat) -> CGFloat {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * linear(rgb.redComponent)
        + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
    let a = luminance(first)
    let b = luminance(second)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }

  @Test func textContrastAcrossGraphiteSurfaces() {
    for surface in [AppTheme.canvasBackground, AppTheme.controlTop, AppTheme.selection] {
      #expect(contrast(AppTheme.text, surface) >= 7)
      #expect(contrast(AppTheme.secondaryText, surface) >= 4.5)
    }
    #expect(contrast(.white, AppTheme.activeKeyTop) >= 4.5)
  }

  @Test func keyboardFitsAndArrowKeysFormInvertedT() throws {
    let keyboard = KeyboardCanvasView()
    for width in [CGFloat(688), 824, 1024] {
      keyboard.frame = NSRect(x: 0, y: 0, width: width, height: 276)
      keyboard.layoutSubtreeIfNeeded()
      let keys = keyboard.subviews.compactMap { $0 as? NSButton }
      for (index, key) in keys.enumerated() {
        #expect(keyboard.bounds.contains(key.frame))
        #expect(key.frame.width > 20)
        #expect(key.frame.height > 12)
        for other in keys.dropFirst(index + 1) {
          #expect(!key.frame.intersects(other.frame))
        }
      }
      let up = try #require(keys.first { $0.identifier?.rawValue == "keycap.key.arrowUp" })
      let down = try #require(keys.first { $0.identifier?.rawValue == "keycap.key.arrowDown" })
      #expect(abs(up.frame.minX - down.frame.minX) < 0.1)
      #expect(up.frame.maxY < down.frame.minY)
    }
  }

  @Test func popupKeepsNativeMenuAndStableHeight() throws {
    let popup = StudioPopUpButton()
    popup.addItem(withTitle: "First")
    popup.lastItem?.tag = 1
    popup.addItem(withTitle: String(repeating: "Long profile ", count: 10))
    popup.lastItem?.tag = 2
    let height = popup.intrinsicContentSize.height
    popup.selectItem(withTag: 2)
    #expect(popup.selectedTag() == 2)
    #expect(popup.intrinsicContentSize.height == height)
    #expect(popup.intrinsicContentSize.width <= 240)
    popup.fixedTitle = "Copy"
    #expect(popup.selectedTag() == 2)
    #expect(try #require(popup.menu).items.count == 2)
    #expect(popup.accessibilityRole() == .popUpButton)
    #expect(popup.font?.pointSize == 13)
    #expect(popup.intrinsicContentSize.height == 34)
  }

  @Test func graphiteTypographyUsesReadableDefaultWeightsAndSizes() throws {
    let label = NSTextField.label("正文")
    let button = StudioButton(title: "操作", target: nil, action: nil)
    let popup = StudioPopUpButton()

    #expect(try #require(label.font).pointSize == 14)
    #expect(try #require(button.font).pointSize == 13)
    #expect(try #require(popup.font).pointSize == 13)
    #expect(contrast(AppTheme.secondaryText, AppTheme.canvasBackground) >= 5.5)
  }

  @Test func themedWorkspaceControlsAndResponsiveRendering() throws {
    _ = NSApplication.shared
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("profiles.json")
    let store = ProfileStore(storageURL: url)
    let demo = try #require(ProfileLibrary.demo().profiles.first)
    store.updateSelectedProfile {
      $0.mappings = demo.mappings
      $0.setAssignment(
        KeyAssignment(actionID: "key.q", modifiers: [.leftShift, .leftCommand]),
        at: MappingAddress(layer: 1, key: 1))
    }
    let controller = WorkspaceViewController(
      profileStore: store, bluetooth: BluetoothController(demoMode: true))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1120, height: 860),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1120, height: 860))
    controller.view.layoutSubtreeIfNeeded()
    #expect(controller.view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    try snapshot(controller.view, name: "graphite-mapping-native")

    let controls = descendants(controller.view)
    let layer = try #require(
      controls.first { $0.identifier?.rawValue == "layerSelector" } as? NSPopUpButton)
    layer.selectItem(withTag: 10)
    #expect(layer.sendAction(layer.action, to: layer.target))
    let key = try #require(
      controls.first { $0.identifier?.rawValue == "keycap.key.k" } as? NSButton)
    key.performClick(nil)
    #expect(
      store.selectedProfile.assignment(at: MappingAddress(layer: 10, key: 1))?.actionID == "key.k")
    layer.selectItem(withTag: 1)
    _ = layer.sendAction(layer.action, to: layer.target)

    let categories = try #require(controls.compactMap { $0 as? StudioSegmentedControl }.first)
    let point = categories.convert(NSPoint(x: 87, y: 15), to: nil)
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
    )
    categories.mouseDown(with: event)
    #expect(categories.selectedSegment == 1)
    let palette = try #require(controls.compactMap { $0 as? ActionPaletteView }.first)
    #expect(!palette.isHidden)
    try snapshot(controller.view, name: "graphite-media-native")

    let settings = try #require(
      controls.first { $0.identifier?.rawValue == "navigation.1" } as? NSButton)
    settings.performClick(nil)
    try snapshot(controller.view, name: "graphite-settings-native")
    let mappings = try #require(
      controls.first { $0.identifier?.rawValue == "navigation.0" } as? NSButton)
    mappings.performClick(nil)
    categories.selectedSegment = 0
    _ = categories.sendAction(categories.action, to: categories.target)
    window.setContentSize(NSSize(width: 960, height: 700))
    controller.view.layoutSubtreeIfNeeded()
    let keyboard = try #require(
      descendants(controller.view).compactMap { $0 as? KeyboardCanvasView }.first)
    let frameInRoot = keyboard.convert(keyboard.bounds, to: controller.view)
    #expect(frameInRoot.minX >= 0)
    #expect(frameInRoot.maxX <= controller.view.bounds.width + 1)
    try snapshot(controller.view, name: "graphite-compact-native")
    window.contentViewController = nil
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
