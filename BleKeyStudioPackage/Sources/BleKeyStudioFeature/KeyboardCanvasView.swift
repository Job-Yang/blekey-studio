import AppKit

final class KeyboardCanvasView: NSView {
  var onActionSelected: ((KeyAction?) -> Void)?
  var onModifierChanged: ((Set<KeyModifier>) -> Void)?

  var selectedActionID: String? {
    didSet { updateKeycapStates() }
  }
  var activeModifiers = Set<KeyModifier>() {
    didSet { updateKeycapStates() }
  }

  private let rows = KeyboardLayout.rows
  private var keycaps: [(button: KeycapButton, spec: KeyboardKeySpec)] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    setAccessibilityRole(.group)
    setAccessibilityLabel("MacBook Pro 键盘")

    for spec in rows.flatMap({ $0 }) {
      let button = KeycapButton(spec: spec)
      button.target = self
      button.action = #selector(keyPressed(_:))
      addSubview(button)
      keycaps.append((button, spec))
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 276)
  }

  override func draw(_ dirtyRect: NSRect) {
    let body = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
    NSGradient(
      starting: AppTheme.gray(0.195),
      ending: AppTheme.gray(0.115))?.draw(in: body, angle: 90)
    NSColor(white: 1, alpha: 0.12).setStroke()
    body.stroke()
    let bed = NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 10), xRadius: 6, yRadius: 6)
    AppTheme.well.setFill()
    bed.fill()
    NSColor(white: 0, alpha: 0.65).setStroke()
    bed.stroke()
  }

  override func layout() {
    super.layout()

    let horizontalPadding: CGFloat = 16
    let verticalPadding: CGFloat = 16
    let gap: CGFloat = 4
    let availableWidth = max(1, bounds.width - horizontalPadding * 2)
    let rowGap: CGFloat = 4
    let keyHeight = max(1, (bounds.height - verticalPadding * 2 - rowGap * 5) / 5.78)

    var index = 0
    var y = verticalPadding
    for (rowIndex, row) in rows.enumerated() {
      let isBottom = rowIndex == rows.count - 1
      let upUnits = isBottom ? CGFloat(0.9) : 0
      let rowUnits = row.reduce(CGFloat.zero) { $0 + $1.widthUnits } - upUnits
      let columnCount = row.count - (isBottom ? 1 : 0)
      let unit = (availableWidth - CGFloat(columnCount - 1) * gap) / rowUnits
      var x = horizontalPadding
      let height = rowIndex == 0 ? keyHeight * 0.78 : keyHeight

      for spec in row {
        let width = spec.widthUnits * unit
        var frame = NSRect(x: x, y: y, width: width, height: height)
        if case .action(let id) = spec.kind, isBottom {
          if id == "key.arrowUp" {
            frame.origin.x -= width + gap
            frame.size.height = (height - gap) / 2
          } else if id.hasPrefix("key.arrow") {
            frame.origin.y += (height + gap) / 2
            frame.size.height = (height - gap) / 2
          }
        }
        keycaps[index].button.frame = frame
        if case .action("key.arrowUp") = spec.kind {
          // Up and down share the middle column of the inverted-T cluster.
        } else {
          x += width + gap
        }
        index += 1
      }
      y += height + rowGap
    }
  }

  @objc private func keyPressed(_ sender: KeycapButton) {
    let spec = sender.spec
    // #region debug-point A-C:keyboard-click
    if let url = URL(string: "http://127.0.0.1:7777/event"),
      let body = try? JSONSerialization.data(withJSONObject: [
        "sessionId": "mapping-activity-log",
        "runId": "post-fix",
        "hypothesisId": "A,C",
        "location": "KeyboardCanvasView.keyPressed",
        "msg": "[DEBUG] Graphical keyboard click",
        "data": [
          "legend": spec.legend,
          "selectedActionID": selectedActionID ?? "nil",
          "activeModifiers": KeyModifier.normalized(activeModifiers).map(\.displayName)
            .joined(separator: " "),
        ],
      ])
    {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      URLSession.shared.uploadTask(with: request, from: body).resume()
    }
    // #endregion
    switch spec.kind {
    case .action(let actionID):
      guard let action = ActionCatalog.action(id: actionID) else { return }
      onActionSelected?(selectedActionID == actionID ? nil : action)
    case .modifier(let modifier):
      if activeModifiers.contains(modifier) {
        activeModifiers.remove(modifier)
      } else {
        activeModifiers.insert(modifier)
      }
      onModifierChanged?(activeModifiers)
    case .disabled:
      NSSound.beep()
    }
  }

  private func updateKeycapStates() {
    for item in keycaps {
      switch item.spec.kind {
      case .action(let actionID):
        item.button.isActive = selectedActionID == actionID
      case .modifier(let modifier):
        item.button.isActive = activeModifiers.contains(modifier)
      case .disabled:
        item.button.isActive = false
      }
    }
  }
}

