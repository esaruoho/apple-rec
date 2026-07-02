# apple-rec — `rec`

Record your **screen and your Mac's audio at once**, from the terminal, with **no
loopback driver** — no BlackHole, no Loopback, no "route the speakers into the
microphone" hack.

```bash
rec
```

That's it. It starts recording the whole screen **+ all system audio** immediately and
saves `./yyyy-MM-dd-HH-mm-ss.mov` **in the folder you ran it from**. Press **Ctrl-C** to
stop and finalize.

## Why this exists

macOS's built-in recorders — QuickTime Player and the ⌘⇧5 Screenshot toolbar — only
offer a **microphone** picker. Apple omits system-audio capture from the built-in
recorder **on purpose**, which is why everyone reaches for a virtual-audio-device hack
(BlackHole/Loopback) that pretends to be a microphone.

But the capability ships in the OS: **ScreenCaptureKit**'s
`SCStreamConfiguration.capturesAudio` pulls audio **straight off the system audio
engine**, and an app-scoped `SCContentFilter` can capture **only one app's sound**. This
is a ~300-line Swift CLI that surfaces exactly that. Apple-frameworks only — no Homebrew,
no dependencies.

## Install

```bash
git clone https://github.com/esaruoho/apple-rec.git
cd apple-rec
./build.sh                      # compiles screen-audio-record (swiftc)
ln -s "$PWD/rec" /usr/local/bin/rec   # optional: put `rec` on your PATH
```

`rec` also auto-builds the binary on first run, so `./rec` works straight after clone.

Requires **macOS 13+** (ScreenCaptureKit); `--also-mic` needs **macOS 15+**. On first
run, macOS asks for **Screen Recording** permission for your terminal — approve it (System
Settings ▸ Privacy & Security ▸ Screen Recording). macOS Sequoia re-asks weekly / after
reboot; that's an OS policy the tool can't suppress.

## Usage

```bash
rec                      # whole screen + ALL system audio → ./<timestamp>.mov
rec --app Renoise        # screen + ONLY that app's audio (nothing else leaks in)
rec --mic                # start with your microphone recording too (2nd audio track)
rec --reveal             # reveal + select the finished file in Finder on stop
rec --out ~/demo.mov     # custom output path
rec --list               # list displays + audible running apps (for --app)
```

- **Stop** a terminal recording with **Ctrl-C** — it catches the signal and finalizes the
  `.mov`. Do not re-run `rec` to stop (that starts a second recording).
- **Toggle the mic on/off mid-recording** without stopping: send the process `SIGUSR1`,
  e.g. `kill -USR1 $(pgrep -n screen-audio-record)`. The mic goes to its own track, so
  muting just stops writing mic samples. Start muted (default) or hot (`--mic`).
- `--app <name>` overrides `--system-audio` — single-app audio wins.
- Output is one `.mov`: **H.264** video + **AAC** audio (a **2nd AAC track** for the mic
  when used), muxed via `AVAssetWriter`.

### Recording both system audio and the mic — and the YouTube trap

Pass `--mic` (or toggle it on live). System audio and the microphone are captured as **two
separate audio tracks** in the same `.mov` — so Final Cut / Premiere / DaVinci can balance
them independently.

**⚠️ YouTube and QuickTime play only the FIRST audio track.** Upload a raw 2-track recording
and your **voice (track 2) is silently dropped**. So `rec --mic` **also writes a
`<name>-flat.mov`** with system + mic **mixed into one track** — that's the file you upload.
(iMovie can't split embedded tracks either; see `rec-audio` below.)

### `rec-audio` — post-process for editing

```bash
rec-audio split   recording.mov            # → recording-system.m4a + recording-mic.m4a
rec-audio flatten recording.mov [-o out]   # → recording-flat.mov (video + one mixed track)
```

- **`split`** extracts each audio stream to its own `.m4a`. **iMovie recipe:** import the
  `.mov` (video + system audio), then drag `recording-mic.m4a` onto the timeline as a second
  audio track — now you can balance voice vs app sound independently.
- **`flatten`** mixes system + mic into one track on a video-**passthrough** `.mov` (no
  re-encode, no quality loss) via `AVAssetReaderAudioMixOutput`. Plays both everywhere —
  QuickTime, iMovie, YouTube. This is what `--auto-flatten` runs for you.

### Direct binary

`rec` is a thin wrapper over `screen-audio-record`, which you can call directly for full
control (e.g. `--system-audio` vs `--app`, `--display <n>`, `--fps <n>`):

```bash
./screen-audio-record --list
./screen-audio-record --app Renoise --out ~/take.mov
./screen-audio-record --system-audio --fps 30 --out ~/take.mov
```

## How it works

- `SCContentFilter` selects the display, or the display **including a single application**
  (for per-app audio isolation).
- `SCStreamConfiguration`: `capturesAudio = true`, `excludesCurrentProcessAudio = true`,
  48 kHz stereo; optional `captureMicrophone = true` (macOS 15+ native mic, no
  `AVCaptureSession`).
- An `SCStream` delivers `.screen` (BGRA frames), `.audio`, and optionally `.microphone`
  sample buffers, which are appended to an `AVAssetWriter` (`.mov`, H.264 + AAC).
- **Ctrl-C** (`SIGINT`) is handled by a `DispatchSource` that stops capture, marks the
  writer inputs finished, and finalizes the file.

## License

MIT — see [LICENSE](LICENSE).

---

Mirror of `bin/screen-audio-record` + `bin/rec` from
[esaruoho/apple](https://github.com/esaruoho/apple). The standalone repo is canonical on
divergence.
