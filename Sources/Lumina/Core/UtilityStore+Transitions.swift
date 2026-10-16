import SwiftUI

/// Animated changes to the panel.
///
/// The menu bar window resizes to fit its content, and animating that size
/// while content is visible makes its glass flicker. So every change that
/// resizes the panel follows the same three steps: what's leaving fades
/// out, the panel resizes while that space is empty, and what's arriving
/// fades in.
extension UtilityStore {
    // MARK: - Pages

    /// Swaps what the panel's main column shows, such as opening a utility's
    /// settings or an add page, or going back.
    func swapPage(_ change: @escaping () -> Void) {
        swapPage { change(); return nil }
    }

    /// Swaps pages and returns the ID of a utility the change added, which
    /// fades in along with the grid, like a new world clock.
    func swapPage(adding change: @escaping () -> String?) {
        guard !isTransitioning else { _ = change(); return }
        isTransitioning = true

        withAnimation(Motion.dismiss, completionCriteria: .removed) {
            isPageVisible = false
        } completion: {
            var added: String?
            withAnimation(Motion.resize, completionCriteria: .removed) {
                added = change()
                if let added { self.fadingUtilityIDs.insert(added) }
            } completion: {
                withAnimation(Motion.present) {
                    self.isPageVisible = true
                    if let added { self.fadingUtilityIDs.remove(added) }
                }
                self.isTransitioning = false
            }
        }
    }

    // MARK: - Tiles

    /// Hides a visible utility: it fades out, then the grid closes the gap.
    func hideTile(_ utility: Utility) {
        guard !isHidden(utility) else { return }
        fadeTileOut(utility.id) { self.toggleVisibility(of: utility) }
    }

    /// Removes a utility the user added: it fades out, then the grid closes
    /// the gap.
    func removeTile(_ utility: Utility) {
        fadeTileOut(utility.id) { self.remove(utility) }
    }

    /// Brings a hidden utility back: the grid makes room, then it fades in.
    func showTile(_ utility: Utility) {
        fadeTileIn {
            self.show(utility)
            return utility.id
        }
    }

    private func fadeTileOut(_ id: String, then change: @escaping () -> Void) {
        guard !isTransitioning else { change(); return }
        isTransitioning = true

        withAnimation(Motion.dismiss, completionCriteria: .removed) {
            _ = fadingUtilityIDs.insert(id)
        } completion: {
            withAnimation(Motion.resize, completionCriteria: .removed) {
                change()
            } completion: {
                self.fadingUtilityIDs.remove(id)
                self.isTransitioning = false
            }
        }
    }

    private func fadeTileIn(_ change: @escaping () -> String) {
        guard !isTransitioning else { _ = change(); return }
        isTransitioning = true

        var added = ""
        withAnimation(Motion.resize, completionCriteria: .removed) {
            added = change()
            fadingUtilityIDs.insert(added)
        } completion: {
            withAnimation(Motion.present) { _ = self.fadingUtilityIDs.remove(added) }
            self.isTransitioning = false
        }
    }
}
