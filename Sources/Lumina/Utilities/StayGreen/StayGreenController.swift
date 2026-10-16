import Foundation
import IOKit.pwr_mgt
import Observation

/// How Lumina's menu bar icon shows that Stay Green is on.
struct StayGreenIndicator: Equatable {
    enum Shape: String, CaseIterable {
        /// The icon doesn't change.
        case none
        /// A dot in place of the bottom-right ray.
        case dot
        /// A ring between the rays and the center.
        case halo
        /// The rays themselves; only shows in green.
        case rays

        var title: String {
            switch self {
            case .none: "None"
            case .dot: "Dot"
            case .halo: "Halo"
            case .rays: "Rays"
            }
        }
    }

    var shape: Shape = .halo
    var prefersGreen = true

    /// Whether it's drawn in green. Rays always are: in the icon's own
    /// color they'd look the same as when Stay Green is off.
    var isGreen: Bool { shape == .rays || (prefersGreen && shape != .none) }

    /// For example "Green Halo".
    var title: String {
        isGreen ? "Green \(shape.title)" : shape.title
    }

    /// For example "A green ring around the center".
    var summary: String {
        let color = isGreen ? "green " : ""
        switch shape {
        case .none: return "The icon doesn’t change"
        case .dot: return "A \(color)dot in place of a ray"
        case .halo: return "A \(color)ring around the center"
        case .rays: return "The rays turn green"
        }
    }
}

/// Keeps chat apps such as Microsoft Teams showing you as available.
///
/// Rather than nudging the cursor, this periodically tells the system the
/// user is active, which resets the idle timers those apps read. It needs no
/// Accessibility permission and never moves the pointer. Like any real
/// activity, it also keeps the display from sleeping while on.
@MainActor
@Observable
final class StayGreenController {
    static let shared = StayGreenController()

    /// Well below the shortest idle threshold of common chat apps (Teams: 5 min).
    private static let interval: Duration = .seconds(30)

    private(set) var isActive = false

    /// How the menu bar icon shows Stay Green is on.
    var indicator: StayGreenIndicator {
        didSet {
            defaults.set(indicator.shape.rawValue, forKey: Self.shapeKey)
            defaults.set(indicator.prefersGreen, forKey: Self.greenKey)
        }
    }

    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let shapeKey = "stayGreen.indicatorShape"
    private static let greenKey = "stayGreen.indicatorIsGreen"

    private init() {
        let defaults = UserDefaults.standard
        var indicator = StayGreenIndicator()
        if let shape = defaults.string(forKey: Self.shapeKey).flatMap(StayGreenIndicator.Shape.init) {
            indicator.shape = shape
        }
        if defaults.object(forKey: Self.greenKey) != nil {
            indicator.prefersGreen = defaults.bool(forKey: Self.greenKey)
        }
        self.indicator = indicator
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    private func activate() {
        isActive = true
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.declareActivity()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func deactivate() {
        heartbeat?.cancel()
        heartbeat = nil
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        isActive = false
    }

    private func declareActivity() {
        // Reusing the same ID refreshes the existing assertion.
        IOPMAssertionDeclareUserActivity(
            "Lumina Stay Green is keeping you available" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
    }
}
