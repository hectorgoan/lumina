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

        step(Motion.dismiss, lasting: Motion.dismissDuration) {
            isPageVisible = false
        } completion: {
            var added: String?
            self.step(Motion.resize, lasting: Motion.resizeDuration) {
                added = change()
                if let added { self.fadingUtilityIDs.insert(added) }
            } completion: {
                withAnimation(Motion.present) {
                    self.isPageVisible = true
                    if let added { self.fadingUtilityIDs.remove(added) }
                }
                if let added { self.highlight(added) }
                self.isTransitioning = false
            }
        }
    }

    // MARK: - More section

    /// Opens the section (room is made, then its tiles fade in) or closes
    /// it (its tiles fade out, then the room closes).
    func toggleMore() {
        guard !isTransitioning else { return }
        isTransitioning = true
        // The Stack's header changes too (the stacked card or the open
        // title), so it fades out, swaps while the panel resizes, and fades
        // back in, both ways.
        if isMoreOpen || moreStyle == .stack {
            let opening = !isMoreOpen
            step(Motion.dismiss, lasting: Motion.dismissDuration) {
                self.isMoreFading = true
            } completion: {
                self.step(Motion.resize, lasting: Motion.resizeDuration) {
                    self.isMoreOpen = opening
                } completion: {
                    withAnimation(Motion.present) { self.isMoreFading = false }
                    self.isTransitioning = false
                }
            }
        } else {
            step(Motion.resize, lasting: Motion.resizeDuration) {
                self.isMoreFading = true
                self.isMoreOpen = true
            } completion: {
                withAnimation(Motion.present) { self.isMoreFading = false }
                self.isTransitioning = false
            }
        }
    }

    /// The Pages style's switch: the whole page fades, swaps and fades in.
    func showMorePage(_ open: Bool) {
        // Requests during a turn are dropped, rather than applied at once.
        guard open != isMoreOpen, !isTransitioning else { return }
        swapPage { self.isMoreOpen = open }
    }

    func openMoreSettings() {
        swapPage { self.isMoreSettingsOpen = true }
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

    /// Removes a utility with the Dock's poof: the caller plays the poof
    /// where the tile was, the tile vanishes at once, and after a beat the
    /// grid closes the gap.
    func poofTile(_ utility: Utility) {
        guard !isTransitioning else { remove(utility); return }
        isTransitioning = true

        fadingUtilityIDs.insert(utility.id)
        // Let the poof read before the other tiles move in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.step(Motion.resize, lasting: Motion.resizeDuration) {
                self.remove(utility)
            } completion: {
                self.fadingUtilityIDs.remove(utility.id)
                self.isTransitioning = false
            }
        }
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

        step(Motion.dismiss, lasting: Motion.dismissDuration) {
            _ = fadingUtilityIDs.insert(id)
        } completion: {
            self.step(Motion.resize, lasting: Motion.resizeDuration) {
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
        step(Motion.resize, lasting: Motion.resizeDuration) {
            added = change()
            fadingUtilityIDs.insert(added)
        } completion: {
            withAnimation(Motion.present) { _ = self.fadingUtilityIDs.remove(added) }
            self.highlight(added)
            self.isTransitioning = false
        }
    }

    /// Marks a tile just added: the grid scrolls to it as it fades in, a
    /// ring glows around it, and fades away after a moment.
    func highlight(_ id: String) {
        withAnimation(Motion.present) { highlightedUtilityID = id }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard highlightedUtilityID == id else { return }
            withAnimation(.easeOut(duration: 0.8)) { highlightedUtilityID = nil }
        }
    }

    /// Runs one animated step of a transition, then `completion` once
    /// SwiftUI reports the step done, or once its curve has run if it
    /// doesn't. Something animating endlessly nearby (like a symbol that
    /// turns while a scan runs) can keep that report from ever coming,
    /// which left the panel sitting empty until it stopped.
    func step(_ animation: Animation, lasting duration: TimeInterval, _ change: () -> Void, completion: @escaping @MainActor () -> Void) {
        Motion.step(animation, lasting: duration, change, completion: completion)
    }
}
