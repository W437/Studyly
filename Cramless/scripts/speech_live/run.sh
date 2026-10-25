#!/bin/bash
# Runs the app's own lecture transcription (TranscriptionGate, the course-vocabulary engine choice,
# LectureFileTranscriber, the exam-flag detector) on this Mac's on-device speech model, against a lecture spoken by
# the Mac's voice. Shows the transcript with and without a course vocabulary.
#
#   scripts/speech_live/run.sh
set -eu
cd "$(dirname "$0")/../.."
out=build/speech_live
rm -rf "$out/src"; mkdir -p "$out/src"
cp Cramless/Lecture/LectureTranscription.swift Cramless/Lecture/TranscriptAssembler.swift \
   Cramless/Lecture/AudioBufferConverter.swift Cramless/Lecture/ExamFlagDetector.swift Cramless/Model/ModelTypes.swift \
   Cramless/Capture/TextPaginator.swift Cramless/Capture/CaptureTypes.swift "$out/src/"
cp scripts/speech_live/main.swift "$out/src/main.swift"
printf 'import AVFoundation\n// From Lecture/LectureRecorder.swift (which needs the iOS audio session).\ntypealias AudioListener = @Sendable (AVAudioPCMBuffer) -> Void\n' > "$out/src/Stubs.swift"
swiftc -O -target arm64-apple-macos26.0 "$out"/src/*.swift -o "$out/speech_live"
say -v Samantha -o "$out/lecture.aiff" "OK, so last time we finished interphase. Today, what actually happens when the cell divides. Prophase first. The chromatin condenses, and you can finally see chromosomes under the microscope. This one will be on the midterm, by the way: anaphase is where the sister chromatids get pulled apart. And telophase is basically prophase in reverse."
echo "### without a course vocabulary"
"$out/speech_live" "$out/lecture.aiff" ""
echo "### with the course's vocabulary"
"$out/speech_live" "$out/lecture.aiff" "interphase,prophase,metaphase,anaphase,telophase,chromatin,chromosomes,sister chromatids,centromeres,spindle fibres,cytokinesis,nuclear envelope,mitosis"
