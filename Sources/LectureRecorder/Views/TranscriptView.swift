import SwiftUI
import LectureCore
struct TranscriptView: View {
    let transcript: Transcript
    let query: String
    let seek: (Double) -> Void
    var body: some View {
        if transcript.noSpeech { ContentUnavailableView("No speech detected", systemImage: "waveform", description: Text("Your audio is still available for playback.")) }
        else {
            let matches = transcript.segments.enumerated().filter { query.isEmpty || $0.element.text.localizedCaseInsensitiveContains(query) }
            if matches.isEmpty { ContentUnavailableView.search(text: query) }
            else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(matches, id: \.offset) { _, segment in
                        HStack(alignment: .top, spacing: 18) {
                            Button(TranscriptExport.timestamp(segment.startSeconds)) { seek(segment.startSeconds) }
                                .font(.system(.caption, design: .monospaced)).buttonStyle(.plain).foregroundStyle(.tint)
                                .accessibilityLabel("Play from \(TranscriptExport.timestamp(segment.startSeconds))")
                            Text(segment.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(.vertical, 12)
            }
        }
    }
}
