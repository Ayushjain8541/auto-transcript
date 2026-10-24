# Lecture Recorder validation — 24 October 2026

Implementation is present; full acceptance is **not complete**. The app is a local development build for this Mac. No lecture audio or model weights are committed to Git.

| Check | Status | Evidence / remaining action |
|---|---|---|
| Automated Swift behavior checks | Pass | 39/39: capture selection/overflow/draining, Finish and sleep boundaries, persistence/recovery, PCM/timeline, model verification, transcription/cancellation, coordinator races, presentation, library/export/seek. |
| Evaluation utility | Pass | Four Python tests: normalization, substitution, insertion/deletion, empty-reference WER. |
| Packaged Chrome capture | Pass | User operated a 152.16775-second recording. 16 consecutive valid WAV segments; saved state recorded; nonzero audio. |
| Actual offline speech transcription | Pass | Cold process denied all network access; 152.16775 seconds processed in 98.65 seconds; 26 timed segments. Subject: flip-flops. |
| Digital silence | Pass | Regression exposed and fixed a Whisper hallucination; 15-second silent WAV now yields no speech. |
| Model preparation | Pass | Pinned 22-artifact manifest, 629,519,690 bytes; successful real Core ML initialization in isolated storage. |
| Standalone package | Pass | Signed arm64 app launches with embedded resources; missing-resource negative check fails correctly. Release build and signature/resource verification also pass. |
| Full final-UI Start → Finish → transcript | Not Run | Current build’s permission status must be reconciled with macOS Settings. Earlier diagnostic capture succeeded. |
| Other-app audio exclusion / microphone exclusion | Not Run | Need distinguishable simultaneous playback outside Chrome and controlled microphone sound. Code filter is Chrome-only; microphone capture is disabled. |
| Fullscreen/background/window-closed capture | Not Run | Need controlled user playback with window closed/fullscreen. |
| Listening and timestamp spot checks | Not Run | Automated segment continuity passes; manually compare audible boundaries and transcript timestamps. |
| Two-hour recording, pauses, resource measurements | Not Run | Requires real-duration controlled playback. No accelerated fixture is represented as this check. |
| Ten-minute lecture quality / WER ≤15% | Not Run | Requires a representative lecture and manually checked reference; scorer provided. |
| Music / low-volume speech | Not Run | Need representative fixtures; model hallucination risk remains for non-speech sounds. |
| Real Chrome exit, permission revocation, sleep/lid | Not Run | State tests pass; physical/OS acceptance remains. |
| Real force-quit recovery | Not Run | Atomic-write/orphan/transcript reconciliation fixtures pass; actual process-termination matrix remains. |
| Disk failure | Pass, injected | Prior committed WAV retained; failed manifest write preserves prior data; setup refuses inadequate free capacity. |
| Cancellation/retry | Pass, automated | Late fake decoder completion cannot commit; job stays reserved until cancelled worker stops. Bundled UI Cancel and retry also passed. |
| Library/search/playback/export | Pass | Bundled UI filtered/restored transcript rows, played across the 20s boundary and exported a 28-line text file. |
| Library/Trash after relaunch | Not Run | Trash operation is tested through an injected filesystem client; actual user recording was retained. |

First-run neural-engine preparation consumes CPU and can take minutes. The recorded 98.65-second timing includes cold model loading; it is not a steady-state speed guarantee. No two-hour RAM/CPU-growth measurements or measured lecture WER are claimed.

Build instructions and repeatable integration commands are in `docs/BUILD.md`; detailed evidence is in `docs/ACCEPTANCE.md`. The app stores data under `~/Library/Application Support/LectureRecorder`. Normal operation is free and local after setup.

Independent review found three important boundary defects; all were fixed with failing-then-passing regressions. No minor findings were deferred. See `lecture-recorder-implementation-notes.md` for decisions and review details. Final release was rebuilt after the fixes, verified, installed at the original stable outputs path, and reopened with the model already prepared.
