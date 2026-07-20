import SwiftUI
import UIKit  // Color(.systemBackground) resolves via UIColor

/// A magnifier loupe shown while a quad corner is being dragged. Renders a
/// zoomed circle of the source image centered on the corner's landing point,
/// parked at the top of the image area opposite the finger, with a crosshair
/// marking the exact point and the two frame edges that meet at the corner.
/// All coordinate math goes through `LoupeGeometry` and the shared
/// `DisplayMapper` — the loupe adds no new coordinate conventions.
struct MagnifierLoupeView: View {
    let image: CGImage
    let mapper: DisplayMapper
    let quad: Quad
    let corner: Quad.Corner
    let areaSize: CGSize

    private static let magnification: CGFloat = 2.5
    private static let diameter: CGFloat = 120
    private static let margin: CGFloat = 16
    private static let crosshairArm: CGFloat = 10

    private var focusDisplay: CGPoint {
        mapper.displayPoint(fromPixel: quad[corner])
    }

    private var geometry: LoupeGeometry {
        LoupeGeometry(
            focusDisplay: focusDisplay,
            magnification: Self.magnification,
            diameter: Self.diameter
        )
    }

    var body: some View {
        let frame = LoupeGeometry.placement(
            focusDisplay: focusDisplay, areaSize: areaSize,
            diameter: Self.diameter, margin: Self.margin)
        content
            .frame(width: Self.diameter, height: Self.diameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(.blue.opacity(0.6), lineWidth: 1.5))
            .shadow(radius: 4, y: 2)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
    }

    private var content: some View {
        ZStack {
            Color(.systemBackground)
            magnifiedImage
            edgesPath.stroke(.blue, lineWidth: 2)
            crosshairPath.stroke(.blue.opacity(0.9), lineWidth: 1)
        }
    }

    /// The source image drawn at `magnification`× the fitted size, positioned
    /// so the focus point lands at the loupe center.
    private var magnifiedImage: some View {
        let fitted = mapper.fittedRect
        let magW = fitted.width * Self.magnification
        let magH = fitted.height * Self.magnification
        let focusInMagX = (focusDisplay.x - fitted.minX) * Self.magnification
        let focusInMagY = (focusDisplay.y - fitted.minY) * Self.magnification
        // .position sets the subview's CENTER. Solve for the center that puts
        // the focus point at the loupe center (diameter/2).
        let centerX = Self.diameter / 2 + magW / 2 - focusInMagX
        let centerY = Self.diameter / 2 + magH / 2 - focusInMagY
        return Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: magW, height: magH)
            .position(x: centerX, y: centerY)
    }

    private var edgesPath: Path {
        Path { p in
            let c = geometry.center
            for adjacent in adjacentCorners {
                let adjacentDisplay = mapper.displayPoint(fromPixel: quad[adjacent])
                p.move(to: c)
                p.addLine(to: geometry.project(adjacentDisplay))
            }
        }
    }

    private var crosshairPath: Path {
        Path { p in
            let c = geometry.center
            let a = Self.crosshairArm
            p.move(to: CGPoint(x: c.x - a, y: c.y))
            p.addLine(to: CGPoint(x: c.x + a, y: c.y))
            p.move(to: CGPoint(x: c.x, y: c.y - a))
            p.addLine(to: CGPoint(x: c.x, y: c.y + a))
        }
    }

    /// The two perimeter neighbors of `corner` (top/bottom edge + side edge).
    private var adjacentCorners: [Quad.Corner] {
        switch corner {
        case .topLeft: [.topRight, .bottomLeft]
        case .topRight: [.topLeft, .bottomRight]
        case .bottomLeft: [.topLeft, .bottomRight]
        case .bottomRight: [.topRight, .bottomLeft]
        }
    }
}
