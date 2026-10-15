# Lumina

A macOS menu bar app that hosts small utilities to help you focus, styled like a Control Center applet.

## Utilities

- **Appearance**: switch the system between Light and Dark mode.

Click **Edit Utilities** at the bottom of the panel, then drag the modules to rearrange them. Lumina remembers the order.

## Building

Requires macOS 26 or later and Swift 6.2 or later (Command Line Tools are enough).

```bash
make run
```

This builds `build/Lumina.app`, signs it ad hoc, and launches it.

The first time you switch appearance, macOS asks for permission to let Lumina control System Events. Because each build is signed ad hoc, a rebuilt app may ask again.

## Adding a utility

1. Create a module view under `Sources/Lumina/Utilities/<Name>/`.
2. Add a `static let` `Utility` for it (see `AppearanceModule.swift`).
3. Register it in `Utility.catalog`.

New utilities go to the end of the user's saved order.
