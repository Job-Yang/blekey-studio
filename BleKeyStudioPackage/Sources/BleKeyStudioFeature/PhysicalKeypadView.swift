import AppKit

final class PhysicalKeypadView: NSView {
  var onKeySelected: ((Int) -> Void)?

  var keyCount = 3 {
    didSet {
      if keyCount != oldValue {
        rebuild()
      }
    }
  }
  var selectedKey = 1 {
    didSet { updateButtons() }
  }
  var assignments: [Int: KeyAssignment] = [:] {
    didSet { updateButtons() }
  }
  var dirtyKeys = Set<Int>() {
    didSet { updateButtons() }
  }

  private var buttons: [PhysicalKeyButton] = []

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityRole(.group)
    setAccessibilityLabel("实体小键盘")
    rebuild()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isFlipped: Bool { true }

  override var intrinsicContentSize: NSSize {
    let rows = ceil(Double(keyCount) / 3.0)
    return NSSize(width: 206, height: rows * 80 + max(0, rows - 1) * 8)
  }

  override func layout() {
    super.layout()
    let columns = min(3, max(1, keyCount))
    let gap: CGFloat = 8
    let width = (bounds.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
    let height: CGFloat = 80

    for (index, button) in buttons.enumerated() {
      let row = index / columns
      let column = index % columns
      button.frame = NSRect(
        x: CGFloat(column) * (width + gap),
        y: CGFloat(row) * (height + gap),
        width: width,
        height: height
      )
    }
  }

  private func rebuild() {
    for button in buttons {
      button.removeFromSuperview()
    }
    buttons = (1...keyCount).map { number in
      let button = PhysicalKeyButton(number: number)
      button.target = self
      button.action = #selector(keyPressed(_:))
      addSubview(button)
      return button
    }
    invalidateIntrinsicContentSize()
    updateButtons()
    needsLayout = true
  }

  private func updateButtons() {
    for button in buttons {
      button.isSelectedKey = button.number == selectedKey
      button.assignmentText = XKeyProtocol.displayName(for: assignments[button.number])
      button.isDirty = dirtyKeys.contains(button.number)
    }
  }

  @objc private func keyPressed(_ sender: PhysicalKeyButton) {
    selectedKey = sender.number
    onKeySelected?(sender.number)
  }
}

private final class PhysicalKeyButton: NSButton {
  let number: Int
  var assignmentText = "未设置" {
    didSet { needsDisplay = true }
  }
  var isSelectedKey = false {
    didSet { needsDisplay = true }
  }
  var isDirty = false {
    didSet { needsDisplay = true }
  }

  init(number: Int) {
    self.number = number
    super.init(frame: .zero)
    isBordered = false
    focusRingType = .exterior
    title = ""
    identifier = NSUserInterfaceItemIdentifier("sourceKey.\(number)")
    setAccessibilityRole(.button)
    setAccessibilityLabel("实体按键 \(number)")
    toolTip = "编辑按键 \(number)"
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 1, dy: 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
    let fill = isSelectedKey ? AppTheme.accentFill : AppTheme.controlBottom
    let stroke = isSelectedKey ? AppTheme.accent : AppTheme.hairline
    fill.setFill()
    path.fill()
    stroke.setStroke()
    path.lineWidth = isSelectedKey ? 1.5 : 1
    path.stroke()

    let numberText = NSAttributedString(
      string: "\(number)",
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor.labelColor,
      ]
    )
    let numberSize = numberText.size()
    numberText.draw(
      at: NSPoint(
        x: rect.midX - numberSize.width / 2,
        y: rect.minY + 31
      )
    )

    let assignment = NSAttributedString(
      string: assignmentText,
      attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: AppTheme.secondaryText,
      ]
    )
    let assignmentSize = assignment.size()
    assignment.draw(
      in: NSRect(
        x: rect.minX + 4,
        y: rect.minY + 10,
        width: rect.width - 8,
        height: min(14, assignmentSize.height)
      )
    )

    if isDirty {
      let marker = NSBezierPath(
        ovalIn: NSRect(x: rect.maxX - 10, y: rect.minY + 5, width: 5, height: 5)
      )
      AppTheme.pending.setFill()
      marker.fill()
    }
  }
}
