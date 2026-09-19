// NoteBroModel.swift
// The card model and its JSON coders. Kept separate from the app so the
// vault interop check can link them without the menu-bar AppDelegate.

import Foundation

// MARK: - NoteBro Card Model
struct NoteCard: Identifiable, Codable, Equatable {
    var id: String
    var content: String
    var color: String // "yellow", "mint", "lavender", "peach", "sky"
    var isPinned: Bool?
    var createdAt: Date
    var updatedAt: Date

    // The web app stores this as "pinned" — match it or sync silently drops pins.
    enum CodingKeys: String, CodingKey {
        case id, content, color, createdAt, updatedAt
        case isPinned = "pinned"
    }

    var pinned: Bool {
        get { isPinned ?? false }
        set { isPinned = newValue }
    }

    var hashtags: [String] {
        let pattern = "#([a-zA-Z0-9_-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
        var tags = [String]()
        for m in matches {
            if m.numberOfRanges > 1 {
                let tag = "#" + nsString.substring(with: m.range(at: 1)).lowercased()
                if !tags.contains(tag) {
                    tags.append(tag)
                }
            }
        }
        return tags
    }

    static func defaultCard() -> NoteCard {
        NoteCard(
            id: "card_\(UUID().uuidString.prefix(8))",
            content: """
yo! welcome to NoteBro for Mac 📝

• cursor is already blinking — just start typing
• ⌘← and ⌘→ (or buttons above) flick between index cards
• tap any pastel highlighter to color-code this card
• use #hashtags like #ideas or #todo for instant filtering
• ⌘N pulls a fresh card from the stack
• ⌥Space brings NoteBro up from anywhere
• close it or hit Esc — it's already saved

in a world of Word, be Notepad. zero friction.
""",
            color: "yellow",
            isPinned: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Shared JSON Coders
/// Dates go over the wire as ISO-8601 with fractional seconds, matching the web
/// app's `new Date().toISOString()`. Swift's stock `.iso8601` strategy rejects the
/// milliseconds JS always writes, so vault payloads from the browser failed to decode.
/// Decoding also accepts second-precision ISO and raw numbers (legacy local files).
enum NoteJSON {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func isoString(from date: Date) -> String { isoFractional.string(from: date) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFractional.string(from: date))
        }
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let raw = try? container.decode(String.self) {
                guard let date = isoFractional.date(from: raw) ?? isoPlain.date(from: raw) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unparseable date: \(raw)")
                }
                return date
            }
            return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
        }
        return d
    }()
}
