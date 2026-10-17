import SwiftUI

/// A four-column grid of tiles that can be dragged into a new order while
/// editing.
///
/// Tiles span one, two or all four columns and fill rows in order, starting
/// a new row when the next tile doesn't fit. The dragged tile follows the pointer while the others
/// animate out of the way.
struct ReorderableGrid<Item: Identifiable, Content: View>: View {
    @Binding var items: [Item]
    var isEditing: Bool
    var spacing: CGFloat = 10
    /// The number of columns (1 to 4) an item spans.
    var span: (Item) -> Int
    /// Whether an item can be picked up; others stay put while the rest
    /// move around them.
    var canDrag: (Item) -> Bool = { _ in true }
    @ViewBuilder var content: (_ item: Item, _ isLifted: Bool) -> Content

    @StateObject private var drag = DragState<Item.ID>()

    private let coordinateSpace = "ReorderableGrid"

    var body: some View {
        TileGridLayout(spacing: spacing) {
            ForEach(items) { item in
                let isLifted = drag.draggedID == item.id

                content(item, isLifted)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                        // Publishing redraws the whole grid, so only on a real change.
                        if drag.heights[item.id] != height { drag.heights[item.id] = height }
                    }
                    // Attached to the tile itself so controls inside it
                    // (like edit badges) stay clickable.
                    .contentShape(Rectangle())
                    .gesture(dragGesture(for: item.id), isEnabled: isEditing && canDrag(item))
                    .pointerStyle(isEditing && canDrag(item) ? (isLifted ? .grabActive : .grabIdle) : nil)
                    .offset(isLifted ? drag.offset : .zero)
                    .zIndex(isLifted ? 1 : 0)
                    // Keep the lifted tile pinned under the pointer instead of
                    // animating along with its siblings.
                    .transaction { if isLifted { $0.animation = nil } }
                    // Must be outermost so the layout can read it.
                    .layoutValue(key: TileSpan.self, value: span(item))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
            if drag.width != width { drag.width = width }
        }
        .coordinateSpace(.named(coordinateSpace))
    }

    private func dragGesture(for id: Item.ID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                if drag.draggedID != id {
                    drag.draggedID = id
                    drag.startOrigin = frame(of: id, in: items).origin
                }

                let size = frame(of: id, in: items).size
                let desiredOrigin = CGPoint(
                    x: drag.startOrigin.x + value.translation.width,
                    y: drag.startOrigin.y + value.translation.height
                )
                let desiredCenter = CGPoint(x: desiredOrigin.x + size.width / 2, y: desiredOrigin.y + size.height / 2)

                if let reordered = bestOrder(moving: id, toward: desiredCenter) {
                    withAnimation(.snappy(duration: 0.25)) { items = reordered }
                }

                let origin = frame(of: id, in: items).origin
                drag.offset = CGSize(width: desiredOrigin.x - origin.x, height: desiredOrigin.y - origin.y)
            }
            .onEnded { _ in
                withAnimation(.snappy(duration: 0.25)) {
                    drag.draggedID = nil
                    drag.offset = .zero
                }
            }
    }

    /// Tries the dragged tile in every position and returns the order that
    /// lands it closest to the pointer, or `nil` if the current one is best.
    private func bestOrder(moving id: Item.ID, toward center: CGPoint) -> [Item]? {
        guard let source = items.firstIndex(where: { $0.id == id }) else { return nil }

        var others = items
        let moving = others.remove(at: source)

        var best: (order: [Item], distance: CGFloat)?
        for index in 0...others.count {
            var candidate = others
            candidate.insert(moving, at: index)
            let frame = frame(of: id, in: candidate)
            let distance = hypot(frame.midX - center.x, frame.midY - center.y)
            if distance < best?.distance ?? .infinity {
                best = (candidate, distance)
            }
        }

        guard let best, best.order.map(\.id) != items.map(\.id) else { return nil }
        return best.order
    }

    private func frame(of id: Item.ID, in order: [Item]) -> CGRect {
        let frames = TileGridMetrics(width: drag.width, spacing: spacing).frames(
            spans: order.map(span),
            heights: order.map { drag.heights[$0.id] ?? 0 }
        )
        guard let index = order.firstIndex(where: { $0.id == id }) else { return .zero }
        return frames[index]
    }
}

/// Per-grid drag bookkeeping.
private final class DragState<ID: Hashable>: ObservableObject {
    @Published var heights: [ID: CGFloat] = [:]
    @Published var width: CGFloat = 0
    @Published var draggedID: ID?
    @Published var startOrigin: CGPoint = .zero
    @Published var offset: CGSize = .zero
}

// MARK: - Layout

/// The number of grid columns a tile spans.
struct TileSpan: LayoutValueKey {
    static let defaultValue = TileGridMetrics.columns
}

/// The packing rules shared by the layout and the drag logic.
struct TileGridMetrics {
    static let columns = 4

    var width: CGFloat
    var spacing: CGFloat

    private var columnWidth: CGFloat {
        (width - spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
    }

    func width(forSpan span: Int) -> CGFloat {
        let span = CGFloat(min(max(span, 1), Self.columns))
        return columnWidth * span + spacing * (span - 1)
    }

    /// Places tiles row by row, starting a new row whenever a tile doesn't
    /// fit beside the previous one.
    func frames(spans: [Int], heights: [CGFloat]) -> [CGRect] {
        var frames: [CGRect] = []
        var y: CGFloat = 0
        var column = 0
        var rowHeight: CGFloat = 0

        for (span, height) in zip(spans, heights) {
            let span = min(max(span, 1), Self.columns)
            if column + span > Self.columns {
                y += rowHeight + spacing
                column = 0
                rowHeight = 0
            }
            let x = CGFloat(column) * (columnWidth + spacing)
            frames.append(CGRect(x: x, y: y, width: width(forSpan: span), height: height))
            rowHeight = max(rowHeight, height)
            column += span
        }
        return frames
    }
}

struct TileGridLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let metrics = TileGridMetrics(width: width, spacing: spacing)
        let spans = subviews.map { $0[TileSpan.self] }
        let heights = zip(spans, subviews).map { span, subview in
            subview.sizeThatFits(ProposedViewSize(width: metrics.width(forSpan: span), height: nil)).height
        }
        return metrics.frames(spans: spans, heights: heights)
    }
}
