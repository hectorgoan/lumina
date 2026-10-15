import SwiftUI

/// The content of the menu bar window, laid out like a Control Center applet.
struct PanelView: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            if let utility = store.settingsUtility, let settings = utility.settings {
                SettingsPage(utility: utility, content: settings)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                UtilityGrid()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            PanelFooter()
        }
        .padding(12)
        .frame(width: 320)
        .clipped()
        .onDisappear { store.isEditing = false }
    }
}

/// The utilities, plus the hidden ones while editing.
private struct UtilityGrid: View {
    @Environment(UtilityStore.self) private var store
    private let updates = UpdateController.shared

    var body: some View {
        VStack(spacing: 12) {
            if let version = updates.availableVersion, !store.isEditing {
                UpdateBanner(version: version, updates: updates)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if store.isEditing {
                Text("Drag utilities to rearrange them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if store.visibleUtilities.isEmpty {
                Text("All utilities are hidden.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }

            ReorderableGrid(
                items: Binding(
                    get: { store.isEditing ? store.utilities : store.visibleUtilities },
                    set: { store.reorder($0) }
                ),
                isEditing: store.isEditing,
                spacing: 10,
                span: \.size.span
            ) { utility, isLifted in
                ModuleTile(
                    isEditing: store.isEditing,
                    isLifted: isLifted,
                    isHidden: store.isHidden(utility)
                ) {
                    utility.content()
                } badges: {
                    badges(for: utility)
                }
            }
        }
    }

    private func badges(for utility: Utility) -> some View {
        HStack(spacing: 4) {
            if utility.settings != nil {
                EditBadge(symbol: "gearshape.fill", help: "\(utility.name) Settings") {
                    withAnimation(.snappy) { store.settingsUtilityID = utility.id }
                }
            }
            let isHidden = store.isHidden(utility)
            EditBadge(
                symbol: isHidden ? "eye.slash.fill" : "eye.fill",
                help: isHidden ? "Show \(utility.name)" : "Hide \(utility.name)"
            ) {
                withAnimation(.snappy) { store.toggleVisibility(of: utility) }
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

            Button {
                withAnimation(.snappy) { updates.dismissBanner() }
            } label: {
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
                    withAnimation(.snappy) { store.settingsUtilityID = nil }
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
            Group {
                if store.isEditing {
                    Button(action: toggleEditing) {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    Button(action: toggleEditing) {
                        Text("Edit Utilities").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
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

    private func toggleEditing() {
        withAnimation(.snappy) { store.isEditing.toggle() }
    }
}
