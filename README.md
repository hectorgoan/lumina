<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Lumina app icon">
</p>

<h1 align="center">Lumina</h1>

<p align="center">A macOS menu bar app that hosts small utilities to help you focus, styled like a Control Center applet.</p>

## Installing

1. Download [Lumina.zip](https://github.com/hectorgoan/lumina/releases/latest/download/Lumina.zip) from the latest release and unzip it.
2. Move **Lumina.app** to your Applications folder and open it.
3. Lumina isn't notarized by Apple, so the first time you open it macOS says it can't check it for malicious software. Go to **System Settings › Privacy & Security**, scroll to Security, and click **Open Anyway** next to the message about Lumina.

You only need to do this once. Lumina checks for updates when it opens and every six hours, and shows a banner at the top of its panel when one is ready; you can also choose **Check for Updates…** from the **…** menu. Updates install in place without asking you to allow Lumina again.

Requires macOS 26 or later.

## Utilities

- **Appearance**: switch the system between Light and Dark mode. Two smaller layouts start hidden; show them in edit mode:
  - **Compact Appearance**: just the Light and Dark previews, at half width.
  - **Appearance Row**: the toggle and the previews in a single full-width row.
- **Caffeine**: keep your Mac and its display awake while it's on, so neither sleep nor the screen saver kicks in.
- **Stay Green**: keep chat apps like Microsoft Teams showing you as available while it's on. It tells macOS you're active every 30 seconds, without moving the pointer or needing extra permissions. Your display won't sleep while it's on.
- **Pomodoro**: four 25-minute focus sessions with 5-minute breaks between them, then a 15-minute long break, repeated. You can change all three durations in its settings. Pause, skip or reset any step. Lumina chimes and posts a notification when a step ends and shows the countdown in the menu bar while a session is under way.
- **Keyboard**: lock the keyboard so you can clean it. Every key, including media and brightness keys, is ignored until you click the tile again; the mouse and trackpad keep working. Needs Accessibility permission.
- **Quit All**: quit every open app with one click, as if you pressed ⌘Q in each. Apps with unsaved changes still ask to save. In its settings, choose apps to keep open; Finder and Lumina are never quit.
- **System**: CPU, memory, CPU temperature and fan speed as gauges, with load for each core, grouped into efficiency and performance cores. Two alternative layouts start hidden; show them in edit mode:
  - **System List**: the same readings as rows with exact values, with the same per-core bars.
  - **CPU Focus**: a compact take with a large CPU figure, its last minute as a graph, and the other readings as pills.

  Temperature and fan speed come from the Mac's System Management Controller, which has no public API. Fan readings are hidden on Macs without fans.
- **World Clock**: a half-width card per city with its flag, city code (MAD, NYC, TYO…), current time, day and night, and how far ahead or behind it is. Add as many as you like from edit mode. In a clock's settings (the gear badge), choose to show it in the menu bar too, as its own item with just the time or with the city code as well. Click a clock in the menu bar to see its day and offset, or to hide it.
- **Batteries**: the charge of your Mac and its Bluetooth accessories (AirPods and their case, keyboards, mice, trackpads), the same devices macOS's own Batteries widget lists. Comes in four sizes: Small (1 device), Medium (2), Large (4) and Extra Large (a list of 6). By default it shows the devices with the lowest charge first; in its settings, change the size or choose devices yourself. Devices appear as they connect.

  The Mac's battery comes from a public API. Accessory levels come from `IOPSCopyPowerSourcesByType`, which IOKit exports but doesn't declare publicly.

Click **Edit Utilities** at the bottom of the panel to customize it:

- Drag the modules to rearrange them.
- Click the eye badge on a module to hide or show it. Hidden modules move to the bottom and only appear, dimmed, while editing.
- Click the gear badge to open a utility's settings, for utilities that have them.
- Click **+ Batteries** to add a battery widget: pick a size and see it with your devices before adding it.
- Click **+ World Clock** to pick a city and add a clock for it. Search by city, country or code; use the arrow keys and Return, or click. Clocks show a remove badge (−) instead of the eye.

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

## Releasing

Every push to `main` (usually a merged pull request) runs the [Release workflow](.github/workflows/release.yml) on GitHub's macOS 26 runner. It:

1. Builds Lumina and signs it with the "Lumina Development" certificate.
2. Zips the app and signs the zip with Sparkle's update key.
3. Publishes a GitHub Release with `Lumina.zip` and `appcast.xml`, the update feed the app checks.

Versions are `major.minor.run`: the major and minor version come from `CFBundleShortVersionString` in `Resources/Info.plist`, and the patch is the workflow's run number. To release 0.2, change the version in `Info.plist` to `0.2.0`.

Updates use [Sparkle](https://sparkle-project.org). Each update is signed with a private key that only you and the workflow have, and the app checks that signature before installing.

### One-time setup

```bash
scripts/setup-release-secrets.sh
```

This creates Sparkle's update signing key in your login keychain (or reuses an existing one) and writes its public half to `Resources/Info.plist`. It then stores these repository secrets with the GitHub CLI:

- `SPARKLE_PRIVATE_KEY`: the update signing key.
- `LUMINA_CERT_P12` and `LUMINA_CERT_PASSWORD`: the "Lumina Development" certificate, so release builds keep the same signature and macOS keeps Lumina's permissions across updates. Create the certificate first with `scripts/create-signing-cert.sh` if you haven't.

macOS asks you to allow access to the keychain along the way. Commit the updated `Resources/Info.plist` afterwards. The workflow refuses to release until the public key is set.

Keep a backup of the update key (Sparkle's `generate_keys -x` tool exports it). If it's lost, installed copies can't verify new updates.

## Adding a utility

1. Create a module view under `Sources/Lumina/Utilities/<Name>/`.
2. Add a `static let` `Utility` for it, choosing a `.full`, `.half` or `.quarter` size and, optionally, a `settings` view (see `PomodoroModule.swift`).
3. Register it in `Utility.catalog`.

New utilities go to the end of the user's saved order.

## License

Lumina is released under the [MIT License](LICENSE).

Made with ❤️ by [@hectorgoan](https://github.com/hectorgoan).
