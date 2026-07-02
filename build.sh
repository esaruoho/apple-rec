#!/bin/bash
# Build the screen-audio-record + rec-audio binaries (Apple-native, no third-party deps).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swiftc -O -o "$DIR/screen-audio-record" "$DIR/screen-audio-record.swift" \
  -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia \
  -framework CoreGraphics -framework AppKit
# rec-audio (split / flatten) must sit next to screen-audio-record so --auto-flatten finds it.
swiftc -O -o "$DIR/rec-audio" "$DIR/rec-audio.swift" \
  -framework AVFoundation -framework CoreMedia
echo "built: $DIR/screen-audio-record"
echo "built: $DIR/rec-audio"
