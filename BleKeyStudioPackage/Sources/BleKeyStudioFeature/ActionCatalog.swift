import AppKit
import Foundation

public enum ActionCatalog {
  public static let all: [KeyAction] = keyboard + media + pointer + system
  public static let modifierOnly = KeyAction(
    id: "key.modifiers",
    name: "仅修饰键",
    keycap: "",
    detail: "只发送所选修饰键",
    code: 0x00,
    category: .keyboard,
    symbolName: "command"
  )

  public static let keyboard: [KeyAction] = {
    var actions: [KeyAction] = [modifierOnly]

    for (offset, letter) in Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").enumerated() {
      let value = String(letter)
      actions.append(
        KeyAction(
          id: "key.\(value.lowercased())",
          name: value,
          keycap: value,
          code: UInt8(0x04 + offset),
          category: .keyboard
        )
      )
    }

    let numbers: [(String, UInt8)] = [
      ("1", 0x1E), ("2", 0x1F), ("3", 0x20), ("4", 0x21), ("5", 0x22),
      ("6", 0x23), ("7", 0x24), ("8", 0x25), ("9", 0x26), ("0", 0x27),
    ]
    actions.append(
      contentsOf: numbers.map {
        KeyAction(id: "key.\($0.0)", name: $0.0, keycap: $0.0, code: $0.1, category: .keyboard)
      })

    actions.append(contentsOf: [
      key("return", "Return", "↩", 0x28),
      key("escape", "Escape", "esc", 0x29),
      key("deleteBackward", "向前删除", "⌫", 0x2A),
      key("tab", "Tab", "⇥", 0x2B),
      key("space", "空格", "space", 0x2C),
      key("minus", "减号", "−", 0x2D),
      key("equal", "等号", "=", 0x2E),
      key("leftBracket", "左方括号", "[", 0x2F),
      key("rightBracket", "右方括号", "]", 0x30),
      key("backslash", "反斜杠", "\\", 0x31),
      key("semicolon", "分号", ";", 0x33),
      key("quote", "引号", "'", 0x34),
      key("grave", "反引号", "`", 0x35),
      key("comma", "逗号", ",", 0x36),
      key("period", "句点", ".", 0x37),
      key("slash", "斜杠", "/", 0x38),
      key("capsLock", "Caps Lock", "caps", 0x39),
    ])

    for index in 1...12 {
      actions.append(
        key("f\(index)", "F\(index)", "F\(index)", UInt8(0x39 + index))
      )
    }