private final class KeycapButton: NSButton {
  let spec: KeyboardKeySpec
  var isActive = false {
    didSet { needsDisplay = true }
  }

  private var isHovering = false {
    didSet { needsDisplay = true }
  }
  private var trackingAreaReference: NSTrackingArea?

  init(spec: KeyboardKeySpec) {
    self.spec = spec
    super.init(frame: .zero)
    title = spec.legend
    isBordered = false
    bezelStyle = .regularSquare
    alignment = .center
    font = .systemFont(ofSize: spec.compact ? 10 : 12, weight: .semibold)
    imagePosition = .imageAbove
    focusRingType = .exterior
    setButtonType(.momentaryChange)
    setAccessibilityRole(.button)
    setAccessibilityLabel(spec.accessibilityLabel)
    toolTip = spec.toolTip
    switch spec.kind {
    case .action(let actionID):
      identifier = NSUserInterfaceItemIdentifier("keycap.\(actionID)")
    case .modifier(let modifier):
      identifier = NSUserInterfaceItemIdentifier("keycap.modifier.\(modifier.rawValue)")
    case .disabled:
      identifier = NSUserInterfaceItemIdentifier("keycap.disabled.\(spec.legend)")
      isEnabled = false
    }
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaReference {
      removeTrackingArea(trackingAreaReference)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInKeyWindow],
      owner: self
    )
    addTrackingArea(area)
    trackingAreaReference = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovering = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovering = false
  }

  override func draw(_ dirtyRect: NSRect) {
    AppTheme.keycap(
      in: bounds.insetBy(dx: 0.5, dy: 0.5), active: isActive,
      pressed: isHighlighted, hovered: isHovering, enabled: isEnabled,
      concave: spec.widthUnits < 1.4 && !spec.compact)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font ?? NSFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: isEnabled
        ? (isActive ? NSColor.white : AppTheme.text) : AppTheme.tertiaryText,
      .paragraphStyle: paragraph,
    ]
    let string = NSAttributedString(string: title, attributes: attributes)
    let size = string.size()
    let rect = NSRect(
      x: 3,
      y: (bounds.height - size.height) / 2 - (isHighlighted ? 0 : 1),
      width: bounds.width - 6,
      height: size.height
    )
    string.draw(in: rect)
    if case .action(let id) = spec.kind, id == "key.f" || id == "key.j" {
      NSColor(white: 1, alpha: 0.16).setFill()
      NSBezierPath(
        roundedRect: NSRect(
          x: bounds.midX - 4, y: bounds.maxY - 8,
          width: 8, height: 1.5), xRadius: 0.75, yRadius: 0.75
      ).fill()
    }
  }
}

private struct KeyboardKeySpec {
  enum Kind {
    case action(String)
    case modifier(KeyModifier)
    case disabled
  }

  let legend: String
  let widthUnits: CGFloat
  let kind: Kind
  let accessibilityLabel: String
  let toolTip: String?
  let compact: Bool

  init(
    _ legend: String,
    width: CGFloat = 1,
    action: String,
    accessibilityLabel: String? = nil,
    toolTip: String? = nil,
    compact: Bool = false
  ) {
    self.legend = legend
    widthUnits = width
    kind = .action(action)
    self.accessibilityLabel = accessibilityLabel ?? legend
    self.toolTip = toolTip
    self.compact = compact
  }

