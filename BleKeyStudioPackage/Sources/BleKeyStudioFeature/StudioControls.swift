import AppKit

final class StudioButton: NSButton {
  enum Treatment { case standard, quiet, navigation, primary }
  var treatment: Treatment = .standard { didSet { needsDisplay = true } }
  private var hovering = false { didSet { needsDisplay = true } }
  private var hoverArea: NSTrackingArea?

  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false
    font = .systemFont(ofSize: 13, weight: .semibold)
    focusRingType = .exterior
    setButtonType(.momentaryPushIn)
    setAccessibilityRole(.button)
  }

  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }

  override var intrinsicContentSize: NSSize {
    let textWidth = (title as NSString).size(withAttributes: [.font: font!]).width
    return NSSize(width: max(32, textWidth + (image == nil ? 0 : 22) + 24), height: 32)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [
        .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
      ], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) { hovering = true }
  override func mouseExited(with event: NSEvent) { hovering = false }

  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 0.5, dy: 1.5)
    let selected = state == .on
    if treatment == .standard || treatment == .primary {
      AppTheme.controlSurface(
        in: rect, pressed: isHighlighted, hovered: hovering,
        primary: treatment == .primary, enabled: isEnabled)
    } else if selected || (hovering && isEnabled) || isHighlighted {
      (selected ? AppTheme.selection : NSColor(white: 1, alpha: 0.035)).setFill()
      NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
      if treatment == .navigation && selected {
        AppTheme.accent.setFill()
        NSBezierPath(
          roundedRect: NSRect(x: 0, y: bounds.midY - 7, width: 2, height: 14),
          xRadius: 1, yRadius: 1
        ).fill()
      }
    }
    let color: NSColor
    if !isEnabled {
      color = AppTheme.tertiaryText
    } else if treatment == .primary {
      color = .white
    } else if treatment == .quiet && !selected {
      color = AppTheme.secondaryText
    } else {
      color = AppTheme.text
    }
    let iconSize: CGFloat = treatment == .navigation ? 16 : 14
    let measuredText = (title as NSString).size(withAttributes: [.font: font!]).width
    let groupWidth = measuredText + (image == nil ? 0 : iconSize + (title.isEmpty ? 0 : 7))
    let start = treatment == .navigation ? 12 : max(10, (bounds.width - groupWidth) / 2)
    if image != nil {
      AppTheme.drawSymbol(
        image,
        in: NSRect(
          x: title.isEmpty ? bounds.midX - iconSize / 2 : start,
          y: bounds.midY - iconSize / 2,
          width: iconSize, height: iconSize),
        color: selected && treatment == .navigation ? AppTheme.accent : color)
    }
    if !title.isEmpty {
      let x = start + (image == nil ? 0 : iconSize + 7)
      AppTheme.drawText(
        title,
        in: NSRect(
          x: x, y: 0, width: max(0, bounds.width - x - 10),
          height: bounds.height),
        font: font!, color: color)
    }
  }
}

// Keep NSPopUpButton's native menu, keyboard handling and accessibility.
// Only the closed control is drawn here; commands still use their NSMenuItem targets.
final class StudioPopUpButton: NSPopUpButton {
  var symbolName: String? {
    didSet {
      needsDisplay = true
      invalidateIntrinsicContentSize()
    }
  }
  var fixedTitle: String? {
    didSet {
      needsDisplay = true
      invalidateIntrinsicContentSize()
    }
  }
  private var hovering = false { didSet { needsDisplay = true } }
  private var hoverArea: NSTrackingArea?

  convenience init() {
    self.init(frame: .zero, pullsDown: false)
  }

