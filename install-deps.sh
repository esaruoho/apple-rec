#!/bin/bash
# install-deps.sh — install the ONE 3rd-party dependency rec needs, and only for subtitles.
#
# Recording, webcam picture-in-picture, audio split/flatten, and subtitle BURN-IN are all
# Apple-native (ScreenCaptureKit / AVFoundation / Core Animation) — zero dependencies.
# The only thing that needs a 3rd-party tool is TRANSCRIPTION (turning speech into text):
# rec-subtitle shells out to the openai-whisper `whisper` CLI. This installs it.
set -e

echo "==> Installing openai-whisper (Whisper transcription)…"
if command -v pip3 >/dev/null 2>&1; then
  pip3 install -U openai-whisper
elif command -v pip >/dev/null 2>&1; then
  pip install -U openai-whisper
else
  echo "No pip found. Install Python 3 first (python.org, or 'brew install python')." >&2
  exit 1
fi

echo "==> Checking ffmpeg (Whisper decodes audio with it)…"
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "   ffmpeg not found — install it with:  brew install ffmpeg"
else
  echo "   ffmpeg ok."
fi

echo
echo "Done. Now subtitles work:"
echo "  rec-subtitle <video>          # → <video>.srt"
echo "  rec-subtitle <video> --burn   # → <video>-subtitled.mov"
echo "  rec --mic --pip --burn        # whole pipeline in one command"
