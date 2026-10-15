import AppKit
import Observation

/// Shows each world clock the user put in the menu bar as its own menu bar
/// item: the flag, the city code as an outlined tag if chosen, and the time.
@MainActor
final class WorldClockMenuBar: NSObject {
    private let store: UtilityStore
    private var items: [String: NSStatusItem] = [:]
    private var ticker: Task<Void, Never>?

    init(store: UtilityStore) {
        self.store = store
        super.init()
        observeClocks()
        startTicking()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: .NSSystemTimeZoneDidChange, object: nil
        )
    }

    /// Re-syncs the menu bar whenever the clocks or their settings change.
    private func observeClocks() {
        withObservationTracking {
            sync(with: store.worldClocks)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeClocks() }
        }
    }

    private func sync(with clocks: [WorldClock]) {
        let shown = clocks.filter { $0.menuBar != .off }
        let shownIDs = Set(shown.map(\.id))

        for (id, item) in items where !shownIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
        }
        for clock in shown where items[clock.id] == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            // Lets macOS remember where the user ⌘-drags it.
            item.autosaveName = "Lumina.\(clock.id)"
            items[clock.id] = item
        }
        refresh()
    }

    @objc private func refresh() {
        let now = Date()
        for clock in store.worldClocks where clock.menuBar != .off {
            guard let item = items[clock.id], let city = WorldClockCity.city(withCode: clock.cityCode) else { continue }
            let moment = WorldClockMoment(city: city, date: now)
            item.button?.attributedTitle = Self.title(city: city, moment: moment, showsCode: clock.menuBar == .codeAndTime)
            item.button?.setAccessibilityLabel("\(city.name), \(moment.time) \(moment.period ?? "")")
            item.menu = menu(for: clock, city: city, moment: moment)
        }
    }

    /// Updates the times on each new minute.
    private func startTicking() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(seconds + 0.05))
                self?.refresh()
            }
        }
    }

    static func title(city: WorldClockCity, moment: WorldClockMoment, showsCode: Bool) -> NSAttributedString {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let text = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        let title = NSMutableAttributedString(
            string: "\(city.flag) ",
            attributes: [.font: NSFont.systemFont(ofSize: size - 2), .baselineOffset: 1]
        )
        if showsCode {
            title.append(codeTag(city.code, alignedWith: text))
            title.append(NSAttributedString(string: " ", attributes: [.font: text]))
        }
        let time = [moment.time, moment.period].compactMap { $0 }.joined(separator: " ")
        title.append(NSAttributedString(string: time, attributes: [.font: text, .foregroundColor: NSColor.labelColor]))
        return title
    }

    /// The city code in a hairline rounded frame, like a luggage tag.
    ///
    /// It's drawn when the menu bar draws, in the menu bar's own text color,
    /// so it stays legible over light, dark and colorful backgrounds.
    private static func codeTag(_ code: String, alignedWith font: NSFont) -> NSAttributedString {
        let tagFont = NSFont.systemFont(ofSize: font.pointSize - 4, weight: .semibold)
        let label = NSAttributedString(string: code, attributes: [.font: tagFont, .kern: 0.3])
        let labelSize = label.size()
        let padding = NSSize(width: 3, height: 1)
        let size = NSSize(width: ceil(labelSize.width + padding.width * 2), height: ceil(labelSize.height + padding.height * 2))

        let image = NSImage(size: size, flipped: false) { rect in
            let color = NSColor.labelColor
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4), xRadius: 3, yRadius: 3)
            frame.lineWidth = 0.8
            color.setStroke()
            frame.stroke()
            NSAttributedString(string: code, attributes: [.font: tagFont, .kern: 0.3, .foregroundColor: color])
                .draw(at: NSPoint(x: padding.width, y: padding.height))
            return true
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        // Center the tag on the time's capital letters.
        attachment.bounds = CGRect(
            x: 0,
            y: ((font.capHeight - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        return NSAttributedString(attachment: attachment)
    }

    private func menu(for clock: WorldClock, city: WorldClockCity, moment: WorldClockMoment) -> NSMenu {
        let menu = NSMenu()
        let header = NSMenuItem(title: "\(city.flag) \(city.name)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let detail = NSMenuItem(title: moment.relativeDescription, action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide from Menu Bar", action: #selector(hide(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = clock.id
        menu.addItem(hide)
        return menu
    }

    @objc private func hide(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.setMenuBarDisplay(.off, forClockWithID: id)
    }
}
