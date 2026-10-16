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

/// Search any app to uninstall, with shortcuts to files left behind and
/// the Dumpster, or (if chosen in its settings) the largest unused apps.
/// Turns into an offer to clean up when an app is deleted in Finder.
struct UninstallerModule: View {
    let controller: UninstallerController

    var body: some View {
        let showsUnused = controller.showsUnusedOnTile
        VStack(alignment: .leading, spacing: 10) {
            header(showsDumpster: showsUnused)
            Group {
                if let notice = controller.notice {
                    noticeView(notice)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        searchButton
                        if showsUnused { unusedApps } else { shortcuts }
                    }
                }
            }
            // The same height whatever it shows, so the panel never resizes.
            .frame(height: showsUnused ? 92 : 68, alignment: .top)
            .transition(.opacity)
        }
        .animation(.snappy(duration: 0.25), value: controller.notice?.bundleID)
        .onAppear { controller.refreshIfStale() }
    }

    private func header(showsDumpster: Bool) -> some View {
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
                    // Changes animate, like Cleanup's status.
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: subtitle)
            }

            Spacer(minLength: 0)

            RefreshButton(isWorking: controller.isScanning, help: "Scan Again") { controller.scan() }

            if showsDumpster {
                roundButton(help: "Open Dumpster", action: { DumpsterWindowController.shared.show() }) {
                    DumpsterGlyph(size: 16)
                }
            }
        }
    }

    private func roundButton<Label: View>(help: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            label()
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.panelTrack))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var subtitle: String {
        if let notice = controller.notice { return "\(notice.name) left files behind" }
        guard controller.hasScanned else { return "Looking at your apps…" }
        if controller.isScanning { return "Scanning…" }
        guard controller.showsUnusedOnTile else {
            return controller.apps.count == 1 ? "1 app" : "\(controller.apps.count) apps"
        }
        let unused = controller.unusedApps
        guard !unused.isEmpty else { return "No unused apps" }
        let count = unused.count == 1 ? "1 unused app" : "\(unused.count) unused apps"
        return "\(count) · \(CleanupFormat.bytes(controller.unusedBytes))"
    }

    /// Opens the full list with the search field focused.
    private var searchButton: some View {
        Button { controller.openList() } label: {
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
    }

    // MARK: - Shortcuts (unused apps off)

    private var shortcuts: some View {
        HStack(spacing: 8) {
            chip(action: { controller.openList(tab: .leftBehind) }) {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 11, weight: .medium))
                Text("Left Behind")
                if controller.hasScanned && !controller.leftBehind.isEmpty {
                    Text("\(controller.leftBehind.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red.opacity(0.85)))
                        .transition(.opacity)
                }
            }
            .help("Files left by apps you deleted")

            chip(action: { DumpsterWindowController.shared.show() }) {
                DumpsterGlyph(size: 15)
                Text("Dumpster")
            }
            .help("A window to drag apps into from Finder")
        }
    }

    private func chip<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: 6) { content() }
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(Capsule().fill(Color.panelTrack))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Unused apps (on)

    @ViewBuilder private var unusedApps: some View {
        if !controller.hasScanned {
            // Placeholders until the first scan finishes; then everything
            // arrives together.
            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 4) {
                        SkeletonBone(width: 30, height: 30, radius: 7)
                        SkeletonBone(width: 40, height: 8)
                        SkeletonBone(width: 30, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .transition(.opacity)
        } else if controller.unusedApps.isEmpty {
            Text("No apps unused for \(controller.unusedThreshold.title).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 50)
        } else {
            let unused = Array(controller.unusedApps.prefix(4))
            HStack(spacing: 0) {
                ForEach(unused) { app in
                    Button { controller.review([app]) } label: {
                        VStack(spacing: 2) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 30, height: 30)
                            Text(app.bytes.map(CleanupFormat.bytes) ?? "")
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
            // Earlier results stay, dimmed, while a new scan runs.
            .opacity(controller.isScanning ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.2), value: controller.isScanning)
            .transition(.opacity)
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

/// The Uninstaller's settings: what counts as unused,
/// noticing deletions, and the Never Uninstall list.
struct UninstallerSettings: View {
    @Bindable var controller: UninstallerController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show Unused Apps on the Tile", isOn: $controller.showsUnusedOnTile)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))
            // Both captions take the same room, so switching doesn't resize
            // the page.
            ZStack(alignment: .topLeading) {
                caption("The tile shows your largest apps not opened in:")
                    .opacity(controller.showsUnusedOnTile ? 1 : 0)
                caption("Apps not opened in this long are listed first when you search or open the Uninstaller:")
                    .opacity(controller.showsUnusedOnTile ? 0 : 1)
            }
            .animation(.snappy(duration: 0.2), value: controller.showsUnusedOnTile)
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

/// A gray placeholder shape, shown where content will be once it's loaded.
struct SkeletonBone: View {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat = 3

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.primary.opacity(0.09))
            .frame(width: width, height: height)
    }
}
