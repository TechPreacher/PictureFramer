import SwiftUI

/// Draws the detected/adjustable quad over the aspect-fitted source image
/// and lets the user drag its corners. All gesture math converts through
/// the one `DisplayMapper`.
struct QuadOverlayView: View {
    let quad: Quad
    let marginQuad: Quad?
    let mapper: DisplayMapper
    let onCornerMoved: (Quad.Corner, CGPoint) -> Void

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
                handle(at: displayQuad[corner], corner: corner)
            }
        }
    }

    private func path(for displayQuad: Quad) -> Path {
        Path { p in
            p.addLines(displayQuad.perimeterCorners)
            p.closeSubpath()
        }
    }

    private func handle(at position: CGPoint, corner: Quad.Corner) -> some View {
        Circle()
            .fill(.blue.opacity(0.35))
            .overlay(Circle().stroke(.blue, lineWidth: 2))
            .frame(width: Self.handleDiameter, height: Self.handleDiameter)
            .contentShape(Circle())
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onCornerMoved(corner, value.location)
                    }
            )
            .accessibilityLabel(accessibilityName(for: corner))
            .accessibilityAddTraits(.allowsDirectInteraction)
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
