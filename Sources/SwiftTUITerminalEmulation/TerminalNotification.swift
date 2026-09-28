import Foundation

public struct TerminalNotificationID: Sendable, Equatable, Hashable {
  public let session: String
  public let identifier: String

  public init(session: String, identifier: String) {
    self.session = session
    self.identifier = identifier
  }
}

/// A request to the embedding host; the package never displays OS notifications itself.
public struct TerminalNotification: Sendable, Equatable, Identifiable {
  public enum Kind: Sendable, Equatable { case show, close }
  public let id: TerminalNotificationID
  public let kind: Kind
  public let title: String
  public let body: String

  public init(id: TerminalNotificationID, kind: Kind, title: String = "", body: String = "") {
    self.id = id
    self.kind = kind
    self.title = title
    self.body = body
  }
}

struct TerminalNotificationParser {
  private struct Pending {
    var title = ""
    var body = ""
    let started = ContinuousClock.now
  }
  private let session = UUID().uuidString
  private var anonymous: UInt64 = 0
  private var pending: [String: Pending] = [:]
  private var active: Set<String> = []
  private var rateWindow = ContinuousClock.now
  private var deliveries = 0

  mutating func parse(_ bytes: [UInt8]) -> TerminalNotification? {
    let now = ContinuousClock.now
    pending = pending.filter { $0.value.started.duration(to: now) <= .seconds(5) }
    guard bytes.count <= 12_288, let content = String(bytes: bytes, encoding: .utf8),
      content.hasPrefix("99;"),
      let separator = content.dropFirst(3).firstIndex(of: ";")
    else { return nil }
    let metadata = content[content.index(content.startIndex, offsetBy: 3)..<separator]
    var fields: [Substring: Substring] = [:]
    for item in metadata.split(separator: ":") {
      let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, fields[parts[0]] == nil else { return nil }
      fields[parts[0]] = parts[1]
    }
    let identifier: String
    if let value = fields["i"], value != "0" {
      guard !value.isEmpty, value.utf8.count <= 128,
        value.utf8.allSatisfy({
          (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            || $0 == 95
        })
      else { return nil }
      identifier = String(value)
    } else {
      guard fields["d"] != "0", fields["p"] != "close" else { return nil }
      anonymous &+= 1
      identifier = ":anonymous-\(anonymous)"
    }
    let id = TerminalNotificationID(session: session, identifier: identifier)
    let part = fields["p"] ?? "title"
    if part == "close" {
      pending[identifier] = nil
      guard active.remove(identifier) != nil else { return nil }
      return TerminalNotification(id: id, kind: .close)
    }
    guard part == "title" || part == "body",
      fields["d"] == nil || fields["d"] == "0" || fields["d"] == "1"
    else { return nil }
    let raw = String(content[content.index(after: separator)...])
    let text: String
    if fields["e"] == "1" {
      guard let data = Data(base64Encoded: raw), let decoded = String(data: data, encoding: .utf8)
      else { return nil }
      text = decoded
    } else {
      guard fields["e"] == nil || fields["e"] == "0" else { return nil }
      text = raw
    }
    guard text.utf8.count <= 8192,
      text.unicodeScalars.allSatisfy({
        $0.value >= 32 && !(127...159).contains($0.value) || $0.value == 10 || $0.value == 9
      })
    else { return nil }
    guard pending[identifier] != nil || pending.count < 16 else { return nil }
    var request = pending[identifier] ?? Pending()
    if part == "title" { request.title += text } else { request.body += text }
    guard request.title.utf8.count + request.body.utf8.count <= 8192 else {
      pending[identifier] = nil
      return nil
    }
    if fields["d"] == "0" {
      pending[identifier] = request
      return nil
    }
    pending[identifier] = nil
    if rateWindow.duration(to: now) >= .seconds(1) {
      rateWindow = now
      deliveries = 0
    }
    guard deliveries < 8, active.contains(identifier) || active.count < 32 else { return nil }
    deliveries += 1
    active.insert(identifier)
    return TerminalNotification(id: id, kind: .show, title: request.title, body: request.body)
  }

  mutating func reset() -> [TerminalNotification] {
    let result = active.sorted().map {
      TerminalNotification(
        id: TerminalNotificationID(session: session, identifier: $0), kind: .close)
    }
    active.removeAll()
    pending.removeAll()
    return result
  }
}
