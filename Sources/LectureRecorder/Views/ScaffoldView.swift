import LectureCore
import SwiftUI

/// A visible status screen until the recording workflow is implemented.
struct ScaffoldView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(AppIdentity.displayName)
                .font(.largeTitle.bold())

            Text("Record a lecture. Read it afterward.")
                .font(.title3)

            Text("This is the app scaffold. Recording and transcription are not implemented yet.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .frame(width: 416, alignment: .leading)
    }
}
