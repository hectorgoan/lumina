import SwiftUI

/// The content of the menu bar window, laid out like a Control Center applet.
struct PanelView: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 12) {
            if store.isEditing {
                Text("Drag utilities to rearrange them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ReorderableStack(items: $store.utilities, isEditing: store.isEditing, spacing: 10) { utility, isLifted in
                ModuleTile(isEditing: store.isEditing, isLifted: isLifted) {
                    utility.content()
                }
            }

            PanelFooter()
        }
        .padding(12)
        .frame(width: 320)
        .onDisappear { store.isEditing = false }
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
                Button("About Lumina") {
                    NSApp.activate()
                    NSApp.orderFrontStandardAboutPanel()
                }
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
