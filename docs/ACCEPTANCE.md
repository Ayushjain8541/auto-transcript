
## Implementation evidence — 24 October 2026

User-operated Chrome recording: session `4ED3308E-27CE-46E3-8FAD-F02539E4FE72`, 2,434,684 frames (152.16775 seconds), state recorded, 15 full ten-second segments plus a 34,684-frame tail. Initial segments have nonzero speech-level signals (first segment peak 8560/32768, RMS 1008/32768). Manifest offsets are consecutive. This establishes successful packaged capture and persistence; exclusion of another app, listening for boundary artifacts, and fullscreen/window-closed conditions have not yet been independently verified.

Pinned tokenizer: openai/whisper-large-v3 at `06f233fe06e710322aca913c1bc4249a0d71fce1`. Complete asset manifest: 22 files, 629,519,690 bytes. Model/tokenizer SHA-256 hashes computed from downloaded immutable URLs. The local tokenizer adapter uses the SDK's file-only parser and injects the result before model loading, bypassing its network fallback.

Real Core ML preparation succeeded on this Mac using the isolated `work/model-freeze` root. Four model-management behavior checks also pass (complete assets/offline lookup, corrupt hash, retry after preparation failure, insufficient disk). This is preparation evidence; offline inference is a separate check.

Offline real-engine check: a cold test process under `sandbox-exec '(version 1)(allow default)(deny network*)'` loaded the pinned local assets and transcribed the user's 152.16775-second Chrome recording in 98.65 seconds, producing 26 timestamped segments about D/JK flip-flops. No lecture audio was uploaded. A separate 15-second digital-silence check initially exposed a Whisper hallucination (“Thank you”, end 29.98s, no-speech probability 0). A streaming signal preflight now returns an empty/no-speech result for digital silence; the regression passes under the same denied-network policy. Music and manually measured WER remain Not Run.
