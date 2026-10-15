<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Lumina app icon">
</p>

<h1 align="center">Lumina</h1>

<p align="center">A macOS menu bar app that hosts small utilities to help you focus, styled like a Control Center applet.</p>

## Utilities

- **Appearance**: switch the system between Light and Dark mode.
- **Caffeine**: keep your Mac and its display awake while it's on, so neither sleep nor the screen saver kicks in.
- **Stay Green**: keep chat apps like Microsoft Teams showing you as available while it's on. It tells macOS you're active every 30 seconds, without moving the pointer or needing extra permissions. Your display won't sleep while it's on.
- **Pomodoro**: four 25-minute focus sessions with 5-minute breaks between them, then a 15-minute long break, repeated. You can change all three durations in its settings. Pause, skip or reset any step. Lumina chimes and posts a notification when a step ends and shows the countdown in the menu bar while a session is under way.
- **Keyboard**: lock the keyboard so you can clean it. Every key, including media and brightness keys, is ignored until you click the tile again; the mouse and trackpad keep working. Needs Accessibility permission.
- **Quit All**: quit every open app with one click, as if you pressed ⌘Q in each. Apps with unsaved changes still ask to save. In its settings, choose apps to keep open; Finder and Lumina are never quit.

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

This builds `build/Lumina.app`, signs it, and launches it. The build output says which signing identity it used.

The first time you switch appearance, macOS asks for permission to let Lumina control System Events. Keyboard Lock needs Accessibility permission.

### Keeping permissions across rebuilds

By default, builds are signed ad hoc. An ad hoc signature changes with every build, so macOS may ask for Accessibility and Automation permission again after a rebuild. To keep them, sign with a stable identity. You only need to do this once:

```bash
scripts/create-signing-cert.sh
```

This creates a self-signed code-signing certificate named "Lumina Development" in your login keychain. It asks before changing anything and doesn't change any trust settings. At the end it asks for your login password so codesign can use the key without a dialog on every build. If you skip that step, click **Always Allow** the first time a build asks.

From then on, `make run` finds the certificate and signs with it. Grant the permissions once more after the first build signed this way, and later builds keep them.

To sign with a different identity, set `LUMINA_SIGN_IDENTITY` to its name or SHA-1 hash (see `security find-identity -p codesigning`):

```bash
LUMINA_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make run
```

To go back to ad hoc signing, delete the "Lumina Development" certificate and its private key in Keychain Access.

## Adding a utility

1. Create a module view under `Sources/Lumina/Utilities/<Name>/`.
2. Add a `static let` `Utility` for it, choosing a `.full`, `.half` or `.quarter` size and, optionally, a `settings` view (see `PomodoroModule.swift`).
3. Register it in `Utility.catalog`.

New utilities go to the end of the user's saved order.

## License

Lumina is released under the [MIT License](LICENSE).

Made with ❤️ by [@hectorgoan](https://github.com/hectorgoan).
