import SwiftUI

extension Utility {
    static let cleanup = Utility(
        id: "cleanup",
        name: "Cleanup",
        symbol: "sparkles",
        size: .full,
        content: { AnyView(CleanupModule(controller: .shared)) },
        settings: { AnyView(CleanupSettings(controller: .shared)) }
    )
}

extension Color {
    static let cleanupViolet = Color(red: 0.55, green: 0.40, blue: 1.0)
}

extension CleanupCategory {
    var color: Color {
        switch self {
        case .caches: .blue
        case .developer: .purple
        case .trash: .red
        case .logs: .gray
        case .downloads: .orange
        case .mail: .teal
        }
    }
}

/// Shows how much junk there is, split by kind, and cleans it.
struct CleanupModule: View {
    let controller: CleanupController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            bar
            footer
                // The same height in every phase, so the panel never resizes.
                .frame(height: 30, alignment: .topLeading)
        }
        .animation(.snappy(duration: 0.25), value: controller.phase)
        .animation(.snappy(duration: 0.2), value: controller.awaitsConfirmation)
        .onAppear { controller.refreshIfStale() }
        // The panel's window stays alive between openings; rescan when it
        // comes back if the last scan is old.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            controller.refreshIfStale()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark" : "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: 30, height: 30)
                .background(Circle().fill(isActive ? AnyShapeStyle(iconTint) : AnyShapeStyle(Color.panelTrack)))
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 1) {
                Text("Cleanup")
                    .font(.system(size: 13, weight: .semibold))
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            button
        }
    }

    @ViewBuilder private var button: some View {
        switch controller.phase {
        case .idle:
            Button("Scan") { controller.scan() }
                .buttonStyle(.glassProminent)
                .tint(.cleanupViolet)
                .controlSize(.small)
                .help("Look for junk")
        case .ready where controller.cleanableBytes > 0:
            refreshButton
            Button(action: controller.cleanTapped) {
                Text(controller.awaitsConfirmation ? "Clean \(CleanupFormat.bytes(controller.cleanableBytes))?" : "Clean")
                    .contentTransition(.interpolate)
            }
            .buttonStyle(.glassProminent)
            .tint(controller.awaitsConfirmation ? .red : .cleanupViolet)
            .controlSize(.small)
            .help(controller.awaitsConfirmation ? "Click again to remove the junk" : "Remove the junk shown below")
        case .cleaning:
            Button("Stop", action: controller.stop)
                .buttonStyle(.glass)
                .controlSize(.small)
        case .scanning, .ready, .done:
            refreshButton
        }
    }

    /// Scans again, with one quick turn of the arrow.
    private var refreshButton: some View {
        RefreshButton(isWorking: controller.phase == .scanning) { controller.scan() }
    }

    private var status: String {
        switch controller.phase {
        case .idle:
            return "Not scanned yet"
        case .scanning:
            return "Scanning…"
        case .ready:
            let bytes = controller.cleanableBytes
            return bytes > 0 ? "\(CleanupFormat.bytes(bytes)) to clean" : "Nothing to clean"
        case .cleaning(let progress, _):
            return "Cleaning… \(Int((progress * 100).rounded()))%"
        case .done:
            return "All clean"
        }
    }

    private var isDone: Bool {
        if case .done = controller.phase { return true }
        return false
    }

    /// Whether the icon is filled in: there's something to clean, it's
    /// cleaning, or it's done.
    private var isActive: Bool {
        switch controller.phase {
        case .idle, .scanning: false
        case .ready: controller.cleanableBytes > 0
        case .cleaning, .done: true
        }
    }

    private var iconTint: Color {
        isDone ? .luminaGreen : .cleanupViolet
    }

    // MARK: - Bar

    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.panelTrack)
                switch controller.phase {
                case .ready, .cleaning:
                    segments(width: proxy.size.width)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: proxy.size.width * progressShown)
                        }
                case .done:
                    Capsule().fill(Color.luminaGreen)
                case .idle, .scanning:
                    EmptyView()
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }

    /// While cleaning, the bar empties from the left as junk goes.
    private var progressShown: Double {
        if case .cleaning(let progress, _) = controller.phase { return 1 - progress }
        return 1
    }

    private func segments(width: CGFloat) -> some View {
        let parts = controller.cleanable
        let total = Double(max(controller.cleanableBytes, 1))
        let gaps = CGFloat(max(parts.count - 1, 0)) * 2
        return HStack(spacing: 2) {
            ForEach(parts, id: \.category) { part in
                Rectangle()
                    .fill(part.category.color)
                    .frame(width: max(3, (width - gaps) * Double(part.bytes) / total))
            }
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        switch controller.phase {
        case .idle:
            caption("Scan to see how much space you can free.")
        case .scanning:
            caption("Looking for junk…")
        case .ready:
            if controller.cleanable.isEmpty {
                caption("There’s no junk in the places Cleanup looks.")
            } else {
                legend
            }
        case .cleaning(_, let category):
            caption("Removing \(category.name)…")
        case .done(let freed):
            let available = controller.availableCapacity.map { " · \(CleanupFormat.bytes($0)) available" } ?? ""
            caption("Freed \(CleanupFormat.bytes(freed))\(available)")
        }
    }

    /// Up to four entries, so it fits two rows: the biggest kinds, then
    /// the rest together.
    private var legend: some View {
        let parts = controller.cleanable
        let entries: [(name: String, color: Color, bytes: Int64)] = parts.count <= 4
            ? parts.map { ($0.category.shortName, $0.category.color, $0.bytes) }
            : parts.prefix(3).map { ($0.category.shortName, $0.category.color, $0.bytes) }
                + [("Other", Color.secondary, parts.dropFirst(3).reduce(0) { $0 + $1.bytes })]

        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())],
            alignment: .leading,
            spacing: 4
        ) {
            ForEach(entries, id: \.name) { entry in
                HStack(spacing: 5) {
                    Circle().fill(entry.color).frame(width: 6, height: 6)
                    Text(entry.name).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(CleanupFormat.bytes(entry.bytes)).monospacedDigit()
                }
                .font(.system(size: 10))
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }
}

