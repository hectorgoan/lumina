# Lumina

A macOS menu bar app that hosts small utilities to help you focus, styled like a Control Center applet.

## Utilities

- **Appearance**: switch the system between Light and Dark mode.
- **Caffeine**: keep your Mac from going to sleep while it's on.
- **Stay Green**: keep chat apps like Microsoft Teams showing you as available while it's on. It tells macOS you're active every 30 seconds, without moving the pointer or needing extra permissions. Your display won't sleep while it's on.
- **Pomodoro**: four 25-minute focus sessions with 5-minute breaks between them, then a 15-minute long break, repeated. You can change all three durations in its settings. Pause, skip or reset any step. Lumina chimes and posts a notification when a step ends and shows the countdown in the menu bar while a session is under way.

Click **Edit Utilities** at the bottom of the panel to customize it:

- Drag the modules to rearrange them.
- Click the eye badge on a module to hide or show it. Hidden modules move to the bottom and only appear, dimmed, while editing.
- Click the gear badge to open a utility's settings, for utilities that have them.

Lumina remembers your layout.

## Building

Requires macOS 26 or later and Swift 6.2 or later (Command Line Tools are enough).

```bash
make run
```

This builds `build/Lumina.app`, signs it ad hoc, and launches it.

The first time you switch appearance, macOS asks for permission to let Lumina control System Events. Because each build is signed ad hoc, a rebuilt app may ask again.

## Adding a utility

1. Create a module view under `Sources/Lumina/Utilities/<Name>/`.
2. Add a `static let` `Utility` for it, choosing a `.full` or `.half` size and, optionally, a `settings` view (see `PomodoroModule.swift`).
3. Register it in `Utility.catalog`.

New utilities go to the end of the user's saved order.
