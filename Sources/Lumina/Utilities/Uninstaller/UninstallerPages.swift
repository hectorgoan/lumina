import SwiftUI

/// The Uninstaller's pages, in place of the grid: pick an app, review what
/// goes, done.
struct UninstallerPageView: View {
    let page: UninstallerPage
    let controller: UninstallerController

    var body: some View {
        switch page {
        case .list: UninstallerListPage(controller: controller)
        case .review: UninstallReviewPage(controller: controller)
        case .done: UninstallDonePage(controller: controller)
        }
    }
}

/// A page's title with a back button, like the other pages.
private struct PageHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Back")
            .keyboardShortcut(.cancelAction)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Spacer()
        }
    }
}

// MARK: - Pick an app

struct UninstallerListPage: View {
    @Bindable var controller: UninstallerController
    @StateObject private var state = ListState()
    @FocusState private var isSearchFocused: Bool

    /// The list scrolls inside a fixed height, so searching never resizes
    /// the panel.
    private static let listHeight: CGFloat = 330

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: "Uninstall an App", back: controller.backToGrid)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search \(controller.apps.count) apps", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.panelTrack, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            FullWidthSegmentedPicker(
                options: UninstallerController.ListTab.allCases.map { ($0.title, $0) },
                selection: $controller.listTab
            )
            .accessibilityLabel("Show")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !controller.hasScanned {
                        skeleton
                    } else if controller.listTab == .leftBehind {
                        let groups = controller.leftBehind.filter { state.query.isEmpty || matches($0.name) || matches($0.bundleID) }
                        section("Files from apps you deleted")
                        if groups.isEmpty {
                            Text(state.query.isEmpty ? "Nothing left behind." : "No Matches")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60)
                        }
                        ForEach(groups) { leftBehindRow($0) }
                    } else if state.query.isEmpty {
                        let unused = sorted(controller.unusedApps)
                        if !unused.isEmpty {
                            section("Not opened in \(controller.unusedThreshold.title)")
                            ForEach(unused) { appRow($0) }
                        }
                        let unusedIDs = Set(unused.map(\.id))
                        section("All Apps")
                        ForEach(sorted(controller.apps.filter { !unusedIDs.contains($0.id) })) { appRow($0) }
                    } else {
                        let apps = sorted(controller.apps.filter { matches($0.name) })
                        if apps.isEmpty {
                            Text("No Apps Found")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 60)
                        }
                        ForEach(apps) { appRow($0) }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.never)
            // Earlier results stay, dimmed, while a new scan runs.
            .opacity(controller.isScanning && controller.hasScanned ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.2), value: controller.isScanning)
            .frame(height: Self.listHeight)
            .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onAppear {
            isSearchFocused = true
            controller.refreshIfStale()
        }
    }

    private func matches(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains(state.query.trimmingCharacters(in: .whitespaces))
    }

    private func sorted(_ apps: [InstalledApp]) -> [InstalledApp] {
        switch controller.listTab {
        case .size: apps.sorted { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        case .name: apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .lastOpened, .leftBehind: apps.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    /// Placeholder rows until the first scan finishes.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBone(width: 120, height: 8)
                .padding(.leading, 6)
                .padding(.top, 6)
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 9) {
                    SkeletonBone(width: 26, height: 26, radius: 6)
                    VStack(alignment: .leading, spacing: 5) {
                        SkeletonBone(width: [110, 80, 130, 95, 70, 120][index], height: 9)
                        SkeletonBone(width: [80, 100, 70, 90, 110, 60][index], height: 7)
                    }
                    Spacer()
                    SkeletonBone(width: 40, height: 8)
                }
                .padding(.horizontal, 6)
            }
        }
        .transition(.opacity)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let isProtected = controller.isProtected(bundleID: app.bundleID)
        return Button { controller.review([app]) } label: {
            HStack(spacing: 9) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(isProtected ? "On your Never Uninstall list" : UninstallerFormat.lastOpened(app.lastUsed))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(app.bytes.map(CleanupFormat.bytes) ?? "…")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .opacity(isProtected ? 0.5 : 1)
    }

    private func leftBehindRow(_ group: LeftBehindApp) -> some View {
        Button { controller.review(leftBehind: group) } label: {
            HStack(spacing: 9) {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(group.bundleID)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(CleanupFormat.bytes(group.bytes))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

@MainActor
private final class ListState: ObservableObject {
    @Published var query = ""
}

/// A row that highlights while pressed or hovered, like a menu.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: Configuration
        @StateObject private var hover = HoverState()

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hover.isHovered ? 0.07 : 0))
                )
                .onHover { hover.isHovered = $0 }
        }
    }
}

@MainActor
private final class HoverState: ObservableObject {
    @Published var isHovered = false
}

// MARK: - Review

struct UninstallReviewPage: View {
    @Bindable var controller: UninstallerController
    @StateObject private var expansion = Expansion()

