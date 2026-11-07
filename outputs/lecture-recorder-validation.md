# Lecture Recorder validation — 24 October 2026

Implementation is present; full acceptance is **not complete**. The app is a local development build for this Mac. No lecture audio or model weights are committed to Git.

| Check | Status | Evidence / remaining action |
|---|---|---|
| Automated Swift behavior checks | Pass | 43/43: capture selection/overflow/draining, Finish and sleep boundaries, persistence/recovery, PCM/timeline, model verification, transcription/cancellation, coordinator races, presentation, library/export/seek. |
| Evaluation utility | Pass | Four Python tests: normalization, substitution, insertion/deletion, empty-reference WER. |
| Packaged Chrome capture | Pass | User operated a 152.16775-second recording. 16 consecutive valid WAV segments; saved state recorded; nonzero audio. |
| Actual offline speech transcription | Pass | Cold process denied all network access; 152.16775 seconds processed in 98.65 seconds; 26 timed segments. Subject: flip-flops. |
| Digital silence | Pass | Regression exposed and fixed a Whisper hallucination; 15-second silent WAV now yields no speech. |
| Model preparation | Pass | Pinned 22-artifact manifest, 629,519,690 bytes; successful real Core ML initialization in isolated storage. |
| Standalone package | Pass | Signed arm64 app launches with embedded resources; missing-resource negative check fails correctly. Release build and signature/resource verification also pass. |
| Full final-UI Start → Finish → transcript | Partial | User captured a 13-minute recording; initial automatic transcription exposed a boundary bug. The fixed release successfully transcribed it through Retry. New-recording automatic completion still needs a fresh check. |
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

## Transcription boundary fix — 26 October 2026

A saved 780.07775-second recording reproduced a deterministic validation failure after local inference: the final generated segment ended at 799.1799926757812 seconds. The final silent section also produced hallucinated text. The original 79 WAV segments remained valid and retained throughout recovery. No user audio or transcript content is included in this repository.

The transcription service now clips generated segments to the actual recorded interval and discards text whose interval contains only digital silence. It preserves absolute offsets and retains very quiet nonzero signals above the existing one-PCM-step threshold. Nonfinite, negative, reversed and descending timestamps still fail validation. This is a digital-silence guard, not a general speech/music classifier or an accuracy guarantee.

Regression evidence: both new boundary/silence checks failed before the change and passed afterward; 42/42 Swift checks and 4/4 Python checks pass. The signed release bundle passed verification, was installed at the stable app path, and its existing macOS capture permission was refreshed. Retrying the original recording through the updated application completed successfully with 215 transcript segments; the last segment ends at 719.5999755859375 seconds, with no invented segments in the verified silent tail. The library visibly shows complete. Broader endurance and WER acceptance checks remain outstanding.

## Overlapping-passage ordering fix — 2 November 2026

A 5471.5600625-second recording (91 minutes 11 seconds, 548 valid consecutive WAV segments) failed because the decoder returned five overlapping passages out of start-time order. Backward differences ranged from about 20 milliseconds to 1.00049 seconds; the first occurred around 4151.5 seconds. All individual intervals were finite, nonnegative, and forward. The previous EOF clipping fix was installed, but the independent monotonic-start check still rejected the whole transcript.

The service now validates individual intervals, then stably orders passages by start time, retaining original order for ties. It preserves overlapping timestamps and text, while still rejecting negative, nonfinite, or reversed intervals. EOF clipping and digital-silence checks remain. Failure messages include the offending passage index and timing; a backward-compatible optional session field retains failure details across relaunch, displays them in the library, and clears on retry/success.

Verification: the overlapping-passage regression failed before the change and passed afterward, including transcript persistence/reload. The failure-detail persistence test also failed then passed. All 43 Swift checks and four Python checks pass. The complete recording was decoded locally once to reproduce the error; replaying that captured decoder output through the corrected production service succeeded, retaining all 1505 non-empty passages with no text loss. The validated transcript was restored locally and normal app startup reconciled its session to complete. This is decoder-output replay evidence, not a second full model-inference run. Private audio and transcript text remain excluded from Git.
