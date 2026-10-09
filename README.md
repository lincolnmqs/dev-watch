# DevWatch

DevWatch is a native macOS menu bar utility for developers who want a quick view of local services running on open ports and of the builds running on their machine.

It lives in the menu bar, scans your machine with `lsof -i -P -n`, and shows useful local listening services in a lightweight SwiftUI popover.

## Features

- Native macOS app built with Swift and SwiftUI
- Runs as a menu bar utility
- Lists useful local listening services
- Groups services by detected project directory
- Detects common developer stacks such as Next.js, Vite, PostgreSQL, Redis, Python servers, and local APIs
- Shows friendly labels, aliases, port, process name, PID, and protocol
- Opens localhost services in the browser
- Reveals binaries, copies URLs or ports, and shows launch commands
- Terminates a process with safe and force-kill options
- Auto-refreshes every 3 seconds
- Passive native notifications for service start, stop, and port ownership changes
- Manual refresh support
- Minimal macOS-style popover UI
- Tracks running builds (Gradle/Android, React Native, Flutter, `xcodebuild`, `eas build --local`) with a progress bar, elapsed time and an estimate based on previous runs
- Shows build progress next to the menu bar icon, notifies when a build finishes, and reveals the produced APK/AAB/IPA

## Why DevWatch

When you're running multiple local tools like:

- frontend dev servers
- API backends
- Docker-exposed services
- database containers
- background workers

it is easy to lose track of what is actually listening on your machine.

DevWatch gives you a fast menu bar view for that information without opening Terminal or Activity Monitor.

## How It Works

DevWatch executes:

```bash
lsof -i -P -n
```

It then filters the results to show developer-useful local services only:

- TCP services
- listening ports
- local hosts such as `127.0.0.1`, `::1`, `localhost`, or `*`

This avoids clutter from outbound client connections from apps like browsers, chat apps, and streaming tools.

## Build Tracking

DevWatch finds running builds by their processes and shows elapsed time. After a build of the same project and task has finished once, it also estimates progress and time remaining from the median of recent runs.

For real Gradle task progress (the same percentage Gradle prints in the terminal), add the init script from `DevWatch/Services/GradleProgressReporter.swift` to `~/.gradle/init.d/devwatch-progress.gradle`. It writes a small JSON progress file to `~/Library/Application Support/DevWatch/builds`, which DevWatch reads. It works for terminal, React Native, Flutter and Android Studio builds, and supports the configuration cache.

## Tech Stack

- Swift
- SwiftUI
- AppKit where needed
- Native macOS APIs
- Target: macOS 13+

## Project Structure

```text
DevWatch/
├── DevWatch.xcodeproj
├── DevWatch/
│   ├── App/
│   ├── MenuBar/
│   ├── Models/
│   ├── Services/
│   ├── ViewModels/
│   ├── Views/
│   └── Resources/
└── README.md
```

### Key folders

- `DevWatch/App`: app entry point and app configuration
- `DevWatch/MenuBar`: menu bar state/controller
- `DevWatch/Models`: port and process models
- `DevWatch/Services`: `lsof` execution and parsing
- `DevWatch/ViewModels`: refresh cycle and actions
- `DevWatch/Views`: SwiftUI popover UI

## Requirements

- macOS 13 or later
- Xcode 15 or later recommended

## Run in Xcode

1. Open `DevWatch.xcodeproj` in Xcode.
2. Select the `DevWatch` scheme.
3. Choose `My Mac` as the run destination.
4. Press `Cmd + R`.

The app launches in the menu bar and does not show a Dock icon.

## Build the App

### In Xcode

1. Choose `Product > Build`.
2. In the Project Navigator, open `Products`.
3. Right-click `DevWatch.app`.
4. Choose `Show in Finder`.

### With xcodebuild

```bash
xcodebuild -project DevWatch.xcodeproj -scheme DevWatch -configuration Debug build
```

The built `.app` will be placed in Xcode's Derived Data output directory.

## Usage

1. Launch DevWatch.
2. Click the DevWatch icon in the macOS menu bar.
3. Review detected local services.
4. Use the browser action for localhost-accessible services.
5. Use the terminate action to stop a process by PID.

## Example Use Cases

- Check whether your local server is actually running
- Confirm which process owns a port before killing it
- Quickly open a local web service in the browser
- See which dev tools are listening in the background

## Notes

- DevWatch is intentionally focused on local listening services, not every socket on the machine.
- Some system services may still appear if they are genuinely listening on local ports.
- Process termination uses `kill -TERM` for a safer default shutdown signal.

## Roadmap

- Search and filtering
- Optional hide rules for system processes
- Docker container enrichment
- Session snapshots
- CLI companion
