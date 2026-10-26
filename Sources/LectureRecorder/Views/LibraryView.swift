import SwiftUI
import UniformTypeIdentifiers
import LectureCore

struct LibraryView: View {
    let app: AppDependencies
    @Bindable var library: LibraryModel
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TextField("Search lecture titles", text: $library.titleQuery).textFieldStyle(.roundedBorder).padding()
                List(selection: $library.selectedSessionID) {
                    ForEach(library.visibleSessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title).lineLimit(2)
                            Text("\(TranscriptExport.timestamp(session.duration)) · \(session.state.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 3).tag(session.id)
                    }
                }
                if !library.errors.isEmpty { Text(library.errors.joined(separator: "\n")).font(.caption).foregroundStyle(.red).padding().textSelection(.enabled) }
            }.navigationTitle("Lectures").navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                RecordingControls(app: app).padding(18)
                Divider()
                if let session = library.sessions.first(where: { $0.id == library.selectedSessionID }) {
                    SessionDetailView(app: app, library: library, session: session).id(session.id)
                } else {
                    ContentUnavailableView("Your lecture library", systemImage: "text.bubble", description: Text("Open a lecture in Chrome, click Start recording, then click Finish when you’re done."))
                }
            }
        }.task(id: app.coordinator.revision) { await library.reload() }
    }
}

private struct SessionDetailView: View {
    let app: AppDependencies
    let library: LibraryModel
    let session: Session
    @State private var transcript: Transcript?
    @State private var query = ""
    @State private var playback = PlaybackService()
    @State private var error: String?
    @State private var rename = false
    @State private var title = ""
    @State private var deleting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.title).font(.title2.bold()).textSelection(.enabled)
                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                if let reason = session.interruptionReason { Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout) }
                HStack {
                    Button(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") { playback.isPlaying ? playback.pause() : playback.play() }.disabled(!playback.ready)
                    Slider(value: Binding(get: { playback.position }, set: { playback.seek(to: $0) }), in: 0...max(0.001, playback.duration)).disabled(!playback.ready).accessibilityLabel("Recording position")
                    Text(TranscriptExport.timestamp(playback.position)).font(.system(.caption, design: .monospaced))
                }
                if let message = error ?? playback.errorMessage { Text(message).foregroundStyle(.red).textSelection(.enabled) }
                HStack {
                    if let transcript {
                        Button("Copy text", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(TranscriptExport.text(session: session, transcript: transcript), forType: .string) }
                        Button("Export text…", systemImage: "square.and.arrow.up") { export(transcript) }
                    } else {
                        Button(session.state == .transcriptionFailed ? "Retry transcription" : "Transcribe", systemImage: "text.bubble") { Task { await app.coordinator.transcribe(session.id) } }.disabled(app.coordinator.phase != nil || session.segments.isEmpty || !app.modelReady)
                    }
                    Spacer()
                    Button("Rename") { title = session.title; rename = true }.disabled(app.coordinator.activeSessionID == session.id)
                    Button("Trash", systemImage: "trash", role: .destructive) { deleting = true }.disabled(app.coordinator.activeSessionID == session.id)
                }
                Divider()
                if let transcript {
                    TextField("Search this transcript", text: $query).textFieldStyle(.roundedBorder)
                    TranscriptView(transcript: transcript, query: query) { playback.seek(to: $0); playback.play() }
                } else if session.state == .transcribing { Text("Transcription is in progress. Your saved audio is available above.").foregroundStyle(.secondary) }
                else { Text("No transcript yet. Transcribe this saved recording when you’re ready.").foregroundStyle(.secondary) }
            }.padding(24)
        }
        .task(id: session.state) {
            do {
                transcript = try await app.store.transcript(session.id)
                if !playback.ready, !session.state.isActive, !session.segments.isEmpty {
                    let folder = await app.store.folder(for: session.id)
                    try await playback.load(session: session, folder: folder)
                }
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { playback.clear() }
        .alert("Rename lecture", isPresented: $rename) {
            TextField("Title", text: $title)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { do { try await library.rename(session.id, title: title) } catch { self.error = error.localizedDescription } } }
        }
        .confirmationDialog("Move this lecture and its audio to the Trash?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { Task { do { playback.clear(); try await library.trash(session.id) } catch { self.error = error.localizedDescription } } }
        }
    }
    private func export(_ transcript: Transcript) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = TranscriptExport.filename(session.title)
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try TranscriptExport.text(session: session, transcript: transcript).write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
    }
}
