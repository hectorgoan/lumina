import SwiftUI

extension Utility {
    static let quitAll = Utility(
        id: "quitAll",
        name: "Quit All",
        symbol: "command",
        size: .quarter,
        content: { AnyView(QuitAllModule(controller: .shared)) },
        settings: { AnyView(QuitAllSettings(controller: .shared)) }
    )
}

/// Quits every open app except the ones kept open. Icon-only, like Control
/// Center's small modules.
struct QuitAllModule: View {
    let controller: QuitAllController

    var body: some View {
        ModuleToggleButton(
            glyph: controller.showsConfirmation ? .symbol("checkmark") : .text("⌘Q"),
            tint: .red,
            isOn: controller.showsConfirmation,
            action: controller.quitApps
        )
        // A quick squash and bounce each time it quits.
        .keyframeAnimator(initialValue: 1.0, trigger: controller.quitCount) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(0.85, duration: 0.08)
                SpringKeyframe(1.12, duration: 0.16)
                SpringKeyframe(1.0, duration: 0.3)
            }
        }
        .frame(maxWidth: .infinity)
        .help("Quit all apps except the ones you keep open")
        .accessibilityLabel("Quit All Apps")
    }
}

/// Chooses the apps Quit All leaves open.
struct QuitAllSettings: View {
    let controller: QuitAllController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep Open")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if controller.keptApps.isEmpty {
                Text("Quit All closes every open app. Add apps here to keep them open.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(controller.keptApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                withAnimation(.snappy) { controller.stopKeeping(app.bundleID) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Stop keeping \(app.name) open")
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Menu("Add App") {
                    let running = controller.addableRunningApps
                    if !running.isEmpty {
                        Section("Open Apps") {
                            ForEach(running) { app in
                                Button {
                                    withAnimation(.snappy) { controller.keep(app.bundleID) }
                                } label: {
                                    Label { Text(app.name) } icon: { Image(nsImage: menuIcon(app.icon)) }
                                }
                            }
                        }
                    }
                    Button("Choose…", action: controller.chooseAppToKeep)
                }
                .fixedSize()

                Spacer()

                Text("Finder and Lumina are never quit.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.snappy, value: controller.keptBundleIDs)
    }

    private func menuIcon(_ icon: NSImage) -> NSImage {
        let image = icon.copy() as! NSImage
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
