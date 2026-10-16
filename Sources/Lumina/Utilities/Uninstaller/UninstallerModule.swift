import SwiftUI

extension Utility {
    static let uninstaller = Utility(
        id: "uninstaller",
        name: "Uninstaller",
        symbol: "xmark.app.fill",
        size: .full,
        content: { AnyView(UninstallerModule(controller: .shared)) },
        settings: { AnyView(UninstallerSettings(controller: .shared)) }
    )
}

/// Search any app to uninstall, with the largest unused ones underneath.
/// Turns into an offer to clean up when an app is deleted in Finder.
struct UninstallerModule: View {
    let controller: UninstallerController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Group {
                if let notice = controller.notice {
                    noticeView(notice)
                } else {
                    browseView
                }
            }
            // The same height either way, so the panel never resizes.
            .frame(height: 92, alignment: .top)
            .transition(.opacity)
        }
        .animation(.snappy(duration: 0.25), value: controller.notice?.bundleID)
        .onAppear { controller.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "xmark.app.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.red.opacity(0.85)))

            VStack(alignment: .leading, spacing: 1) {
                Text("Uninstaller")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Button {
                DumpsterWindowController.shared.show()
            } label: {
                DumpsterGlyph(size: 16)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.panelTrack))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Open Dumpster")
            .accessibilityLabel("Open Dumpster")
        }
    }

    private var subtitle: String {
        if let notice = controller.notice { return "\(notice.name) left files behind" }
        let unused = controller.unusedApps
        guard !unused.isEmpty else { return "Removes apps and what they leave" }
        let bytes = controller.unusedBytes
        let count = unused.count == 1 ? "1 unused app" : "\(unused.count) unused apps"
        return bytes > 0 ? "\(count) · \(CleanupFormat.bytes(bytes))" : count
    }

    // MARK: - Browsing

    private var browseView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Opens the full list with the search field focused.
            Button(action: controller.openList) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                    Text("Search apps to uninstall")
                        .font(.system(size: 12))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            let unused = Array(controller.unusedApps.prefix(4))
            if unused.isEmpty {
                Text(controller.hasScanned
                     ? "No apps unused for \(controller.unusedThreshold.title)."
                     : "Looking at your apps…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
            } else {
                HStack(spacing: 0) {
                    ForEach(unused) { app in
                        Button { controller.review([app]) } label: {
                            VStack(spacing: 2) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                Text(app.bytes.map(CleanupFormat.bytes) ?? "…")
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                                Text(UninstallerFormat.age(app.lastUsed))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .help("Uninstall \(app.name)")
                    }
                    // Keep icons at the same width when there are fewer than four.
                    ForEach(unused.count..<4, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    // MARK: - After an app was deleted in Finder

    private func noticeView(_ notice: LeftBehindApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, .red)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(notice.name) was deleted")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Its files are still on your Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(CleanupFormat.bytes(notice.bytes)) in \(notice.items.count) \(notice.items.count == 1 ? "place" : "places")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Ignore", action: controller.ignoreNotice)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                Button("Clean Up", action: controller.reviewNotice)
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .controlSize(.small)
            }
        }
    }
}

/// The Uninstaller's settings: the menu bar tip, what counts as unused,
/// noticing deletions, and the Never Uninstall list.
struct UninstallerSettings: View {
    @Bindable var controller: UninstallerController
    @StateObject private var tip = TipVisibility()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !controller.isDropTipDismissed {
                DropTip(dismiss: dismissTip)
                    .opacity(tip.isVisible ? 1 : 0)
            }

            label("Suggest Apps Not Opened In")
            FullWidthSegmentedPicker(
                options: UninstallerController.UnusedThreshold.allCases.map { ($0.title, $0) },
                selection: $controller.unusedThreshold
            )
            .accessibilityLabel("Suggest Apps Not Opened In")

            Divider()

            Toggle("Notice Apps Moved to the Trash", isOn: $controller.noticesDeletions)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))
            caption("When you delete an app in Finder, Lumina offers to remove what it left behind.")

            Divider()

            label("Never Suggest or Uninstall")
            if controller.protectedApps.isEmpty {
                caption("Apps you add here are never suggested, and Lumina refuses to remove them.")
            }
            ForEach(controller.protectedApps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    Button { controller.unprotect(app) } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(app.name) from the list")
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Button("Add App…") { controller.chooseAppToProtect() }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("Apple’s apps are always protected.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// The tip fades out, then the page closes its space.
    private func dismissTip() {
        withAnimation(Motion.dismiss, completionCriteria: .removed) {
            tip.isVisible = false
        } completion: {
            withAnimation(Motion.resize) { controller.isDropTipDismissed = true }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A dismissible tip: apps can be dropped on the menu bar icon.
private struct DropTip: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.max.fill")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("Drop Apps on the Menu Bar")
                    .font(.system(size: 12, weight: .semibold))
                Text("Drag an app from Finder onto Lumina’s icon in the menu bar to uninstall it. Or open the Dumpster from the tile and toss in several at once.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Hide this tip")
        }
        .padding(10)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.yellow.opacity(0.25), lineWidth: 0.8))
    }
}

@MainActor
private final class TipVisibility: ObservableObject {
    @Published var isVisible = true
}