  init(
    _ legend: String,
    width: CGFloat = 1,
    modifier: KeyModifier,
    compact: Bool = false
  ) {
    self.legend = legend
    widthUnits = width
    kind = .modifier(modifier)
    accessibilityLabel = modifier.accessibilityName
    toolTip = "点击可加入或移除\(modifier.accessibilityName)"
    self.compact = compact
  }

  init(disabled legend: String, width: CGFloat = 1, toolTip: String) {
    self.legend = legend
    widthUnits = width
    kind = .disabled
    accessibilityLabel = legend
    self.toolTip = toolTip
    compact = true
  }
}

private enum KeyboardLayout {
  static let rows: [[KeyboardKeySpec]] = [
    [
      k("esc", 1.2, "escape"), k("F1", 1, "f1", true), k("F2", 1, "f2", true),
      k("F3", 1, "f3", true), k("F4", 1, "f4", true), k("F5", 1, "f5", true),
      k("F6", 1, "f6", true), k("F7", 1, "f7", true), k("F8", 1, "f8", true),
      k("F9", 1, "f9", true), k("F10", 1, "f10", true), k("F11", 1, "f11", true),
      k("F12", 1, "f12", true),
      KeyboardKeySpec(disabled: "Touch ID", width: 1.45, toolTip: "设备协议不支持 Touch ID"),
    ],
    [
      k("`", 1, "grave"), k("1", 1, "1"), k("2", 1, "2"), k("3", 1, "3"),
      k("4", 1, "4"), k("5", 1, "5"), k("6", 1, "6"), k("7", 1, "7"),
      k("8", 1, "8"), k("9", 1, "9"), k("0", 1, "0"), k("−", 1, "minus"),
      k("=", 1, "equal"), k("⌫", 1.75, "deleteBackward"),
    ],
    [
      k("tab", 1.5, "tab"), k("Q", 1, "q"), k("W", 1, "w"), k("E", 1, "e"),
      k("R", 1, "r"), k("T", 1, "t"), k("Y", 1, "y"), k("U", 1, "u"),
      k("I", 1, "i"), k("O", 1, "o"), k("P", 1, "p"), k("[", 1, "leftBracket"),
      k("]", 1, "rightBracket"), k("\\", 1.25, "backslash"),
    ],
    [
      k("caps", 1.8, "capsLock"), k("A", 1, "a"), k("S", 1, "s"), k("D", 1, "d"),
      k("F", 1, "f"), k("G", 1, "g"), k("H", 1, "h"), k("J", 1, "j"),
      k("K", 1, "k"), k("L", 1, "l"), k(";", 1, "semicolon"), k("'", 1, "quote"),
      k("return", 2.05, "return"),
    ],
    [
      KeyboardKeySpec("⇧", width: 2.35, modifier: .leftShift),
      k("Z", 1, "z"), k("X", 1, "x"), k("C", 1, "c"), k("V", 1, "v"),
      k("B", 1, "b"), k("N", 1, "n"), k("M", 1, "m"), k(",", 1, "comma"),
      k(".", 1, "period"), k("/", 1, "slash"),
      KeyboardKeySpec("⇧", width: 2.55, modifier: .rightShift),
    ],
    [
      KeyboardKeySpec(disabled: "fn", width: 1, toolTip: "Fn 不属于 USB HID 修饰键"),
      KeyboardKeySpec("⌃", width: 1, modifier: .leftControl),
      KeyboardKeySpec("⌥", width: 1, modifier: .leftOption),
      KeyboardKeySpec("⌘", width: 1.25, modifier: .leftCommand),
      k("space", 5.2, "space"),
      KeyboardKeySpec("⌘", width: 1.25, modifier: .rightCommand),
      KeyboardKeySpec("⌥", width: 1, modifier: .rightOption),
      k("←", 0.9, "arrowLeft"), k("↓", 0.9, "arrowDown"),
      k("↑", 0.9, "arrowUp"), k("→", 0.9, "arrowRight"),
    ],
  ]

  private static func k(
    _ legend: String,
    _ width: CGFloat,
    _ id: String,
    _ compact: Bool = false
  ) -> KeyboardKeySpec {
    KeyboardKeySpec(
      legend,
      width: width,
      action: "key.\(id)",
      compact: compact
    )
  }
}
