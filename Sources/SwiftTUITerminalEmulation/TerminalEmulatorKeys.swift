public import SwiftTUIRuntime

public struct TerminalEmulatorKey: Sendable, Equatable, Hashable {
  public enum Code: Sendable, Equatable, Hashable {
    case character(Character)
    case enter
    case backspace
    case escape
    case tab
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case home
    case end
    case insert
    case delete
    case pageUp
    case pageDown
    case function(Int)
  }

  public struct Modifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
  }

  public var code: Code
  public var modifiers: Modifiers

  public init(code: Code, modifiers: Modifiers = []) {
    self.code = code
    self.modifiers = modifiers
  }

  public init?(
    event: KeyEvent,
    modifiers: EventModifiers = []
  ) {
    self.init(keyPress: KeyPress(event, modifiers: modifiers))
  }

  public init?(keyPress: KeyPress) {
    guard let code = Code(event: keyPress.key) else {
      return nil
    }
    self.init(
      code: code,
      modifiers: Modifiers(eventModifiers: keyPress.modifiers)
    )
  }

  /// Legacy text uses the character supplied by the host (already keyboard-layout resolved).
  public var legacyByteSequence: [UInt8] {
    legacyBytes(applicationCursor: false)
  }

  func legacyBytes(applicationCursor: Bool) -> [UInt8] {
    let alt: [UInt8] = modifiers.contains(.option) ? [0x1B] : []
    switch code {
    case .character(let character):
      if modifiers.contains(.control), character.unicodeScalars.count == 1,
        let scalar = character.unicodeScalars.first,
        let control = Self.controlByte(scalar.value)
      {
        return alt + [control]
      }
      return alt + Array(String(character).utf8)
    case .enter: return alt + [13]
    case .escape: return alt + [27]
    case .backspace: return alt + [modifiers.contains(.control) ? 8 : 127]
    case .tab: return alt + (modifiers.contains(.shift) ? Array("\u{1B}[Z".utf8) : [9])
    default:
      return functionalBytes(kitty: false, applicationCursor: applicationCursor)
    }
  }

  // Only flags for information the public KeyPress contract can provide are negotiated:
  // disambiguation, all supplied keys, and associated Unicode text. No event phases or alternates.
  static let supportedKeyboardFlags = 1 | 8 | 16

  func kittyBytes(flags: Int, applicationCursor: Bool) -> [UInt8] {
    let allKeys = flags & 8 != 0
    let disambiguate = flags & 1 != 0 || allKeys
    guard disambiguate else { return legacyBytes(applicationCursor: applicationCursor) }
    switch code {
    case .character(let character):
      guard allKeys || !modifiers.intersection([.control, .option]).isEmpty else {
        return Array(String(character).utf8)
      }
      let scalars = String(character).unicodeScalars.map(\.value)
      if allKeys && flags & 16 != 0 && modifiers.intersection([.control, .option]).isEmpty {
        guard let first = scalars.first else { return [] }
        return csiU(first, text: scalars)
      }
      return scalars.flatMap { csiU($0) }
    case .escape: return csiU(27)
    case .enter: return allKeys ? csiU(13) : legacyBytes(applicationCursor: false)
    case .backspace: return allKeys ? csiU(127) : legacyBytes(applicationCursor: false)
    case .tab:
      return allKeys ? csiU(9) : legacyBytes(applicationCursor: false)
    default:
      return functionalBytes(kitty: true, applicationCursor: false)
    }
  }

  private var wireModifiers: Int {
    1 + (modifiers.contains(.shift) ? 1 : 0)
      + (modifiers.contains(.option) ? 2 : 0)
      + (modifiers.contains(.control) ? 4 : 0)
  }

  private func csiU(_ scalar: UInt32, text: [UInt32] = []) -> [UInt8] {
    // ASCII letters use their unshifted identity; no keyboard-layout alternatives are invented.
    let code = modifiers.contains(.shift) && (65...90).contains(scalar) ? scalar + 32 : scalar
    var body = String(code)
    if wireModifiers != 1 { body += ";\(wireModifiers)" }
    if !text.isEmpty {
      body += (wireModifiers == 1 ? ";;" : ";") + text.map(String.init).joined(separator: ":")
    }
    return Array("\u{1B}[\(body)u".utf8)
  }

  private func functionalBytes(kitty: Bool, applicationCursor: Bool) -> [UInt8] {
    let letter: String?
    switch code {
    case .arrowUp: letter = "A"
    case .arrowDown: letter = "B"
    case .arrowRight: letter = "C"
    case .arrowLeft: letter = "D"
    case .home: letter = "H"
    case .end: letter = "F"
    case .function(let n) where (1...4).contains(n) && !(kitty && n == 3):
      letter = ["P", "Q", "R", "S"][n - 1]
    default: letter = nil
    }
    if let letter {
      if wireModifiers != 1 { return Array("\u{1B}[1;\(wireModifiers)\(letter)".utf8) }
      let useSS3: Bool
      if case .function = code { useSS3 = !kitty } else { useSS3 = applicationCursor }
      return Array("\u{1B}\(useSS3 ? "O" : "[")\(letter)".utf8)
    }
    let number: Int
    switch code {
    case .insert: number = 2
    case .delete: number = 3
    case .pageUp: number = 5
    case .pageDown: number = 6
    case .function(3) where kitty: number = 13
    case .function(let n) where (5...12).contains(n):
      number = [15, 17, 18, 19, 20, 21, 23, 24][n - 5]
    case .function(let n) where kitty && (13...35).contains(n):
      return csiU(UInt32(57376 + n - 13))
    default: return []
    }
    let modifier = wireModifiers == 1 ? "" : ";\(wireModifiers)"
    return Array("\u{1B}[\(number)\(modifier)~".utf8)
  }

  private static func controlByte(_ scalar: UInt32) -> UInt8? {
    if (65...90).contains(scalar) { return UInt8(scalar - 64) }
    if (97...122).contains(scalar) { return UInt8(scalar - 96) }
    switch scalar {
    case 32, 50, 64: return 0
    case 51, 91: return 27
    case 52, 92: return 28
    case 53, 93: return 29
    case 54, 94, 126: return 30
    case 47, 55, 95: return 31
    case 56, 63: return 127
    default: return nil
    }
  }
}

extension TerminalEmulatorKey.Code {
  fileprivate init?(event: KeyEvent) {
    switch event {
    case .character(let character):
      self = .character(character)
    case .return:
      self = .enter
    case .space:
      self = .character(" ")
    case .tab:
      self = .tab
    case .arrowLeft:
      self = .arrowLeft
    case .arrowRight:
      self = .arrowRight
    case .arrowUp:
      self = .arrowUp
    case .arrowDown:
      self = .arrowDown
    case .backspace:
      self = .backspace
    case .escape:
      self = .escape
    case .home:
      self = .home
    case .end:
      self = .end
    case .insert:
      self = .insert
    case .delete:
      self = .delete
    case .pageUp:
      self = .pageUp
    case .pageDown:
      self = .pageDown
    case .functionKey(let number):
      guard number > 0 else {
        return nil
      }
      self = .function(number)
    }
  }
}

extension TerminalEmulatorKey.Modifiers {
  fileprivate init(eventModifiers: EventModifiers) {
    var modifiers: Self = []
    if eventModifiers.contains(.ctrl) {
      modifiers.insert(.control)
    }
    if eventModifiers.contains(.alt) {
      modifiers.insert(.option)
    }
    if eventModifiers.contains(.shift) {
      modifiers.insert(.shift)
    }
    self = modifiers
  }
}
