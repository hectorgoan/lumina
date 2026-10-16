import SwiftUI

/// The content of the menu bar window, laid out like a Control Center applet.
struct PanelView: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            mainColumn
                .frame(width: 296)
                .frame(maxHeight: .infinity)

            if store.isEditing {
                // The panel widens before the library fades in, and narrows
                // after it fades out, so the window only animates its size
                // while the glass there is empty.
                sidebar
                    .frame(width: 230)
                    .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .fadesWithoutColorShift()
                    .opacity(store.isLibraryPresented ? 1 : 0)
                    .padding(.leading, 12)
                    .frame(width: store.isLibraryExpanded ? 242 : 0, alignment: .leading)
                    .clipped()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .onAppear { store.isPanelOpen = true }
        .onDisappear {
            store.isPanelOpen = false
            store.isEditing = false
            if !store.remembersMoreOpen { store.isMoreOpen = false }
            // The Uninstaller starts over next time, unless it's mid-way
            // through moving things to the Trash.
            if !UninstallerController.shared.isWorking { store.uninstallerPage = nil }
        }
    }

    /// Edit mode's sidebar. It stays while a settings or add page is open;
    /// only what's in it changes: the Library crossfades into a preview of
    /// the tile as the panel resizes for the page, and back again.
    private var sidebar: some View {
        ZStack(alignment: .top) {
            UtilityLibrary()
                .fadesWithoutColorShift()
                .opacity(store.isConfiguring ? 0 : 1)
                .allowsHitTesting(!store.isConfiguring)

            if store.isConfiguring {
                UtilityPreview()
                    .fadesWithoutColorShift()
                    .transition(.opacity)
            }
        }
    }

    /// The current page, with the footer pinned to the bottom of the panel
    /// even when the library beside it is taller.
    private var mainColumn: some View {
        VStack(spacing: 12) {
            currentPage
                // Pages fade out, swap while the panel resizes, and fade in
                // (see UtilityStore.swapPage); they never overlap.
                .transition(.identity)
                .fadesWithoutColorShift()
                .opacity(store.isPageVisible ? 1 : 0)

            Spacer(minLength: 0)

            PanelFooter()
        }
    }

    @ViewBuilder private var currentPage: some View {
        if let utility = store.settingsUtility, let settings = utility.settings {
            SettingsPage(utility: utility, content: settings)
        } else if store.isAddingWorldClock {
            WorldClockPicker()
        } else if store.isAddingBatteryWidget {
            BatteryWidgetPicker()
        } else if store.isMoreSettingsOpen {
            MoreSettingsPage()
        } else if let page = store.uninstallerPage {
            UninstallerPageView(page: page, controller: .shared)
        } else {
            UtilityGrid()
        }
    }
}

/// The utilities, plus the hidden ones while editing.
private struct UtilityGrid: View {
    @Environment(UtilityStore.self) private var store
    @StateObject private var drop = LibraryDropTarget()
    @StateObject private var tileFrames = TileFrames()
    @StateObject private var banner = BannerState()
    private let updates = UpdateController.shared

