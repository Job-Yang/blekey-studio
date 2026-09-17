import Foundation

public enum XKeyProtocolError: LocalizedError, Equatable {
  case unsupportedLayer(Int)
  case unsupportedKey(Int)
  case unknownAction(String)
  case modifierRequired

  public var errorDescription: String? {
    switch self {
    case .unsupportedLayer(let value):
      "不支持第 \(value) 层，设备只接受 1 到 10 层。"
    case .unsupportedKey(let value):
      "不支持按键 \(value)，设备只接受 1 到 24 号按键。"
    case .unknownAction(let id):
      "找不到动作 \(id)。"
    case .modifierRequired:
      "仅修饰键映射至少需要一个修饰键。"
    }
  }
}

public struct XKeyCommand: Equatable, Sendable {
  public let bytes: Data
  public let target: WriteItem
  public let label: String

  public init(bytes: Data, target: WriteItem, label: String) {
    self.bytes = bytes
    self.target = target
    self.label = label
  }

  public var hex: String {
    bytes.map { String(format: "%02X", $0) }.joined()
  }
}

public enum XKeyProtocol {
  public static let serviceUUID = "0000FFE6-0000-1000-8000-00805F9B34FB"
  public static let writeCharacteristicUUID = "0000FFE7-0000-1000-8000-00805F9B34FB"
  public static let notifyCharacteristicUUID = "00001002-0000-1000-8000-00805F9B34FB"

  public static func mappingCommand(
    address: MappingAddress,
    assignment: KeyAssignment?
  ) throws -> XKeyCommand {
    guard (1...10).contains(address.layer) else {
      throw XKeyProtocolError.unsupportedLayer(address.layer)
    }
    guard (1...24).contains(address.key) else {
      throw XKeyProtocolError.unsupportedKey(address.key)
    }

    let layer = address.layer == 10 ? UInt8(0x10) : UInt8(address.layer)
    let key = UInt8(address.key)
    let typeOrModifiers: UInt8
    let keyCode: UInt8
    let label: String

    if let assignment {
      guard let action = ActionCatalog.action(id: assignment.actionID) else {
        throw XKeyProtocolError.unknownAction(assignment.actionID)
      }
      switch action.category {
      case .keyboard:
        if action.id == ActionCatalog.modifierOnly.id, assignment.modifiers.isEmpty {
          throw XKeyProtocolError.modifierRequired
        }
        typeOrModifiers = assignment.modifiers.reduce(0) { $0 | $1.rawValue }
      case .pointer:
        typeOrModifiers = 0xFE
      case .media, .system:
        typeOrModifiers = 0xFD
      }
      keyCode = action.code
      label = "第 \(address.layer) 层 · 按键 \(address.key) · \(displayName(for: assignment))"
    } else {
      typeOrModifiers = 0
      keyCode = 0
      label = "第 \(address.layer) 层 · 清空按键 \(address.key)"
    }

    return XKeyCommand(
      bytes: Data([layer, key, typeOrModifiers, keyCode]),
      target: .mapping(address),
      label: label
    )
  }

  public static func sleepCommand(_ timeout: SleepTimeout) -> XKeyCommand {
    XKeyCommand(
      bytes: Data([0xFF, 0xFF, 0xFF, timeout.rawValue]),
      target: .sleep,
      label: "休眠时间 · \(timeout.title)"
    )
  }

  public static func commands(for profile: DeviceProfile) throws -> [XKeyCommand] {
    var commands = try profile.dirtyAddresses.map {
      try mappingCommand(address: $0, assignment: profile.assignment(at: $0))
    }
    if profile.isSleepDirty {
      commands.append(sleepCommand(profile.sleepTimeout))
    }
    return commands
  }

  public static func displayName(for assignment: KeyAssignment?) -> String {
    guard let assignment,
      let action = ActionCatalog.action(id: assignment.actionID)
    else {
      return "未设置"
    }

    guard action.category == .keyboard else {
      return action.name
    }

    let prefix = assignment.modifiers.map(\.displayName).joined(separator: " ")
    if action.id == ActionCatalog.modifierOnly.id {
      return prefix.isEmpty ? action.name : prefix
    }
    return prefix.isEmpty ? action.name : "\(prefix) \(action.keycap)"
  }
}
