# WHAT THIS CARD SPAWNS
# Codespace: screen-audio-record.swift; rec-audio.swift; rec-subtitle.swift; recaudio.
# Thinkspace: audio-only-recording.session.md.
# Areaspace: audio capture without a video track; does not alter the screen+audio path.
# SESSION: audio-only-recording.session.md
# RESULT: Code and card shipped as a PR to main: apple-rec #1.
# WATCH: audioOnly reconnectSizeIsCompatible defaultOutPath transcribe flatten
# RESULT-LOG >>
#   2026-10-21  direct-commit  touched: transcribe flatten
Feature: Record the audio of a call without recording the screen
  As a person in a meeting, I want the sound of the call and not its picture,
  So that a long call costs no CPU on frames nobody will watch.

  @runtime-verified
  Scenario: An audio-only recording has two audio tracks and no video track
    Given a recording started with --audio-only --also-mic
    When the recording is finalized
    Then the file is a .m4a carrying the app/system audio and the microphone as two tracks
    And it carries no video track at all
    # cite: screen-audio-record.swift setupWriter (~line 536); the produced .m4a was probed with ffprobe

  @runtime-verified
  Scenario: The YouTube-ready mix is written next to the audio-only recording
    Given an audio-only recording that used the microphone
    When it is finalized
    Then a <name>-flat.m4a is written with the app audio and the microphone mixed into one track
    And the manifest records the flat file as the final artifact
    # cite: screen-audio-record.swift finish (~line 1290); the produced .recburn.json names the flat file

  @runtime-verified
  Scenario: Flattening an audio-only recording produces a single mixed .m4a
    Given an audio-only .m4a with two tracks
    When rec-audio flatten is run on it
    Then it writes <name>-flat.m4a with one mixed track and no video track
    # cite: rec-audio.swift flatten (~line 662); the produced -flat.m4a was probed with ffprobe

  @runtime-verified
  Scenario: Subtitles of an audio-only recording are kept as a sidecar
    Given an audio-only .m4a
    When rec-subtitle is run on it
    Then the .srt sidecar is written
    And it reports that there is no picture to burn the subtitles into
    # cite: rec-subtitle.swift doBurn (~line 745)

  @runtime-verified
  Scenario: A file with no directory part transcribes instead of crashing
    Given a recording in the current directory, named with no directory part
    When rec-subtitle is run on it with no --srt sidecar
    Then Whisper is given a non-empty output directory and the .srt is written
    # cite: rec-subtitle.swift transcribe (~line 403)

  @build-verified
  Scenario: The reconnect size guard is asserted at build time
    Given the recorder's build script
    When it runs the recorder's self-test
    Then audio-only is allowed to reconnect whatever the display size is
    And video mode still refuses to append frames of a different size
    # cite: screen-audio-record.swift reconnectSizeIsCompatible (~line 1339); build.sh runs --self-test

  @stock
  Scenario: The screen and system-audio path is unchanged
    Given the ordinary screen + system audio recorder
    When a recording is started without --audio-only
    Then it still writes a .mov with the picture and the same audio tracks as before
    # cite: screen-audio-record.swift start (~line 418) — the video path is untouched by --audio-only
