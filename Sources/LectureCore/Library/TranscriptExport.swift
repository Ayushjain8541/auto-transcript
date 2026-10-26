import Foundation
public enum TranscriptExport {
    public static func text(session: Session, transcript: Transcript) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm z"; formatter.timeZone = TimeZone(identifier: session.timeZoneID)
        var lines = [session.title, formatter.string(from: session.createdAt), "Timestamps follow the recording.", ""]
        if let reason = session.interruptionReason { lines += ["Recording interrupted: \(reason)", ""] }
        if transcript.noSpeech { lines.append("No speech detected.") }
        else { lines += transcript.segments.map { "[\(timestamp($0.startSeconds))] \($0.text)" } }
        return lines.joined(separator: "\n") + "\n"
    }
    public static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "00:00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
    public static func filename(_ title: String) -> String {
        let sanitized = title.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.isEmpty ? "Lecture" : sanitized).prefix(100)) + ".txt"
    }
}