    /// What was found scrolls inside a fixed height, so loading and
    /// expanding never resize the panel.
    private static let listHeight: CGFloat = 230

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: controller.plan?.title ?? "", back: { controller.openList() })

            if let plan = controller.plan {
                if plan.entries.count == 1 {
                    appHeader(plan.entries[0])
                }

                ScrollView {
                    VStack(spacing: 0) {
                        if plan.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, minHeight: 80)
                            Text("Looking for its files…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else if plan.entries.count == 1 {
                            ForEach(plan.entries[0].kinds, id: \.self) { kind in
                                kindRow(kind, entryIndex: 0)
                            }
                        } else {
                            ForEach(plan.entries.indices, id: \.self) { index in
                                entryRow(index)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .frame(height: plan.entries.count == 1 ? Self.listHeight : Self.listHeight + 76)
                .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Text(summary(plan))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: controller.moveToTrash) {
                        if controller.isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Move to Trash")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .disabled(plan.isLoading || plan.selectedItems.isEmpty || controller.isWorking)
                }

                Text(note(plan))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func appHeader(_ entry: UninstallEntry) -> some View {
        HStack(spacing: 12) {
            if let app = entry.app {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 48, height: 48)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                if let app = entry.app {
                    let details = [app.version.map { "Version \($0)" }, app.vendor].compactMap { $0 }
                    if !details.isEmpty {
                        Text(details.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(UninstallerFormat.lastOpened(app.lastUsed))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text("App not installed · \(entry.bundleID)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// A kind of file, with a checkbox; opens to list each file.
    private func kindRow(_ kind: LeftoverKind, entryIndex: Int) -> some View {
        let entry = controller.plan!.entries[entryIndex]
        let items = entry.items(of: kind)
        let isOn = !entry.excludedKinds.contains(kind)
        let isExpanded = expansion.kinds.contains(kind)
        let bytes = items.reduce(0) { $0 + $1.bytes }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Button {
                    controller.plan?.entries[entryIndex].excludedKinds.formSymmetricDifference([kind])
                } label: {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .disabled(entry.isProtected)

                Button {
                    withAnimation(.snappy(duration: 0.2)) { expansion.kinds.formSymmetricDifference([kind]) }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(kind == .app ? entry.app?.url.lastPathComponent ?? kind.title : kind.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(CleanupFormat.bytes(bytes))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 5)

            if isExpanded {
                ForEach(items) { item in
                    Text(item.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 48)
                        .padding(.bottom, 4)
                        .help(item.url.path)
                }
            }
        }
        .opacity(isOn ? 1 : 0.5)
    }

    /// An app in a review of several, with a checkbox.
    private func entryRow(_ index: Int) -> some View {
        let entry = controller.plan!.entries[index]
        let bytes = entry.items.reduce(0) { $0 + $1.bytes }
        let isOn = entry.isIncluded && !entry.isProtected

        return HStack(spacing: 9) {
            Button {
                controller.plan?.entries[index].isIncluded.toggle()
            } label: {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .disabled(entry.isProtected)

            if let app = entry.app {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(entry.isProtected ? "On your Never Uninstall list" : "\(entry.items.count) items")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(CleanupFormat.bytes(bytes))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .opacity(isOn ? 1 : 0.5)
    }

    private func summary(_ plan: UninstallPlan) -> String {
        guard !plan.isLoading else { return "" }
        let count = plan.selectedItems.count
        return "\(CleanupFormat.bytes(plan.selectedBytes)) in \(count) \(count == 1 ? "item" : "items")"
    }

    private func note(_ plan: UninstallPlan) -> String {
        if plan.entries.count == 1, plan.entries[0].isProtected {
            return "\(plan.entries[0].name) is on your Never Uninstall list. Remove it from the list in the Uninstaller’s settings to uninstall it."
        }
        let running = plan.entries.filter { $0.isIncluded && !($0.app?.runningInstances.isEmpty ?? true) }.map(\.name)
        let quitting = running.isEmpty ? "" : "\(ListFormatter.localizedString(byJoining: running)) \(running.count == 1 ? "is" : "are") open and will be quit first. "
        return quitting + "Everything goes to the Trash, so you can put it back."
    }
}

@MainActor
private final class Expansion: ObservableObject {
    @Published var kinds: Set<LeftoverKind> = []
}

// MARK: - Done

struct UninstallDonePage: View {
    let controller: UninstallerController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Uninstaller", back: { controller.openList() })

            if let result = controller.result {
                VStack(spacing: 10) {
                    Image(systemName: result.isPutBack ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white, result.isPutBack ? Color.accentColor : .green)
                        .contentTransition(.symbolEffect(.replace))

                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)

                    Text(detail(result))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if result.putBackFailed {
                            Button("Open Trash", action: controller.openTrash)
                                .buttonStyle(.glass)
                        } else if !result.isPutBack && !result.moved.isEmpty {
                            Button("Put Back", action: controller.putBack)
                                .buttonStyle(.glass)
                        }
                        Button("Done", action: controller.backToGrid)
                            .buttonStyle(.glassProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 12)
                .background(Color.panelSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .animation(.snappy(duration: 0.25), value: result.isPutBack)
            }
        }
    }

    private func detail(_ result: UninstallResult) -> String {
        if result.isPutBack { return "Everything is back where it was." }
        if result.putBackFailed {
            return "Some items couldn’t be put back. Open the Trash and use Put Back there."
        }
        var text = "\(CleanupFormat.bytes(result.bytes)) in \(result.moved.count) items. Empty the Trash to free the space."
        if !result.failures.isEmpty {
            text += " Couldn’t move: \(ListFormatter.localizedString(byJoining: result.failures))."
        }
        return text
    }
}
