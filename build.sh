#!/bin/bash
# Build the screen-audio-record + rec-audio binaries (Apple-native, no third-party deps).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="$(uname -m)"
swiftc -O -o "$DIR/screen-audio-record" "$DIR/screen-audio-record.swift" \
  -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia \
  -framework CoreGraphics -framework CoreImage -framework AppKit
# rec-audio (split / flatten) targets macOS 13 so it runs on Ventura/Sonoma too (AVFoundation
# only; the 15+ export API is behind #available). Must sit next to screen-audio-record so
# --auto-flatten finds it.
swiftc -O -target "${ARCH}-apple-macos13.0" -o "$DIR/rec-audio" "$DIR/rec-audio.swift" \
  -framework AVFoundation -framework CoreMedia
# rec-subtitle (.srt + burn-in). Sits next to screen-audio-record so `rec --burn` finds it.
# Transcription needs openai-whisper on PATH (`pip install openai-whisper`).
swiftc -O -target "${ARCH}-apple-macos13.0" -o "$DIR/rec-subtitle" "$DIR/rec-subtitle.swift" \
  -framework AVFoundation -framework CoreMedia -framework QuartzCore -framework AppKit
echo "built: $DIR/screen-audio-record"
echo "built: $DIR/rec-audio"
echo "built: $DIR/rec-subtitle"
