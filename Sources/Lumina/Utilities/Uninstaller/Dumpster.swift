import AppKit
import SwiftUI

/// The Dumpster: a small window that floats above Finder, to toss apps into
/// by dragging. The panel can't take drops itself, since it closes as soon
/// as Finder is clicked.
@MainActor
final class DumpsterWindowController: NSObject, NSWindowDelegate {
    static let shared = DumpsterWindowController()

    private var window: NSPanel?
    private let model = DumpsterModel()

    func show() {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Dumpster"
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: DumpsterView(model: model, close: { [weak self] in self?.close() }))
            panel.center()
            window = panel
        }
        // The Dumpster takes over from the panel: you drag from Finder next.
        MenuBarPanel.close()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

/// The apps in the Dumpster.
@MainActor
@Observable
final class DumpsterModel {
    var apps: [InstalledApp] = []
    var isTargeted = false
    /// A short note after a drop, such as why an app was refused.
    var note: String?

    var bytes: Int64 { apps.reduce(0) { $0 + ($1.bytes ?? 0) } }

    func add(_ urls: [URL]) -> Bool {
        let candidates = urls.filter { $0.pathExtension == "app" }.compactMap { AppCatalog.app(at: $0) }
        let refused = candidates.filter { AppCatalog.isProtected(bundleID: $0.bundleID) }
        var added = candidates.filter { candidate in
            !AppCatalog.isProtected(bundleID: candidate.bundleID) && !apps.contains { $0.bundleID == candidate.bundleID }
        }
        note = refused.isEmpty ? nil : "\(refused.map(\.name).joined(separator: ", ")) can’t be uninstalled."
        guard !added.isEmpty else { return !refused.isEmpty }

        for index in added.indices where added[index].bytes == nil {
            added[index].bytes = UninstallerController.shared.apps.first { $0.bundleID == added[index].bundleID }?.bytes
        }
        withAnimation(.snappy) { apps += added }
        // Sizes for apps the Uninstaller hasn't measured.
        for app in added where app.bytes == nil {
            let url = app.url
            Task {
                let bytes = await Task.detached(priority: .utility) { CleanupScanner.size(of: url) }.value
                if let index = apps.firstIndex(where: { $0.id == app.id }) { apps[index].bytes = bytes }
            }
        }
        return true
    }
}

struct DumpsterView: View {
    @Bindable var model: DumpsterModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(model.isTargeted ? Color.green.opacity(0.14) : Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        model.isTargeted ? Color.green.opacity(0.8) : Color.primary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 2, dash: model.apps.isEmpty || model.isTargeted ? [7, 5] : [])
                    )

                VStack(spacing: 12) {
                    ZStack(alignment: .top) {
                        DumpsterGlyph(size: 120, lidOpen: model.isTargeted || !model.apps.isEmpty ? 1 : 0)
                        if !model.apps.isEmpty {
                            // The newest apps peek out of the bin.
                            HStack(spacing: -10) {
                                ForEach(Array(model.apps.suffix(3).enumerated()), id: \.element.id) { index, app in
                                    Image(nsImage: app.icon)
                                        .resizable()
                                        .frame(width: 34, height: 34)
                                        .rotationEffect(.degrees([-18.0, 6, 20][index]))
                                        .offset(y: index == 1 ? -6 : 0)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .offset(y: 4)
                        }
                    }
                    .frame(height: 120, alignment: .bottom)

                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 12)
            }
            .padding([.horizontal, .top], 14)
            .dropDestination(for: URL.self) { urls, _ in
                model.add(urls)
            } isTargeted: { targeted in
                withAnimation(.snappy(duration: 0.25)) { model.isTargeted = targeted }
            }

            HStack(spacing: 8) {
                if model.apps.isEmpty {
                    Text("Stays on top while you drag from Finder.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Empty Out") {
                        withAnimation(.snappy) { model.apps = [] }
                    }
                    .help("Take the apps back out; nothing is removed")
                    Spacer()
                    Button("Review & Uninstall…") {
                        let opened = UninstallerController.shared.reviewFromOutside(model.apps)
                        model.apps = []
                        if opened {
                            close()
                        } else {
                            // Opening the panel takes the Accessibility
                            // permission; the review waits in the panel.
                            model.note = "Click Lumina in the menu bar to review them. To have it open on its own, allow Lumina in Privacy & Security › Accessibility."
                            MenuBarPanel.requestPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(14)
            .frame(height: 60)
        }
        .frame(width: 300, height: 360)
    }

    private var title: String {
        if model.isTargeted { return "Let Go to Toss It" }
        switch model.apps.count {
        case 0: return "Drag Apps Here"
        case 1: return "1 App in the Dumpster"
        default: return "\(model.apps.count) Apps in the Dumpster"
        }
    }

    private var subtitle: String {
        if let note = model.note { return note }
        if model.isTargeted { return "You’ll review everything before it goes." }
        guard !model.apps.isEmpty else {
            return "Drop as many as you like, then review what goes before anything is removed."
        }
        let names = ListFormatter.localizedString(byJoining: model.apps.map(\.name))
        return model.bytes > 0 ? "\(names) · \(CleanupFormat.bytes(model.bytes))" : names
    }
}

/// A little dumpster: a green bin with a lid and wheels.
struct DumpsterGlyph: View {
    var size: CGFloat = 60
    /// From 0 (closed) to 1 (open).
    var lidOpen: Double = 0

    var body: some View {
        let s = size / 60
        ZStack(alignment: .bottom) {
            HStack(spacing: 26 * s) {
                Circle().fill(Color(white: 0.15)).frame(width: 9 * s, height: 9 * s)
                Circle().fill(Color(white: 0.15)).frame(width: 9 * s, height: 9 * s)
            }
            DumpsterBody()
                .fill(LinearGradient(
                    colors: [Color(red: 0.28, green: 0.72, blue: 0.42), Color(red: 0.16, green: 0.52, blue: 0.30)],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 52 * s, height: 34 * s)
                .overlay {
                    VStack(spacing: 4 * s) {
                        ForEach(0..<2, id: \.self) { _ in
                            Capsule().fill(Color.black.opacity(0.18)).frame(width: 30 * s, height: 2.5 * s)
                        }
                    }
                }
                .padding(.bottom, 5 * s)
            // The lid, hinged at the back.
            RoundedRectangle(cornerRadius: 3 * s)
                .fill(Color(red: 0.12, green: 0.40, blue: 0.24))
                .frame(width: 56 * s, height: 7 * s)
                .rotationEffect(.degrees(lidOpen * 38), anchor: .trailing)
                .offset(y: -38 * s)
        }
        .frame(width: size, height: size * 0.9, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct DumpsterBody: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.08
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
