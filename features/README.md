# RecBurn — Feature Reference

> **Generated** from the Gherkin report cards in this folder by `python3 print-card.py --readme`. Do not hand-edit — edit the `.feature` card and regenerate. Each entry below = one card: *what it does* (intent + behaviour scenarios) and *how it does it* (the procs/files the behaviour is cited to).

Each card is a triad: the `.feature` spec, a `.session.md` (the conversation that produced it), and a RESULT-LOG of what shipped.

## Contents

- [Install and verify compatible Whisper dependencies](#recburn-whisper-deps) — `recburn-whisper-deps.feature`


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

