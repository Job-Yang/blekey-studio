import AppKit

enum AppTheme {
  static let accent = NSColor(srgbRed: 0.96, green: 0.29, blue: 0.20, alpha: 1)
  static let activeKeyTop = NSColor(srgbRed: 0.84, green: 0.20, blue: 0.13, alpha: 1)
  static let accentFill = NSColor(srgbRed: 0.24, green: 0.14, blue: 0.13, alpha: 1)
  static let pending = NSColor(srgbRed: 0.94, green: 0.67, blue: 0.34, alpha: 1)
  static let connected = NSColor(srgbRed: 0.40, green: 0.80, blue: 0.57, alpha: 1)
  static let text = gray(0.98)
  static let secondaryText = gray(0.76)
  static let tertiaryText = gray(0.58)
  static let hairline = NSColor(white: 1, alpha: 0.075)
  static let panelBackground = gray(0.065)
  static let canvasBackground = gray(0.09)
  static let well = gray(0.035)
  static let controlTop = gray(0.225)
  static let controlBottom = gray(0.18)
  static let selection = gray(0.16)

  static func gray(_ value: CGFloat) -> NSColor {
    NSColor(srgbRed: value, green: value, blue: value, alpha: 1)
  }

  static func controlSurface(
    in rect: NSRect, pressed: Bool = false, hovered: Bool = false,
    primary: Bool = false, enabled: Bool = true
  ) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
    let top: NSColor
    let bottom: NSColor
    if primary && enabled {
      top = activeKeyTop
      bottom = NSColor(srgbRed: 0.77, green: 0.19, blue: 0.13, alpha: 1)
    } else {
      top = gray(pressed ? 0.16 : (hovered ? 0.28 : 0.225))
      bottom = gray(pressed ? 0.17 : (hovered ? 0.23 : 0.18))
    }
    NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: 90)
    NSColor(white: 0, alpha: 0.45).setStroke()
    path.lineWidth = 1
    path.stroke()
    let inset = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
    NSColor(white: 1, alpha: pressed ? 0.03 : 0.07).setStroke()
    inset.stroke()
  }

  static func drawText(
    _ text: String, in rect: NSRect, font: NSFont, color: NSColor,
    alignment: NSTextAlignment = .left
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    let string = NSAttributedString(
      string: text,
      attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
      ])
    string.draw(
      in: NSRect(
        x: rect.minX, y: rect.midY - string.size().height / 2,
        width: rect.width, height: string.size().height))
  }

  static func drawSymbol(_ image: NSImage?, in rect: NSRect, color: NSColor) {
    image?.withSymbolConfiguration(.init(paletteColors: [color]))?
      .draw(
        in: rect, from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: true, hints: nil)
  }

  static func keycap(
    in rect: NSRect, active: Bool = false, pressed: Bool = false,
    hovered: Bool = false, enabled: Bool = true, concave: Bool = true
  ) {
    let radius: CGFloat = 5
    let base = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    gray(0.045).setFill()
    base.fill()
    let faceRect = NSRect(
      x: rect.minX + 1, y: rect.minY + (pressed ? 2 : 0.5),
      width: rect.width - 2, height: rect.height - (pressed ? 3 : 4))
    let face = NSBezierPath(roundedRect: faceRect, xRadius: radius, yRadius: radius)
    let top = active ? activeKeyTop : gray(hovered ? 0.31 : (enabled ? 0.265 : 0.19))
    let bottom =
      active
      ? NSColor(srgbRed: 0.73, green: 0.13, blue: 0.085, alpha: 1)
      : gray(hovered ? 0.25 : (enabled ? 0.195 : 0.155))
    NSGradient(starting: top, ending: bottom)?.draw(in: face, angle: 90)
    NSColor(white: 1, alpha: active ? 0.17 : 0.085).setStroke()
    face.lineWidth = 0.8
    face.stroke()
    if concave && faceRect.height > 24 {
      let dish = NSBezierPath(
        ovalIn: faceRect.insetBy(
          dx: faceRect.width * 0.13,
          dy: faceRect.height * 0.08))
      NSGradient(
        starting: NSColor(white: 0, alpha: active ? 0.12 : 0.28),
        ending: .clear)?
        .draw(in: dish, relativeCenterPosition: NSPoint(x: 0, y: -0.45))
      NSGradient(
        starting: NSColor(white: 1, alpha: active ? 0.04 : 0.07),
        ending: .clear)?
        .draw(in: dish, relativeCenterPosition: NSPoint(x: 0, y: 0.65))
    }
  }

  static func symbol(
    _ name: String,
    accessibilityDescription: String? = nil
  ) -> NSImage? {
    NSImage(
      systemSymbolName: name,
      accessibilityDescription: accessibilityDescription
    )
  }
}

extension NSView {
  func pinEdges(
    to other: NSView,
    insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  ) {
    translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
      trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
      topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
      bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
    ])
  }
}

extension NSStackView {
  static func vertical(
    spacing: CGFloat = 8,
    alignment: NSLayoutConstraint.Attribute = .leading
  ) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = spacing
    stack.alignment = alignment
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }

  static func horizontal(
    spacing: CGFloat = 8,
    alignment: NSLayoutConstraint.Attribute = .centerY
  ) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.spacing = spacing
    stack.alignment = alignment
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
  }
}

extension NSTextField {
  static func label(
    _ text: String,
    font: NSFont = .systemFont(ofSize: 14, weight: .medium),
    color: NSColor = AppTheme.text
  ) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor =
      color == .secondaryLabelColor
      ? AppTheme.secondaryText
      : (color == .tertiaryLabelColor ? AppTheme.tertiaryText : color)
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }
}

extension NSButton {
  static func symbolButton(
    _ symbolName: String,
    label: String,
    target: AnyObject?,
    action: Selector?
  ) -> NSButton {
    let button = StudioButton()
    button.image = AppTheme.symbol(symbolName, accessibilityDescription: label)
    button.title = ""
    button.target = target
    button.action = action
    button.treatment = .quiet
    button.isBordered = false
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = label
    button.setAccessibilityLabel(label)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 28),
      button.heightAnchor.constraint(equalToConstant: 28),
    ])
    return button
  }
}