/// Cleanup's settings: what it cleans, and how carefully.
struct CleanupSettings: View {
    @Bindable var controller: CleanupController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clean")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(CleanupCategory.allCases, id: \.self, content: row)
            }

            Divider()

            Toggle("Scan Automatically", isOn: $controller.scansAutomatically)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))

            FullWidthSegmentedPicker(
                options: CleanupController.ScanInterval.allCases.map { ($0.title, $0) },
                selection: $controller.scanInterval
            )
            .disabled(!controller.scansAutomatically)
            .accessibilityLabel("Scan Interval")

            // Both captions take the same room, so switching doesn't
            // resize the page.
            ZStack(alignment: .topLeading) {
                intervalCaption("When you open the panel, Cleanup scans again if its last scan is older than this.")
                    .opacity(controller.scansAutomatically ? 1 : 0)
                intervalCaption("Cleanup scans only when you click Scan or ↻ on its tile.")
                    .opacity(controller.scansAutomatically ? 0 : 1)
            }
            .animation(.snappy(duration: 0.2), value: controller.scansAutomatically)

            Divider()

            Toggle("Skip Apps That Are Open", isOn: $controller.skipsOpenApps)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 13))

            Text("Their caches come back as soon as you use them, and removing them while an app runs can upset it.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            accessRow
        }
    }

    private func intervalCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ category: CleanupCategory) -> some View {
        let isOn = controller.enabledCategories.contains(category)
        let finding = controller.findings[category]

        return Button {
            controller.enabledCategories.formSymmetricDifference([category])
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: category.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(category.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.name)
                        .font(.system(size: 12))
                    note(for: category, finding: finding)
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(size(for: category, isOn: isOn, finding: finding))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private func note(for category: CleanupCategory, finding: CleanupFinding?) -> some View {
        if finding?.isBlocked == true || (category.needsFullDiskAccess && !controller.hasFullDiskAccess) {
            Text("Needs Full Disk Access").foregroundStyle(.orange)
        } else if finding?.isInUse == true {
            Text("Skipped while its app is open").foregroundStyle(.secondary)
        } else {
            Text(category.detail).foregroundStyle(.secondary)
        }
    }

    private func size(for category: CleanupCategory, isOn: Bool, finding: CleanupFinding?) -> String {
        guard isOn else { return "" }
        if controller.phase == .scanning { return "…" }
        guard let finding, !finding.isBlocked, !finding.isInUse else { return "—" }
        return finding.bytes > 0 ? CleanupFormat.bytes(finding.bytes) : "None"
    }

    private var accessRow: some View {
        HStack(spacing: 8) {
            Image(systemName: controller.hasFullDiskAccess ? "checkmark.shield.fill" : "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(controller.hasFullDiskAccess ? Color.luminaGreen : .orange)
            Text(controller.hasFullDiskAccess ? "Full Disk Access is on." : "Trash and Mail need Full Disk Access.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if !controller.hasFullDiskAccess {
                Button("Open Settings", action: controller.openFullDiskAccessSettings)
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
            }
        }
    }
}
