# Audio-only recording

A Discord call was being recorded with `recaudio` and came back marked CUT SHORT at
48:40. The manifest named the reason: "the display resolution changed mid-recording
(2x2 → 3024x1964)". That was not true — the display never changed. In `--audio-only`
mode the writer is deliberately 2x2 because there is no video track at all, so the
reconnect guard compared the display's real pixel size against 2x2, always mismatched,
and turned every ScreenCaptureKit blip into a hard stop. The fix was to skip that
check when there is no committed video size to protect, and the decision was pulled
into a pure function with a self-test so the same one-line mistake cannot recur
unnoticed.

The feature itself adds `--audio-only` / `--no-video` to `screen-audio-record` and a
`recaudio` wrapper. The recorder never attaches the `.screen` stream output and asks
ScreenCaptureKit for a 2x2 video configuration it never encodes, so the audio path is
the same one `rec` already uses. `rec-audio flatten` learned to handle an input with
no video track, and `rec-subtitle` learned to keep the `.srt` sidecar when there is no
picture to burn into.

Testing the audio-only path surfaced two pre-existing `rec-subtitle` bugs, both hit by
the everyday case of transcribing a file sitting in the current directory. The output
directory was derived from the stem, so a bare filename produced an empty
`--output_dir`, which Whisper's `makedirs` dies on. And the transcript is renamed to
the source stem afterwards, comparing two spellings of one path as if they were two
files — which deleted the transcript it had just written and then copied it onto
itself. Both were confirmed against the pre-fix binary and fixed by making the stem
absolute and comparing standardized file URLs.

Verification: a real 48:40 Discord recording was produced with two audio tracks and no
video track, with its flat mix and manifest; `rec-audio flatten` and `rec-subtitle`
were run against it and against a short clip; the bare-filename transcription was
reproduced as a failure on the pre-fix binary and confirmed fixed after. The
reconnect guard's self-test was verified to FAIL against the pre-fix logic and pass
after. The reconnect behaviour itself was not exercised live — forcing a ScreenCaptureKit
interruption needs a `replayd` restart, which needs sudo — so that scenario is graded
by its build-time assertion rather than by a live blip.

Card: [audio-only-recording.feature](audio-only-recording.feature).
