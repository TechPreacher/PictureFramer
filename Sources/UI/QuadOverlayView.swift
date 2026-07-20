import SwiftUI

/// Draws the detected/adjustable quad over the aspect-fitted source image
/// and lets the user drag its corners. All gesture math converts through
/// the one `DisplayMapper`. Reports drag begin/end so the editor can show a
/// magnifier loupe for the active corner.
struct QuadOverlayView: View {
    let quad: Quad
    let marginQuad: Quad?
    let mapper: DisplayMapper
    let onCornerMoved: (Quad.Corner, CGPoint) -> Void
    var onDragBegan: (Quad.Corner) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    private static let handleDiameter: CGFloat = 44

    var body: some View {
        let displayQuad = mapper.displayQuad(from: quad)
        ZStack {
            if let marginQuad {
                path(for: mapper.displayQuad(from: marginQuad))
                    .stroke(
                        .yellow.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
            }
            path(for: displayQuad)
                .stroke(.blue, lineWidth: 2)

            ForEach(Quad.Corner.allCases, id: \.self) { corner in
                CornerHandle(
                    position: displayQuad[corner],
                    diameter: Self.handleDiameter,
                    accessibilityName: accessibilityName(for: corner),
                    onMoved: { onCornerMoved(corner, $0) },
                    onBegan: { onDragBegan(corner) },
                    onEnded: onDragEnded
                )
            }
        }
    }

    private func path(for displayQuad: Quad) -> Path {
        Path { p in
            p.addLines(displayQuad.perimeterCorners)
            p.closeSubpath()
        }
    }

    private func accessibilityName(for corner: Quad.Corner) -> String {
        switch corner {
        case .topLeft: "Top left corner"
        case .topRight: "Top right corner"
        case .bottomLeft: "Bottom left corner"
        case .bottomRight: "Bottom right corner"
        }
    }
}

/// One draggable corner handle. Owns its own drag state so drag begin/end is
/// detected per corner without a flag shared across handles.
private struct CornerHandle: View {
    let position: CGPoint
    let diameter: CGFloat
    let accessibilityName: String
    let onMoved: (CGPoint) -> Void
    let onBegan: () -> Void
    let onEnded: () -> Void

    @State private var isDragging = false

    var body: some View {
        Circle()
            .fill(.blue.opacity(0.35))
            .overlay(Circle().stroke(.blue, lineWidth: 2))
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onBegan()
                        }
                        onMoved(value.location)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEnded()
                    }
            )
            .accessibilityLabel(accessibilityName)
            .accessibilityAddTraits(.allowsDirectInteraction)
    }
}
