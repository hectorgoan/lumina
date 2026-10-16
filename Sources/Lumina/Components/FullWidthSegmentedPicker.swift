import AppKit
import SwiftUI

/// A segmented control whose equal-width segments span the available width.
/// SwiftUI's segmented picker on macOS keeps its labels' natural width, which
/// looks lost with short labels like S, M, L and XL.
struct FullWidthSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.label),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if let index = options.firstIndex(where: { $0.value == selection }) {
            control.selectedSegment = index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? control.intrinsicContentSize.width, height: control.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: FullWidthSegmentedPicker

        init(parent: FullWidthSegmentedPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ control: NSSegmentedControl) {
            guard parent.options.indices.contains(control.selectedSegment) else { return }
            parent.selection = parent.options[control.selectedSegment].value
        }
    }
}
