# RecBurn — Feature Reference

> **Generated** from the Gherkin report cards in this folder by `python3 print-card.py --readme`. Do not hand-edit — edit the `.feature` card and regenerate. Each entry below = one card: *what it does* (intent + behaviour scenarios) and *how it does it* (the procs/files the behaviour is cited to).

Each card is a triad: the `.feature` spec, a `.session.md` (the conversation that produced it), and a RESULT-LOG of what shipped.

## Contents

- [Record the audio of a call without recording the screen](#audio-only-recording) — `audio-only-recording.feature`
- [Install and verify compatible Whisper dependencies](#recburn-whisper-deps) — `recburn-whisper-deps.feature`


<a id="audio-only-recording"></a>
## Record the audio of a call without recording the screen

`features/audio-only-recording.feature` · [session](audio-only-recording.session.md)

**What it does:** As a person in a meeting, I want the sound of the call and not its picture, So that a long call costs no CPU on frames nobody will watch.

**Behaviour (7 scenarios):**

- An audio-only recording has two audio tracks and no video track — `@runtime-verified`
- The YouTube-ready mix is written next to the audio-only recording — `@runtime-verified`
- Flattening an audio-only recording produces a single mixed .m4a — `@runtime-verified`
- Subtitles of an audio-only recording are kept as a sidecar — `@runtime-verified`
- A file with no directory part transcribes instead of crashing — `@runtime-verified`
- The reconnect size guard is asserted at build time — `@build-verified`
- The screen and system-audio path is unchanged — `@stock`

**How it does it:** **Key procs:** `audioOnly`, `reconnectSizeIsCompatible`, `defaultOutPath`, `transcribe`, `flatten` · **Source files:** `screen-audio-record.swift`, `rec-audio.swift`, `rec-subtitle.swift`

**Grade:** @build-verified ×1 · @runtime-verified ×5 · @stock ×1


<a id="recburn-whisper-deps"></a>
## Install and verify compatible Whisper dependencies

`features/recburn-whisper-deps.feature` · [session](recburn-whisper-deps.session.md)

**Behaviour (4 scenarios):**

- Check the actual Whisper runtime without installing packages — `@runtime-verified`
- Install a compatible dependency family together — `@built`
- Real recording transcribes after dependency repair — `@runtime-verified`
- Subtitle burn-in exports the real recording — `@runtime-verified`

**How it does it:** **Key procs:** `resolve_python`, `check_whisper` · **Source files:** `bin/rec-subtitle.swift`

**Grade:** @built ×1 · @runtime-verified ×3