    var body: some View {
        VStack(spacing: 12) {
            if let version = banner.version, !store.isLibraryExpanded {
                // Fades out before edit mode's resize and back in after it;
                // its space closes and reopens with the resize itself.
                UpdateBanner(version: version, updates: updates)
                    .fadesWithoutColorShift()
                    .opacity(store.isEditing || !banner.isVisible ? 0 : 1)
                    .transition(.identity)
            }

            if store.isLibraryExpanded {
                // Its space opens and closes with the panel's resize, so the
                // utilities glide down and back up; the text itself fades with
                // the library.
                Text("Drag to rearrange, or into \(store.moreTitle) to tuck utilities away. Hidden ones wait in the Library.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .fadesWithoutColorShift()
                    .opacity(store.isLibraryPresented ? 1 : 0)
                    .transition(.identity)
            }

            if store.visibleUtilities.isEmpty {
                Text(store.isEditing ? "Add utilities from the Library." : "All utilities are hidden.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }

            // One grid in every mode, the More section's header included,
            // so opening it and entering edit mode reuse the panel's usual
            // steps; in edit mode, dragging a tile past the header moves it
            // into the section.
            ReorderableGrid(
                items: Binding(
                    get: { store.panelGridItems },
                    set: { store.applyPanelGridOrder($0) }
                ),
                isEditing: store.showsEditControls,
                spacing: 10,
                span: \.span,
                canDrag: { $0.utility != nil }
            ) { item, isLifted in
                switch item {
                case .utility(let utility):
                    tile(utility, isLifted: isLifted)
                case .moreHeader:
                    if store.isLibraryExpanded {
                        MoreEditHeader()
                            .fadesWithoutColorShift()
                            .opacity(store.isLibraryPresented ? 1 : 0)
                            .anchorPreference(key: MoreSectionBounds.self, value: .bounds) { [$0] }
                    } else {
                        MoreHeader()
                            .fadesWithoutColorShift()
                            .opacity(store.isEditing ? 0 : 1)
                    }
                case .moreHint:
                    MoreDropHint()
                        .opacity(store.isLibraryPresented ? 1 : 0)
                        .anchorPreference(key: MoreSectionBounds.self, value: .bounds) { [$0] }
                }
            }
            // Outlines the section in edit mode.
            .overlayPreferenceValue(MoreSectionBounds.self) { anchors in
                GeometryReader { proxy in
                    if let first = anchors.first {
                        let rect = anchors.dropFirst().reduce(proxy[first]) { $0.union(proxy[$1]) }.insetBy(dx: -6, dy: -6)
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .opacity(store.isLibraryPresented ? 1 : 0)
                    }
                }
                .allowsHitTesting(false)
            }

            if store.moreStyle == .pages && !store.moreUtilities.isEmpty && !store.isLibraryExpanded {
                MorePageDots()
                    .fadesWithoutColorShift()
                    .opacity(store.isEditing ? 0 : 1)
            }

        }
        // An update found while the panel is open: the panel makes room
        // first, then the banner fades in; dismissing it goes in reverse.
        .onChange(of: updates.availableVersion, initial: true) { old, new in
            banner.update(to: new, animated: old != new, store: store)
        }
        // Utilities dragged in from the library land at the end.
        .dropDestination(for: String.self) { payloads, _ in
            payloads.contains { LibraryDrag.handle($0, in: store) }
        } isTargeted: { isTargeted in
            drop.isTargeted = isTargeted && store.showsEditControls
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .padding(-6)
                .opacity(drop.isTargeted ? 1 : 0)
                .animation(.snappy, value: drop.isTargeted)
                .allowsHitTesting(false)
        }
    }

    private func tile(_ utility: Utility, isLifted: Bool) -> some View {
        let isInMore = store.moreUtilities.contains { $0.id == utility.id }
        return ModuleTile(isEditing: store.showsEditControls, isLifted: isLifted) {
            utility.content()
        } badges: {
            badges(for: utility)
        }
        // Tiles being added or removed fade while the grid makes or closes
        // their space; so do the section's while it opens or closes.
        .opacity(store.fadingUtilityIDs.contains(utility.id) || (isInMore && isMoreTileHidden) ? 0 : 1)
        .anchorPreference(key: MoreSectionBounds.self, value: .bounds) { isInMore && store.isLibraryExpanded ? [$0] : [] }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            tileFrames.rects[utility.id] = frame
        }
    }

    /// Whether the section's tiles are invisible right now: while it opens
    /// or closes, and in edit mode while the Library fades in or out, if
    /// they weren't showing already.
    private var isMoreTileHidden: Bool {
        if store.isLibraryExpanded {
            let wasShowing = store.isMoreOpen && store.moreStyle != .pages
            return !store.isLibraryPresented && !wasShowing
        }
        return store.isMoreFading
    }

    private func badges(for utility: Utility) -> some View {
        HStack(spacing: 4) {
            if utility.settings != nil {
                EditBadge(symbol: "gearshape.fill", help: "\(utility.name) Settings") {
                    store.swapPage { store.settingsUtilityID = utility.id }
                }
            }
            if utility.isRemovable {
                EditBadge(symbol: "minus", help: "Remove \(utility.name)") {
                    // The Dock's poof where the tile was; a fade if it can't play.
                    if let frame = tileFrames.rects[utility.id], Poof.show(over: frame, in: NSApp.keyWindow) {
                        store.poofTile(utility)
                    } else {
                        store.removeTile(utility)
                    }
                }
            } else {
                let isHidden = store.isHidden(utility)
                EditBadge(
                    symbol: isHidden ? "eye.slash.fill" : "eye.fill",
                    help: isHidden ? "Show \(utility.name)" : "Hide \(utility.name)"
                ) {
                    store.hideTile(utility)
                }
            }
        }
    }
}

/// The update banner as shown, trailing the update controller so its
/// arrival and departure can be animated in steps.
@MainActor
private final class BannerState: ObservableObject {
    /// Makes room for the banner while set.
    @Published var version: String?
    /// The banner's opacity, which changes once its room is made.
    @Published var isVisible = false

    func update(to newVersion: String?, animated: Bool, store: UtilityStore) {
        switch (version, newVersion) {
        case (nil, let arriving?):
            guard animated else {
                version = arriving
                isVisible = true
                return
            }
            store.step(Motion.resize, lasting: Motion.resizeDuration) {
                self.version = arriving
            } completion: {
                withAnimation(Motion.present) { self.isVisible = true }
            }
        case (_?, nil):
            store.step(Motion.dismiss, lasting: Motion.dismissDuration) {
                self.isVisible = false
            } completion: {
                withAnimation(Motion.resize) { self.version = nil }
            }
        default:
            version = newVersion
        }
    }
}

/// Where each tile is in the window, for the poof when one is removed.
/// Not published: updating it shouldn't redraw anything.
private final class TileFrames: ObservableObject {
    var rects: [String: CGRect] = [:]
}

/// Tells the user a new version is ready, above the utilities.
private struct UpdateBanner: View {
    let version: String
    let updates: UpdateController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("Update Available")
                    .font(.system(size: 13, weight: .semibold))
                Text("Lumina \(version) is ready to install.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("Update", action: updates.checkForUpdates)
                .buttonStyle(.glassProminent)
                .controlSize(.small)

            Button(action: updates.dismissBanner) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remind Me Later")
        }
        .padding(12)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.tint.opacity(0.25), lineWidth: 0.5)
        }
    }
}

