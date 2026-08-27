#!/bin/bash
# build.sh — build RecBurn.app (menu-bar recorder) AND the rec/recburn CLI, self-contained.
#
# Compiles the ScreenCaptureKit engine from the .swift sources in this folder, builds the
# SwiftUI menu-bar app, and assembles everything into RecBurn.app (engine binaries live in
# Contents/MacOS so the app finds them next to itself — no hardcoded paths).
#
# The CLI needs no build step of its own: rec / recburn / recburnclick are shell scripts
# that sit right here next to the binaries this produces.
#
#   ./build.sh              # build the engine + the app
#   ./build.sh --cli        # engine binaries only, skip the app (no SwiftPM needed)
#   ./build.sh --install    # also copy RecBurn.app to /Applications and link the CLI
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"; ARCH="$(uname -m)"; APP="$ROOT/RecBurn.app"; BIN="$ROOT"
ENGINE=(screen-audio-record rec-audio rec-subtitle)

echo "▸ compiling engine ($ARCH)…"
# CoreImage is needed for the webcam PiP circle and the --clicks counter badge.
swiftc -O -target ${ARCH}-apple-macos15.0 -o "$BIN/screen-audio-record" screen-audio-record.swift \
  -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia \
  -framework CoreGraphics -framework CoreImage -framework AppKit
# rec-audio / rec-subtitle target macOS 13 so they also run on Ventura/Sonoma.
swiftc -O -target ${ARCH}-apple-macos13.0 -o "$BIN/rec-audio" rec-audio.swift \
  -framework AVFoundation -framework CoreMedia
swiftc -O -target ${ARCH}-apple-macos13.0 -o "$BIN/rec-subtitle" rec-subtitle.swift \
  -framework AVFoundation -framework CoreMedia -framework QuartzCore -framework AppKit
# vision-ocr powers `recburn-redact --find` (on-device Apple Vision; nothing leaves the
# Mac). Built here so the redact tool is self-contained rather than reaching into another
# checkout for a helper.
swiftc -O -target ${ARCH}-apple-macos13.0 -o "$BIN/vision-ocr" vision-ocr.swift \
  -framework Vision -framework AppKit -framework CoreImage
chmod +x rec recburn recburnclick recburn-redact recburn-url recburn-youtube

# The proper-noun vocabulary is pure logic, so it is checked headlessly HERE rather than by
# discovering mid-screencast that "Paketti" came out as "Pucketty" again.
echo "▸ checking the vocabulary rules…"
"$BIN/rec-subtitle" --self-test

# The voice/app balance decision and every filter in the mic chain are pure arithmetic too,
# so they are asserted here rather than discovered three minutes into a screencast.
echo "▸ checking the audio balance rules…"
"$BIN/rec-audio" --self-test

if [ "${1:-}" = "--cli" ]; then
  echo "✓ CLI ready: ./rec , ./recburn , ./recburnclick"
  exit 0
fi

echo "▸ building the app…"
swift build -c release
APPBIN="$(swift build -c release --show-bin-path)/RecBurn"

echo "▸ assembling RecBurn.app…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$APPBIN" "$APP/Contents/MacOS/RecBurn"
for e in "${ENGINE[@]}"; do cp "$BIN/$e" "$APP/Contents/MacOS/$e"; done   # engine beside the app binary
cp "$ROOT/recburn-vocabulary.json" "$APP/Contents/MacOS/"                  # rec-subtitle looks beside itself
cp "$BIN/recburn-url" "$BIN/recburn-youtube" "$APP/Contents/MacOS/"        # helpers the App Intents resolve next to themselves
[ -f "$ROOT/AppIcon.icns" ] && cp "$ROOT/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" || true
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>RecBurn</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>com.esaruoho.recburn</string>
	<key>CFBundleName</key><string>recburn</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.3</string>
	<key>LSMinimumSystemVersion</key><string>15.0</string>
	<key>LSUIElement</key><true/>
	<key>NSCameraUsageDescription</key><string>recburn overlays your webcam as picture-in-picture.</string>
	<key>NSMicrophoneUsageDescription</key><string>recburn records your microphone.</string>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key><string>com.esaruoho.recburn</string>
			<key>CFBundleURLSchemes</key><array><string>recburn</string></array>
		</dict>
	</array>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key><dict><key>default</key><string>RecBurn: Toggle Recording</string></dict>
			<key>NSMessage</key><string>toggleRecording</string>
			<key>NSPortName</key><string>RecBurn</string>
			<key>NSSendTypes</key><array/>
			<key>NSReturnTypes</key><array/>
		</dict>
		<dict>
			<key>NSMenuItem</key><dict><key>default</key><string>RecBurn: Start Recording</string></dict>
			<key>NSMessage</key><string>startRecording</string>
			<key>NSPortName</key><string>RecBurn</string>
			<key>NSSendTypes</key><array/>
			<key>NSReturnTypes</key><array/>
		</dict>
		<dict>
			<key>NSMenuItem</key><dict><key>default</key><string>RecBurn: Stop Recording</string></dict>
			<key>NSMessage</key><string>stopRecording</string>
			<key>NSPortName</key><string>RecBurn</string>
			<key>NSSendTypes</key><array/>
			<key>NSReturnTypes</key><array/>
		</dict>
	</array>
</dict>
</plist>
PLIST

echo "▸ signing (ad-hoc, stable identifier)…"
codesign --force --deep --sign - --identifier com.esaruoho.recburn "$APP" >/dev/null
echo "✓ built: $APP"
echo "✓ CLI:   ./rec , ./recburn , ./recburnclick  (engine binaries alongside)"

if [ "${1:-}" = "--install" ]; then
  echo "▸ installing…"
  pkill -f "RecBurn.app/Contents/MacOS/RecBurn" 2>/dev/null || true; sleep 1
  rm -rf /Applications/RecBurn.app && cp -R "$APP" /Applications/RecBurn.app
  codesign --force --deep --sign - --identifier com.esaruoho.recburn /Applications/RecBurn.app >/dev/null
  # link the CLI into the first writable PATH dir — no sudo
  LINKDIR=""
  for d in "$HOME/.local/bin" /usr/local/bin "$HOME/bin"; do
    if mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then LINKDIR="$d"; break; fi
  done
  echo "✓ installed /Applications/RecBurn.app"
  if [ -n "$LINKDIR" ]; then
    for e in "${ENGINE[@]}" rec recburn recburnclick recburn-url recburn-youtube recburn-vocabulary.json; do ln -sf "$ROOT/$e" "$LINKDIR/$e"; done
    echo "✓ linked rec/recburn into $LINKDIR  (make sure it's on your PATH)"
  else
    echo "• CLI ready here — add it to PATH:  export PATH=\"$ROOT:\$PATH\""
  fi
  echo "  open it:  open /Applications/RecBurn.app"
fi