  override init(frame: NSRect, pullsDown flag: Bool) {
    super.init(frame: frame, pullsDown: flag)
    isBordered = false
    font = .systemFont(ofSize: 13, weight: .semibold)
    focusRingType = .exterior
    setAccessibilityRole(.popUpButton)
  }

  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }

  private var displayTitle: String { fixedTitle ?? titleOfSelectedItem ?? title }

  override var intrinsicContentSize: NSSize {
    let textWidth = (displayTitle as NSString).size(withAttributes: [.font: font!]).width
    return NSSize(
      width: min(240, max(90, textWidth + 42 + (symbolName == nil ? 0 : 23))),
      height: 34)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [
        .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
      ], owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseEntered(with event: NSEvent) { hovering = true }
  override func mouseExited(with event: NSEvent) { hovering = false }

  override func draw(_ dirtyRect: NSRect) {
    AppTheme.controlSurface(
      in: bounds.insetBy(dx: 0.5, dy: 1.5),
      pressed: isHighlighted, hovered: hovering && isEnabled)
    let color = isEnabled ? AppTheme.text : AppTheme.tertiaryText
    let x: CGFloat = symbolName == nil ? 11 : 33
    if let symbolName {
      AppTheme.drawSymbol(
        AppTheme.symbol(symbolName),
        in: NSRect(x: 11, y: bounds.midY - 7, width: 14, height: 14),
        color: isEnabled ? AppTheme.secondaryText : AppTheme.tertiaryText)
    }
    AppTheme.drawText(
      displayTitle,
      in: NSRect(x: x, y: 0, width: max(0, bounds.width - x - 34), height: bounds.height),
      font: font!, color: color)
    AppTheme.hairline.setFill()
    NSRect(x: bounds.width - 31, y: 7, width: 1, height: bounds.height - 14).fill()
    let indicator = AppTheme.symbol("chevron.up.chevron.down")?.withSymbolConfiguration(
      NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
    )
    AppTheme.drawSymbol(
      indicator,
      in: NSRect(x: bounds.width - 23, y: bounds.midY - 7, width: 14, height: 14),
      color: isEnabled ? AppTheme.text : AppTheme.tertiaryText)
  }
}

final class StudioSegmentedControl: NSSegmentedControl {
  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize {
    NSSize(width: (0..<segmentCount).reduce(0) { $0 + width(forSegment: $1) }, height: 32)
  }

  override func draw(_ dirtyRect: NSRect) {
    let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 1), xRadius: 6, yRadius: 6)
    AppTheme.well.setFill()
    outer.fill()
    AppTheme.hairline.setStroke()
    outer.stroke()
    var x: CGFloat = 0
    for segment in 0..<segmentCount {
      let width = width(forSegment: segment)
      let frame = NSRect(x: x + 2, y: 3, width: width - 4, height: bounds.height - 6)
      if segment == selectedSegment {
        AppTheme.controlSurface(in: frame)
      }
      AppTheme.drawText(
        label(forSegment: segment) ?? "", in: frame,
        font: .systemFont(ofSize: 13, weight: .semibold),
        color: segment == selectedSegment ? AppTheme.text : AppTheme.secondaryText,
        alignment: .center)
      x += width
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    let location = convert(event.locationInWindow, from: nil)
    var x: CGFloat = 0
    for segment in 0..<segmentCount {
      let width = width(forSegment: segment)
      if location.x >= x && location.x < x + width && isEnabled(forSegment: segment) {
        selectedSegment = segment
        window?.makeFirstResponder(self)
        needsDisplay = true
        sendAction(action, to: target)
        return
      }
      x += width
    }
  }
}

final class StudioSurface: NSView {
  let fill: NSColor
  let bottomSeparator: Bool

  init(_ fill: NSColor, bottomSeparator: Bool = false) {
    self.fill = fill
    self.bottomSeparator = bottomSeparator
    super.init(frame: .zero)
    wantsLayer = true
  }

  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    fill.setFill()
    bounds.fill()
    if bottomSeparator {
      AppTheme.hairline.setFill()
      NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
  }
}

final class StudioTableHeaderCell: NSTableHeaderCell {
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    AppTheme.canvasBackground.setFill()
    cellFrame.fill()
    AppTheme.drawText(
      stringValue, in: cellFrame.insetBy(dx: 10, dy: 0),
      font: .systemFont(ofSize: 12, weight: .semibold), color: AppTheme.secondaryText)
    AppTheme.hairline.setFill()
    NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
  }
}

final class StudioTableRow: NSTableRowView {
  override func drawBackground(in dirtyRect: NSRect) {
    AppTheme.canvasBackground.setFill()
    bounds.fill()
    AppTheme.hairline.setFill()
    NSRect(x: 10, y: bounds.maxY - 1, width: bounds.width - 20, height: 0.5).fill()
  }

  override func drawSelection(in dirtyRect: NSRect) {
    AppTheme.selection.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
    AppTheme.accent.setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 1, y: bounds.midY - 9, width: 2, height: 18),
      xRadius: 1, yRadius: 1
    ).fill()
  }

  override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
