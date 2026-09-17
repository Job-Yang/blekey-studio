import AppKit

final class ShortcutRecorderView: NSControl {
  var assignment: KeyAssignment? {
    didSet {
      if oldValue != assignment { cancelRecording() }
      updateFeedback()
    }
  }
  var onRecorded: ((KeyAssignment) -> Void)?

  private(set) var isRecording = false
  private(set) var heldModifiers = Set<KeyModifier>()
  private let cancelButton = StudioButton()
  private var windowObserver: NSObjectProtocol?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    focusRingType = .exterior
    identifier = NSUserInterfaceItemIdentifier("shortcutRecorder")
    toolTip = "点击后直接按下要映射的快捷键"
    setAccessibilityRole(.textField)
    setAccessibilityLabel("快捷键录入")
    cancelButton.title = ""
    cancelButton.image = AppTheme.symbol("xmark")
    cancelButton.treatment = .quiet
    cancelButton.toolTip = "取消录入"
    cancelButton.setAccessibilityLabel("取消录入")
    cancelButton.identifier = NSUserInterfaceItemIdentifier("cancelRecording")
    cancelButton.target = self
    cancelButton.action = #selector(cancelRecording)
    cancelButton.isHidden = true
    addSubview(cancelButton)
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit {
    if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
  }

  override var isEnabled: Bool {
    didSet { if !isEnabled { cancelRecording() } }
  }
  override var acceptsFirstResponder: Bool { isEnabled }
  override var isFlipped: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
    windowObserver = nil
    guard let window else {
      endRecording()
      return
    }
    windowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: window, queue: .main
    ) { [weak self] _ in self?.cancelRecording() }
  }

  override func layout() {
    super.layout()
    cancelButton.frame = NSRect(x: bounds.width - 39, y: bounds.midY - 15, width: 30, height: 30)
  }

  override func becomeFirstResponder() -> Bool {
    guard isEnabled else { return false }
    isRecording = true
    heldModifiers = []
    updateFeedback()
    return true
  }

  override func resignFirstResponder() -> Bool {
    endRecording()
    return true
  }

  override func mouseDown(with event: NSEvent) {
    startRecording()
  }

  func startRecording() {
    guard isEnabled else { return }
    if window?.firstResponder === self {
      _ = becomeFirstResponder()
    } else {
      window?.makeFirstResponder(self)
    }
  }

  @objc func cancelRecording() {
    endRecording()
    if window?.firstResponder === self { window?.makeFirstResponder(nil) }
  }

  private func endRecording() {
    isRecording = false
    heldModifiers = []
    updateFeedback()
  }

  private func updateFeedback() {
    needsDisplay = true
    cancelButton.isHidden = !isRecording
    let modifiers = KeyModifier.normalized(heldModifiers).map(\.displayName).joined(separator: " ")
    setAccessibilityValue(
      isRecording ? "\(modifiers) 等待按键" : XKeyProtocol.displayName(for: assignment))
  }

  override func keyDown(with event: NSEvent) {
    guard isEnabled, isRecording, !event.isARepeat else { return }
    guard let action = ActionCatalog.keyboardAction(for: event) else {
      NSSound.beep()
      return
    }
    let modifiers = ActionCatalog.modifiers(for: event)
    let value = KeyAssignment(actionID: action.id, modifiers: modifiers)
    endRecording()
    assignment = value
    onRecorded?(value)
    window?.makeFirstResponder(nil)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isEnabled, isRecording, window?.firstResponder === self else { return false }
    keyDown(with: event)
    return true
  }

  override func flagsChanged(with event: NSEvent) {
    guard isEnabled, isRecording else { return }
    heldModifiers = ActionCatalog.modifiers(for: event)
    updateFeedback()
  }

  override func draw(_ dirtyRect: NSRect) {
    let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
    let border = isRecording ? AppTheme.accent : AppTheme.hairline
    let fill = AppTheme.well

    fill.setFill()
    path.fill()
    border.setStroke()
    path.lineWidth = isRecording ? 2 : 1
    path.stroke()

    if isRecording {
      if heldModifiers.isEmpty {
        drawPlaceholder()
      } else {
        drawTokens(KeyModifier.normalized(heldModifiers).map(\.displayName), waiting: true)
      }
      return
    }
    guard let assignment,
      let action = ActionCatalog.action(id: assignment.actionID)
    else {
      drawPlaceholder()
      return
    }

    var tokens = assignment.modifiers.map(\.displayName)
    if !action.keycap.isEmpty {
      tokens.append(action.keycap)
    }
    drawTokens(tokens)
  }

  private func drawPlaceholder() {
    let title = isRecording ? "等待按键…" : "录入快捷键"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 14, weight: .medium),
      .foregroundColor: AppTheme.secondaryText,
    ]
    let string = NSAttributedString(string: title, attributes: attributes)
    let size = string.size()
    string.draw(
      at: NSPoint(
        x: 14,
        y: (bounds.height - size.height) / 2
      )
    )
  }

  private func drawTokens(_ tokens: [String], waiting: Bool = false) {
    var x: CGFloat = 12
    let availableWidth = bounds.width - (isRecording ? 48 : 12)
    let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
    for token in tokens {
      let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: AppTheme.text,
      ]
      let string = NSAttributedString(string: token, attributes: attributes)
      let textSize = string.size()
      let width = max(28, textSize.width + 14)
      guard x + width <= availableWidth else { break }
      let frame = NSRect(
        x: x,
        y: (bounds.height - 28) / 2,
        width: width,
        height: 28
      )
      AppTheme.keycap(in: frame, concave: false)
      string.draw(
        at: NSPoint(
          x: frame.midX - textSize.width / 2,
          y: frame.midY - textSize.height / 2 - 1
        )
      )
      x += width + 6
    }

    let hint = waiting ? "等待主键…" : "重新录入"
    let hintAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .medium),
      .foregroundColor: AppTheme.secondaryText,
    ]
    let hintString = NSAttributedString(string: hint, attributes: hintAttributes)
    let hintSize = hintString.size()
    guard x + hintSize.width + 12 < availableWidth else { return }
    hintString.draw(
      at: NSPoint(
        x: waiting ? x + 4 : bounds.maxX - hintSize.width - 12,
        y: (bounds.height - hintSize.height) / 2
      )
    )
  }
}
