# Report Cards — Index

The commit ⇄ card map. Every behaviour cluster in this repo gets ONE card
(`<name>.feature`), its spawning conversation (`<name>.session.md`), and a
RESULT-LOG of what shipped. Enrol each new card here.

Derived views — GENERATED, never hand-edit:
- `README.md` — what each card does + how it does it (`print-card.py --readme`)
- `STATUS.md` — the test matrix from the `@grade` tags (`gen-status.py`)
- `SESSIONS.generated.md` — the conversations behind the cards (`gen-sessions.py`)

| Card | What it covers | Session | Shipped in |
|------|----------------|---------|------------|
| `recburn-whisper-deps` | Install and verify compatible Whisper dependencies | [session](recburn-whisper-deps.session.md) | `8028689` |
| `audio-only-recording` | Record the audio of a call without recording the screen | [session](audio-only-recording.session.md) | PR #1 |
