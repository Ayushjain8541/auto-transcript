# Implementation decisions and review

## Rulings made

1. Execute the approved plan inline on an attached worktree. The build request provided authorization to proceed; no additional execution-method question was needed. Cost if wrong: the workflow preference can be changed without losing committed work.
2. Reuse the existing scaffold. Cost if wrong: packaging/capture verification must expose any foundation gaps.
3. Replace XCTest/Swift Testing with the `LectureCoreChecks` executable because neither test module is available in the installed CLT toolchain. Cost: no IDE test discovery; the checks still execute production services and fail with nonzero exit status.
4. Build persistence and the audio writer while awaiting the first live-capture permission step. Cost: a platform capture failure could require adapter changes. The subsequent user-operated capture succeeded.
5. Inject a local English tokenizer adapter before WhisperKit model loading. The upstream convenience loader can download a tokenizer on failure, and its ready-made wrapper initializer is internal. Cost: maintain the adapter when upgrading the pinned SDK. Actual denied-network transcription verified this path.
6. Stream an assembled temporary WAV through AVPlayer for playback. This retains source segments and their offsets and avoids gaps from switching files. Cost: temporary disk usage and assembly latency; capacity checks and cleanup are implemented.
7. Leave physical sleep/lid, two-hour endurance, measured WER, music, and controlled source-exclusion/listening checks explicitly unverified until observed. Cost: platform and lecture-quality limitations may remain undiscovered. These are acceptance gaps, not passing results.

## Independent review

A fresh reviewer examined the full branch and reran the original 34 checks. It found three important defects and no critical or minor findings:

- Finish could discard queued audio and extend its duration during delayed capture teardown.
- Sleep during finalization could be forgotten, allowing transcription to start afterward.
- Forward audio timestamp jumps could bypass the suspension guard and synthesize a large unknown interval.

All three were fixed in one pass. Four regression checks were observed failing before the fixes and passing afterward. An additional ordinary long-pause check confirms that the discontinuity fix preserves legitimate silence. The full suite now passes **39/39**. There are **no deferred minor findings**. The reviewer did not substitute automated checks for the manual acceptance gaps listed above.

Other observed fixes: the real silence test exposed a model hallucination, addressed with a streaming signal preflight; abandoned processing files are removed at startup without touching original audio; UI startup waits for recovery; the main window has a minimum size that keeps library controls usable.

## Delivery and branch

The final app is locally ad-hoc signed and intended for this Mac. New builds have new code hashes, which may require renewing capture permission. No signing account, paid inference service, keychain changes, public release, or network-setting changes were introduced. The implementation branch remains separate from `main` for review.
