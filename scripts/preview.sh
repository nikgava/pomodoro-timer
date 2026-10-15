#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
PREVIEW_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/pomodoro-preview.XXXXXX")"
trap 'rm -rf "$PREVIEW_DIRECTORY"' EXIT

swiftc -parse-as-library -swift-version 6 \
    Sources/PomodoroCore/TimerEngine.swift \
    Sources/Pomodoro/TimerModel.swift \
    Sources/Pomodoro/SystemServices.swift \
    Sources/Pomodoro/PanelView.swift \
    scripts/PreviewMain.swift \
    -o "$PREVIEW_DIRECTORY/pomodoro-preview"
"$PREVIEW_DIRECTORY/pomodoro-preview" "$PROJECT_ROOT/docs"
