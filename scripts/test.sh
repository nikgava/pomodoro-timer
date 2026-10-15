#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ $# -ne 0 ]]; then
    printf 'Uso: %s\n' "$0" >&2
    exit 2
fi

# These native executable harnesses work with Apple's Command Line Tools alone.
# The same engine cases also remain available to XCTest with a full Xcode install.
CHECK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/pomodoro-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIRECTORY"' EXIT

swiftc -swift-version 6 -D POMODORO_STANDALONE_TESTS \
    Sources/PomodoroCore/TimerEngine.swift \
    Tests/PomodoroCoreTests/TimerEngineTests.swift \
    Tests/PomodoroCoreTests/StandaloneRunner.swift \
    -o "$CHECK_DIRECTORY/engine-checks"
"$CHECK_DIRECTORY/engine-checks"

swiftc -parse-as-library -swift-version 6 \
    Sources/Pomodoro/SystemServices.swift \
    Tests/PomodoroTests/ServiceChecksMain.swift \
    -o "$CHECK_DIRECTORY/service-checks"
"$CHECK_DIRECTORY/service-checks"

swiftc -parse-as-library -swift-version 6 \
    Sources/PomodoroCore/TimerEngine.swift \
    Sources/Pomodoro/TimerModel.swift \
    Tests/PomodoroTests/ModelChecksMain.swift \
    -o "$CHECK_DIRECTORY/model-checks"
"$CHECK_DIRECTORY/model-checks"
