# demo.tape — a "recorded-terminal GIF" script for the README banner.
#
# A GIF of the terminal doing its thing, generated deterministically (no screen-capturing a
# real session) by charmbracelet/vhs: it spins up a headless terminal, TYPES these commands,
# records the output, and writes an animated GIF. That GIF goes at the top of the README so a
# visitor sees what `rec` is in two seconds — the "hook."
#
# Regenerate:
#   brew install vhs        # https://github.com/charmbracelet/vhs
#   ./build.sh              # so ./rec and ./screen-audio-record exist
#   vhs demo.tape           # → demo.gif
#
# (Recording the screen needs a TTY with Screen Recording permission, so this demo shows the
#  usage/help surface rather than a live capture — enough to convey what the tool does.)

Output demo.gif

Set FontSize 22
Set Width 1100
Set Height 700
Set Padding 24
Set Theme "Builtin Solarized Dark"

Type "# record screen + system audio — no BlackHole, no loopback driver"
Enter
Sleep 1200ms

Type "rec --help"
Sleep 400ms
Enter
Sleep 3500ms

Type "# start with mic + webcam circle + burned subtitles, in one word:"
Enter
Sleep 1200ms

Type "recburn        # = rec --mic --pip --burn"
Sleep 400ms
Enter
Sleep 2500ms
