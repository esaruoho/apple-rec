#!/bin/bash
# Build the screen-audio-record binary (Apple-native, no third-party deps).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
swiftc -O -o "$DIR/screen-audio-record" "$DIR/screen-audio-record.swift" \
  -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia \
  -framework CoreGraphics -framework AppKit
echo "built: $DIR/screen-audio-record"
