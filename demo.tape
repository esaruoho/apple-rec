# demo.tape — a "recorded-terminal GIF" script for the README banner.
#
# A GIF of the terminal doing its thing, generated deterministically (no screen-capturing a
# real session) by charmbracelet/vhs: it spins up a headless terminal, TYPES these commands,
# records the output, and writes an animated GIF. That GIF goes at the top of the README so a
# visitor sees what `rec` is in two seconds — the "hook."
#
# Regenerate (run from the repo root so ./rec resolves):
#   brew install vhs        # https://github.com/charmbracelet/vhs
#   ./build.sh              # so ./rec and ./screen-audio-record exist
#   vhs demo.tape           # → demo.gif
#
# `./rec --help` just prints usage (it never starts a real capture), and the final one-liner
# is typed but not run — enough to convey what the tool does without needing permissions.

Output demo.gif

Set Shell bash
Set FontSize 22
Set Width 1100
Set Height 660
Set Padding 24
Set Theme "Builtin Solarized Dark"

Hide
Type "export PS1='$ ' && clear"
Enter
Show

Type "# record screen + system audio at once — no BlackHole, no loopback driver"
Enter
Sleep 1200ms

Type "./rec --help"
Sleep 500ms
Enter
Sleep 4500ms

Type "# mic + webcam circle + burned subtitles, in one word:"
Enter
Sleep 1200ms

Type "recburn   # = ./rec --mic --pip --burn"
Sleep 3000ms
