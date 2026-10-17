import SwiftUI

/// Adds a media widget: pick a size and a background, see it in edit
/// mode's preview beside the page, add it.
struct MediaWidgetPicker: View {
    @Environment(UtilityStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Back to Utilities")
                .keyboardShortcut(.cancelAction)

                Text("Add Media")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()
            }

            MediaWidgetForm(widget: store.newMediaWidget, update: { store.newMediaWidget = $0 }, sizeFirst: true)

            Text(needsControls ? "Choose its controls to add it." : "Follows whatever is playing: Music, Spotify, a browser…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)

            Button(action: add) {
                Text("Add Widget").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(needsControls)
        }
        .onAppear { MediaController.shared.start() }
    }

    /// A Small one has to have its controls chosen first.
    private var needsControls: Bool {
        store.newMediaWidget.size == .small && store.newMediaWidget.smallControls == nil
    }

    private func add() {
        guard !needsControls else { return }
        store.swapPage(adding: { store.addMediaWidget(store.newMediaWidget) })
    }

    private func close() {
        let close = {
            store.isAddingMediaWidget = false
            store.resetNewMediaWidget()
        }
        store.swapPage(close)
    }
}