    actions.append(contentsOf: [
      key("printScreen", "截屏", "PrtSc", 0x46),
      key("scrollLock", "Scroll Lock", "ScrLk", 0x47),
      key("pause", "Pause", "Pause", 0x48),
      key("insert", "Insert", "Ins", 0x49),
      key("home", "Home", "Home", 0x4A),
      key("pageUp", "上一页", "PgUp", 0x4B),
      key("deleteForward", "向后删除", "⌦", 0x4C),
      key("end", "End", "End", 0x4D),
      key("pageDown", "下一页", "PgDn", 0x4E),
      key("arrowRight", "右箭头", "→", 0x4F),
      key("arrowLeft", "左箭头", "←", 0x50),
      key("arrowDown", "下箭头", "↓", 0x51),
      key("arrowUp", "上箭头", "↑", 0x52),
    ])
    return actions
  }()

  public static let pointer: [KeyAction] = [
    pointer("leftClick", "左键单击", "左键", 0x01, "cursorarrow.click"),
    pointer("rightClick", "右键单击", "右键", 0x02, "cursorarrow.click.2"),
    pointer("middleClick", "滚轮单击", "中键", 0x04, "computermouse"),
    pointer("back", "鼠标后退", "后退", 0x08, "chevron.left"),
    pointer("forward", "鼠标前进", "前进", 0x10, "chevron.right"),
    pointer("scrollUp", "滚轮上滑", "上滑", 0xFE, "arrow.up.mouse"),
    pointer("scrollDown", "滚轮下滑", "下滑", 0xFF, "arrow.down.mouse"),
  ]

  public static let media: [KeyAction] = [
    media("volumeUp", "音量增加", "音量 +", 0xE9, "speaker.wave.3"),
    media("volumeDown", "音量降低", "音量 −", 0xEA, "speaker.wave.1"),
    media("mute", "静音", "静音", 0xE2, "speaker.slash"),
    media("play", "播放", "播放", 0xB0, "play.fill"),
    media("pause", "暂停", "暂停", 0xB1, "pause.fill"),
    media("record", "录制", "录制", 0xB2, "record.circle"),
    media("fastForward", "快进", "快进", 0xB3, "forward.fill"),
    media("rewind", "快退", "快退", 0xB4, "backward.fill"),
    media("nextTrack", "下一曲", "下一曲", 0xB5, "forward.end.fill"),
    media("previousTrack", "上一曲", "上一曲", 0xB6, "backward.end.fill"),
    media("stop", "停止", "停止", 0xB7, "stop.fill"),
    media("eject", "推出", "推出", 0xB8, "eject.fill"),
    media("playPause", "播放／暂停", "播放", 0xCD, "playpause.fill"),
  ]

  public static let system: [KeyAction] = [
    system("power", "电源", "电源", 0x30, "power"),
    system("reset", "重置", "重置", 0x31, "arrow.counterclockwise"),
    system("sleep", "系统睡眠", "睡眠", 0x32, "moon.zzz"),
    system("menu", "菜单", "菜单", 0x40, "list.bullet"),
    system("selection", "选择", "选择", 0x80, "checkmark.circle"),
    system("assignSelection", "指定选择", "指定", 0x81, "scope"),
    system("recallLast", "恢复上次", "恢复", 0x83, "arrow.uturn.backward"),
    system("quit", "退出", "退出", 0x94, "xmark.circle"),
    system("help", "帮助", "帮助", 0x95, "questionmark.circle"),
    system("channelUp", "频道增加", "频道 +", 0x9C, "plus"),
    system("channelDown", "频道降低", "频道 −", 0x9D, "minus"),
  ]

  public static func action(id: String) -> KeyAction? {
    all.first { $0.id == id }
  }

  public static func actions(in category: ActionCategory) -> [KeyAction] {
    switch category {
    case .keyboard: keyboard
    case .media: media
    case .pointer: pointer
    case .system: system
    }
  }

  public static func keyboardAction(for event: NSEvent) -> KeyAction? {
    if let id = specialKeyIDs[event.keyCode] {
      return action(id: id)
    }

    guard let characters = event.charactersIgnoringModifiers?.uppercased(),
      characters.count == 1
    else {
      return nil
    }

    let character = String(characters)
    if character.range(of: "[A-Z]", options: .regularExpression) != nil {
      return action(id: "key.\(character.lowercased())")
    }
    if character.range(of: "[0-9]", options: .regularExpression) != nil {
      return action(id: "key.\(character)")
    }
    return characterActionIDs[character].flatMap(action(id:))
  }

  public static func modifiers(for event: NSEvent) -> Set<KeyModifier> {
    var result = Set<KeyModifier>()
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.control) { result.insert(.leftControl) }
    if flags.contains(.shift) { result.insert(.leftShift) }
    if flags.contains(.option) { result.insert(.leftOption) }
    if flags.contains(.command) { result.insert(.leftCommand) }
    return result
  }

  private static let characterActionIDs: [String: String] = [
    " ": "key.space",
    "-": "key.minus",
    "=": "key.equal",
    "[": "key.leftBracket",
    "]": "key.rightBracket",
    "\\": "key.backslash",
    ";": "key.semicolon",
    "'": "key.quote",
    "`": "key.grave",
    ",": "key.comma",
    ".": "key.period",
    "/": "key.slash",
  ]

  private static let specialKeyIDs: [UInt16: String] = [
    36: "key.return",
    48: "key.tab",
    49: "key.space",
    51: "key.deleteBackward",
    53: "key.escape",
    114: "key.insert",
    115: "key.home",
    116: "key.pageUp",
    117: "key.deleteForward",
    119: "key.end",
    121: "key.pageDown",
    123: "key.arrowLeft",
    124: "key.arrowRight",
    125: "key.arrowDown",
    126: "key.arrowUp",
    122: "key.f1",
    120: "key.f2",
    99: "key.f3",
    118: "key.f4",
    96: "key.f5",
    97: "key.f6",
    98: "key.f7",
    100: "key.f8",
    101: "key.f9",
    109: "key.f10",
    103: "key.f11",
    111: "key.f12",
  ]

  private static func key(_ id: String, _ name: String, _ keycap: String, _ code: UInt8)
    -> KeyAction
  {
    KeyAction(id: "key.\(id)", name: name, keycap: keycap, code: code, category: .keyboard)
  }

  private static func pointer(
    _ id: String,
    _ name: String,
    _ keycap: String,
    _ code: UInt8,
    _ symbol: String
  ) -> KeyAction {
    KeyAction(
      id: "pointer.\(id)",
      name: name,
      keycap: keycap,
      code: code,
      category: .pointer,
      symbolName: symbol
    )
  }

  private static func media(
    _ id: String,
    _ name: String,
    _ keycap: String,
    _ code: UInt8,
    _ symbol: String
  ) -> KeyAction {
    KeyAction(
      id: "media.\(id)",
      name: name,
      keycap: keycap,
      code: code,
      category: .media,
      symbolName: symbol
    )
  }

  private static func system(
    _ id: String,
    _ name: String,
    _ keycap: String,
    _ code: UInt8,
    _ symbol: String
  ) -> KeyAction {
    KeyAction(
      id: "system.\(id)",
      name: name,
      keycap: keycap,
      code: code,
      category: .system,
      symbolName: symbol
    )
  }
}
