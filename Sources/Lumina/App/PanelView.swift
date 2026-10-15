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
                UtilityLibrary()
                    .frame(width: 230)
                    .fadesWithoutColorShift()
                    .opacity(store.isLibraryPresented ? 1 : 0)
                    .padding(.leading, 12)
                    .frame(width: store.isLibraryExpanded ? 242 : 0, alignment: .leading)
                    .clipped()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .onDisappear { store.isEditing = false }
    }

    /// The current page, with the footer pinned to the bottom of the panel
    /// even when the library beside it is taller.
    private var mainColumn: some View {
        VStack(spacing: 12) {
            currentPage
                // Pages swap without a transition: the menu bar window
                // resizes to fit its content, and laying out two pages at
                // once mid-animation made it flicker.
                .transition(.identity)

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
        } else {
            UtilityGrid()
        }
    }
}

/// The utilities, plus the hidden ones while editing.
private struct UtilityGrid: View {
    @Environment(UtilityStore.self) private var store
    @StateObject private var drop = LibraryDropTarget()
    private let updates = UpdateController.shared

    var body: some View {
        VStack(spacing: 12) {
            if let version = updates.availableVersion, !store.isEditing {
                UpdateBanner(version: version, updates: updates)
            }

            if store.isEditing {
                // Takes its space with the panel's layout, but fades with the
                // library, so the grid doesn't jump when edit mode ends.
                Text("Drag to rearrange. Hidden utilities wait in the Library.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .fadesWithoutColorShift()
                    .opacity(store.isLibraryPresented ? 1 : 0)
            }

            if store.visibleUtilities.isEmpty {
                Text(store.isEditing ? "Add utilities from the Library." : "All utilities are hidden.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }

            ReorderableGrid(
                items: Binding(
                    get: { store.visibleUtilities },
                    set: { store.reorder($0) }
                ),
                isEditing: store.showsEditControls,
                spacing: 10,
                span: \.size.span
            ) { utility, isLifted in
                ModuleTile(isEditing: store.showsEditControls, isLifted: isLifted) {
                    utility.content()
                } badges: {
                    badges(for: utility)
                }
            }

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

    private func badges(for utility: Utility) -> some View {
        HStack(spacing: 4) {
            if utility.settings != nil {
                EditBadge(symbol: "gearshape.fill", help: "\(utility.name) Settings") {
                    store.settingsUtilityID = utility.id
                }
            }
            if utility.isRemovable {
                EditBadge(symbol: "minus", help: "Remove \(utility.name)") {
                    store.remove(utility)
                }
            } else {
                let isHidden = store.isHidden(utility)
                EditBadge(
                    symbol: isHidden ? "eye.slash.fill" : "eye.fill",
                    help: isHidden ? "Show \(utility.name)" : "Hide \(utility.name)"
                ) {
                    store.toggleVisibility(of: utility)
                }
            }
        }
    }
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
                    store.settingsUtilityID = nil
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

    /// Opening: the panel widens, then the library and edit controls fade in.
    /// Closing: they fade out, then the panel narrows. The window's size only
    /// animates while the space it gains or loses is empty, which keeps its
    /// glass from flickering.
    private func toggleEditing() {
        if store.isEditing {
            // Fade everything out, then close up the empty space, then leave
            // edit mode once the panel is back to its usual width.
            withAnimation(Motion.dismiss, completionCriteria: .removed) {
                store.isLibraryPresented = false
            } completion: {
                withAnimation(Motion.resize, completionCriteria: .removed) {
                    store.isLibraryExpanded = false
                } completion: {
                    store.isEditing = false
                }
            }
        } else {
            store.isEditing = true
            // Next turn of the run loop, once edit mode's layout is in place.
            DispatchQueue.main.async {
                withAnimation(Motion.resize, completionCriteria: .removed) {
                    store.isLibraryExpanded = true
                } completion: {
                    withAnimation(Motion.present) { store.isLibraryPresented = true }
                }
            }
        }
    }
}
