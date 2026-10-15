# Pomodoro

A minimal Pomodoro timer for the macOS menu bar. Built with Swift, SwiftUI and AppKit. No accounts, analytics, network access or third-party dependencies.

<img src="docs/Pomodoro-chiaro.png" alt="Pomodoro menu bar panel" width="360">

## Features

- Adjustable Focus and Relax timers: 25 and 5 minutes by default, from 1 to 180 minutes each.
- Start, pause, resume and reset. Optional automatic phase switching.
- The panel opens when a phase ends, with optional sound that follows system volume and mute.
- Light and dark appearance, saved preferences and optional launch at login.
- Runs in the menu bar, with no Dock icon. Countdown updates stop when the panel is closed.

## Build and install

Requires an **Apple Silicon Mac**, **macOS 14+** and **Swift 6+** (Xcode 16+ or compatible Apple Command Line Tools).

Download or clone this repository, then run from its folder:

```sh
./scripts/build.sh
```

Move `dist/Pomodoro.app` to **Applications** and open it. Click the timer icon in the menu bar. Enable **Open at Login** from the **•••** menu if needed.

The script also creates `dist/Pomodoro-macOS-arm64.zip` for sharing. Builds are signed locally, not notarized by Apple; macOS may require approval on another Mac. Intel Macs are not supported by the build script.

## Usage

Choose Focus or Relax, adjust the duration and press **Start**. Closing the panel keeps the timer running. Duration changes apply the next time that phase starts; reset to apply them immediately.

**Space**: start/pause/resume · **⌘R**: reset · **Esc**: close panel · **⌘Q**: quit.

Timers account for time spent asleep. Quitting ends the current session; preferences are saved locally.

## Development

Open `Pomodoro.xcodeproj` in Xcode, or use the build script. Run the automated engine, model and system-service checks with:

```sh
./scripts/test.sh
```

Source is in `Sources/`, tests in `Tests/`. Build output stays in `dist/` and is excluded from Git.