/// A utility's settings, shown in place of the grid.
private struct SettingsPage: View {
    @Environment(UtilityStore.self) private var store
    let utility: Utility
    let content: @MainActor () -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    store.swapPage { store.settingsUtilityID = nil }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Back to Utilities")
                .keyboardShortcut(.cancelAction)

                Text(utility.name)
                    .font(.system(size: 15, weight: .semibold))

                Spacer()
            }

            ModuleTile(isEditing: false, isLifted: false) {
                content()
            } badges: {
                EmptyView()
            }
        }
    }
}

/// The bottom bar with the edit toggle and the app menu.
private struct PanelFooter: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            // Both buttons share one spot and crossfade, so switching between
            // them never shifts the layout.
            ZStack {
                Button(action: toggleEditing) {
                    Text("Edit Utilities").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .opacity(store.showsEditControls ? 0 : 1)
                .allowsHitTesting(!store.showsEditControls)

                Button(action: toggleEditing) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .opacity(store.showsEditControls ? 1 : 0)
                .allowsHitTesting(store.showsEditControls)
            }
            .controlSize(.large)

            Menu {
                Button("About Lumina", action: AboutPanel.show)
                Button("Check for Updates…", action: UpdateController.shared.checkForUpdates)
                Button("\(store.moreTitle) Section Settings…") { store.openMoreSettings() }
                    .disabled(!UpdateController.shared.canCheckForUpdates)
                Divider()
                Button("Quit Lumina") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis")
                    .frame(height: 16)
            }
            .menuIndicator(.hidden)
            .menuStyle(.button)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .fixedSize()
        }
    }

    /// Opening: the update banner (if any) fades out, the panel resizes to
    /// make room, then the library and edit controls fade in. Closing runs
    /// the same steps in reverse. The window's size only animates while the
    /// space it gains or loses is empty, which keeps its glass from
    /// flickering.
    private func toggleEditing() {
        if store.isEditing {
            withAnimation(Motion.dismiss, completionCriteria: .removed) {
                store.isLibraryPresented = false
            } completion: {
                withAnimation(Motion.resize, completionCriteria: .removed) {
                    store.isLibraryExpanded = false
                } completion: {
                    withAnimation(Motion.present) { store.isEditing = false }
                }
            }
        } else if UpdateController.shared.availableVersion != nil || !store.moreUtilities.isEmpty {
            // Fade the banner and the More section's header out first, so
            // their space changes while empty.
            withAnimation(Motion.dismiss, completionCriteria: .removed) {
                store.isEditing = true
            } completion: {
                expandForEditing()
            }
        } else {
            store.isEditing = true
            // Next turn of the run loop, once edit mode's layout is in place.
            DispatchQueue.main.async(execute: expandForEditing)
        }
    }

    private func expandForEditing() {
        withAnimation(Motion.resize, completionCriteria: .removed) {
            // Edit mode shows both pages at once.
            if store.moreStyle == .pages { store.isMoreOpen = false }
            store.isLibraryExpanded = true
        } completion: {
            withAnimation(Motion.present) { store.isLibraryPresented = true }
        }
    }
}
