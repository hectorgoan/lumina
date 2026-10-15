import SwiftUI

/// A vertical stack whose rows can be dragged into a new order while editing.
///
/// Rows may have different heights; their measured sizes decide where a
/// dragged row lands. The dragged row follows the pointer while its siblings
/// animate out of the way.
struct ReorderableStack<Item: Identifiable, Content: View>: View {
    @Binding var items: [Item]
    var isEditing: Bool
    var spacing: CGFloat = 10
    @ViewBuilder var content: (_ item: Item, _ isLifted: Bool) -> Content

    @StateObject private var drag = DragState<Item.ID>()

    private let coordinateSpace = "ReorderableStack"

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(items) { item in
                let isLifted = drag.draggedID == item.id

                content(item, isLifted)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { drag.heights[item.id] = $0 }
                    .overlay {
                        if isEditing {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(dragGesture(for: item.id))
                                .pointerStyle(isLifted ? .grabActive : .grabIdle)
                        }
                    }
                    .offset(y: isLifted ? drag.dragOffset : 0)
                    .zIndex(isLifted ? 1 : 0)
                    // Keep the lifted row pinned under the pointer instead of
                    // animating along with its siblings.
                    .transaction { if isLifted { $0.animation = nil } }
            }
        }
        .coordinateSpace(.named(coordinateSpace))
    }

    private func dragGesture(for id: Item.ID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                if drag.draggedID != id {
                    drag.draggedID = id
                    drag.dragStartTop = top(of: id)
                }

                let desiredTop = drag.dragStartTop + value.translation.height
                let center = desiredTop + (drag.heights[id] ?? 0) / 2
                let target = targetIndex(for: id, center: center)

                if let source = items.firstIndex(where: { $0.id == id }), source != target {
                    var reordered = items
                    reordered.insert(reordered.remove(at: source), at: target)
                    withAnimation(.snappy(duration: 0.25)) { items = reordered }
                }

                drag.dragOffset = desiredTop - top(of: id)
            }
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.25)) {
                    drag.draggedID = nil
                    drag.dragOffset = 0
                }
            }
    }

    /// The resting y position of a row in the current order.
    private func top(of id: Item.ID) -> CGFloat {
        var y: CGFloat = 0
        for item in items {
            if item.id == id { return y }
            y += (drag.heights[item.id] ?? 0) + spacing
        }
        return y
    }

    /// Where a dragged row whose center is at `center` belongs among the others.
    private func targetIndex(for id: Item.ID, center: CGFloat) -> Int {
        var index = 0
        var y: CGFloat = 0
        for item in items where item.id != id {
            let height = drag.heights[item.id] ?? 0
            if center > y + height / 2 { index += 1 }
            y += height + spacing
        }
        return index
    }
}

/// Per-stack drag bookkeeping.
private final class DragState<ID: Hashable>: ObservableObject {
    @Published var heights: [ID: CGFloat] = [:]
    @Published var draggedID: ID?
    @Published var dragStartTop: CGFloat = 0
    @Published var dragOffset: CGFloat = 0
}
