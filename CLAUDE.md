# Lumina

A SwiftUI macOS menu bar app (`MenuBarExtra`, window style) that hosts focus utilities in a Control Center–style panel. Swift package, no Xcode project. macOS 26+. See README.md for the user-facing feature list.

## Toolchain constraints

- **No Xcode locally**, only the Command Line Tools (Swift 6.4). Their SDK lacks the SwiftUI macro plugin, so **`@State` doesn't compile**. Keep view state in a private `ObservableObject` held by `@StateObject` (see `SizeSelection`, `PickerSearch`), or in an `@Observable` store or controller. `@Observable`, `@Environment`, `@Bindable` and `@FocusState` all work.
- **CI uses Xcode 26.6 / Swift 6.3.3** (`macos-26` runner). It can fail where local builds pass. Example: passing a main-actor method directly as a closure (`set: selection.choose`) crashed the 6.3 compiler. Wrap it instead: `set: { selection.choose($0) }`.
- Swift 6 language mode: shared controllers are `@MainActor @Observable final class … { static let shared }`.

## Build and run

- `make run` builds `build/Lumina.app` via `scripts/build-app.sh`, kills the old instance and opens the new one. If `open` hits error -600 it retries.
- The build script:
  - embeds and signs `Sparkle.framework` from the inside out;
  - stamps `CFBundleVersion` with a timestamp, so macOS caches (like Notification Center's icon) refresh;
  - signs with the "Lumina Development" self-signed identity, falling back to ad hoc. A stable identity keeps Accessibility and Automation permissions across rebuilds;
  - runs `lsregister`.
- `scripts/setup-release-secrets.sh` (one-time, already done) sets the GitHub secrets and the Sparkle public key. `scripts/render-marketing.sh` regenerates `docs/marketing` (heroes, `x-overview.png`, `features/*.png`, plus half-size JPEGs in `readme/` that the README shows) and the README's feature gallery (between `<!-- features:start/end -->`). Features are derived from `Utility.catalog` + `LibraryDrag.NewItem`; **when adding a utility, add its card to `Feature.all` in `scripts/marketing/main.swift`** (the script warns otherwise). The hero layout (`heroTiles`) mirrors the user's own panel, and `heroLayout()` appends a tile for any feature it doesn't show yet (the canvas grows to fit); battery devices are fixed demo devices.

## Git flow (the user wants this followed)

- `develop` is the integration branch, and `main` is releases. Work happens on `feature/<name>` branched from `develop`, with a PR into `develop`. Only commit or push when the user asks.
- **Release:** open a PR `develop → main` titled `release_<version>`, plus a matching label (`gh label create`). Merging into `main` runs `.github/workflows/release.yml`, which publishes `v<major>.<minor>.<run_number>`. Get `major.minor` from Info.plist (0.1) and use the next run number (`gh run list --workflow release.yml`). Failed runs still use up a number.
- **Hotfix:** branch `hotfix/<name>` from `main`, then open PRs into both `main` and `develop`.
- Push over SSH as `hectorgoan`. End commit messages and PR bodies with the attribution lines from the system reminder.
- After a release, the user likes to be notified when the artifact publishes. Poll `gh release view v<x>` in a background loop, and look failures up by run *database ID*, not run number.

## Architecture

- `Core/Utility.swift`: a `Utility` has an id, name, symbol, `size` (`.quarter/.half/.full` = 1/2/4 grid columns), `content`, optional `settings`, `isHiddenByDefault` and `isRemovable`. `Utility.catalog` lists the built-in ones.
- `Core/UtilityStore.swift`:
  - Stores the order, hidden IDs (persisted; hidden ones always come after visible ones), user-added `worldClocks` and `batteryWidgets` (JSON in UserDefaults), and page state (`settingsUtilityID`, `isAddingWorldClock`, `isAddingBatteryWidget`).
  - Edit-mode flags: `isEditing` (layout), `isLibraryExpanded` (width) and `isLibraryPresented` (fade). `showsEditControls` is `isEditing && isLibraryPresented`.
- `Core/UtilityStore+Transitions.swift`: `swapPage`, `swapPage(adding:)`, `hideTile`, `showTile`, `removeTile` and `poofTile`.
- `Components/`:
  - `ReorderableGrid` and `TileGridLayout`: a four-column packing layout with drag-to-reorder.
  - `ModuleTile`, `EditBadge`, `ModuleToggleButton` and `CompactToggleModule`.
  - `Motion` (curves), `PanelFill` (`Color.panelSurface/panelControl/panelTrack`) and `FullWidthSegmentedPicker` (a wrapper around `NSSegmentedControl`).
  - `Poof` (the Dock poof, via a `dlsym` lookup of `NSShowAnimationEffect`).
- `App/`:
  - `PanelView`: the main column (grid, settings, add pages) plus `UtilityLibrary` (edit-mode sidebar) and the footer.
  - `MenuBarIcon`: the rays icon (drawn rays, so the Stay Green dot can replace one), with a Caffeine sun, the Stay Green indicator chosen in its settings (`StayGreenIndicator`: none/dot/halo/rays, optionally green) and the Pomodoro time. Everything must stay inside the 22 × 18 canvas, since the menu bar crops to it. Monochrome states are one template image; a green indicator is drawn by an `NSImage` drawing handler that tints the ink layer with `labelColor` at draw time and draws the green layer on top.
  - `UpdateController`: Sparkle, with update reminders shown as an in-panel banner. It checks at launch and every 6 h.

### The panel's animation rules (learned the hard way)

1. The menu bar window resizes to fit its content. **Animating its size while content is visible makes the glass flicker.** So every size change goes: fade out → resize while the space is empty → fade in. Use `UtilityStore+Transitions`; don't add bare `withAnimation` around page or tile changes.
2. Steps that hand off to the next one (`Motion.dismiss`, `Motion.resize`) are **fixed-length ease curves**. A spring's tail delays `completionCriteria: .removed` and leaves the panel sitting empty. `Motion.present` can be a spring.
3. Vibrant hierarchical fills (`.fill.quaternary` and the like) turn flat and dark while fading. Use `Color.panel*`. Fading views with vibrant text get `.fadesWithoutColorShift()` (a `compositingGroup`).
4. Only a lifted tile casts a shadow. Avoid materials on many small views.
5. The user wants animations to feel native, smooth and not slow. Simple fades beat fancy slides.

## Utilities (notable implementation details)

- **Appearance (and Compact Appearance / Appearance Row):** switches via `osascript` → System Events, which needs the Automation permission.
- **Caffeine:** `kIOPMAssertionTypePreventUserIdleDisplaySleep`.
- **Stay Green:** `IOPMAssertionDeclareUserActivity` every 30 s. No cursor movement or extra permissions.
- **Pomodoro:** durations live in its settings. Starting it requests notification permission, which needs a bundle.
- **Keyboard Lock:** a `CGEvent` tap, which needs Accessibility.
- **Quit All:** `NSRunningApplication.terminate()` with a keep-open list.
- **System / System List / CPU Focus:** `host_processor_info`, VM stats, and the SMC (private, `Utilities/SystemStatus/SMC.swift`) for temperature (`Tp*`/`Te*` keys) and fans.
- **Cleanup:** `CleanupCategory` (what and where), `CleanupScanner` (nonisolated: scans and removes, run in detached tasks), `CleanupController` (phases, persisted choices, two-click confirm, scan interval or manual scans; it only scans when the panel opens, never in the background). User folders only; Trash/Mail need Full Disk Access (detected by listing `~/.Trash`). Never run a real clean while testing: point `CleanupScanner` at a fake home.
- **Uninstaller:** `AppCatalog` (apps in /Applications and ~/Applications, last used from Spotlight, Apple's and Lumina protected), `LeftoverFinder` (exact bundle ID/name matches in ~/Library; left behind = reverse-DNS names with no installed app or same-vendor app), `UninstallerController` (pages via `store.uninstallerPage`, `NSWorkspace.recycle` + Put Back, /Applications watcher for deletions, notifications with Clean Up/Ignore actions), `Dumpster` (floating `NSPanel` drop window). `App/MenuBarPanel` finds the `MenuBarExtra`'s status button to open the panel programmatically and accept drops (window delegate). Never trash real files while testing: point `LeftoverFinder` at a fake home.
- **World clocks:** `WorldClockCity.all` has 458 validated cities (every UN capital). The menu bar items are `NSStatusItem`s, and the city tag is an `NSTextAttachment` drawn in `labelColor`.
- **Batteries:** the Mac's battery via `IOPSCopyPowerSourcesInfo`, accessories via `dlsym("IOPSCopyPowerSourcesByType")(4)`. Comes in S/M/L/XL.

## Verifying UI work

- Computer use and screen capture aren't available. The user shares screenshots and recordings, saved under `build/` (git-ignored). To read a recording, extract frames with a small AVFoundation script (`AVAssetImageGenerator` → contact sheet).
- Offscreen renders: compile the needed source files with a `main.swift` and use `ImageRenderer` (see `scripts/marketing/main.swift`). Caveats:
  - `PanelView`'s page container and glass button styles don't render (yellow placeholder, or blank), so compose from `ModuleTile` + `TileGridLayout`.
  - Vibrancy isn't reproduced.
  - Controllers that need `NSApp` require `NSApplication.shared` first.
- The user prefers **design proposals rendered as images before implementing UI**, and designs "like Apple would". Check renders yourself before sending them.
