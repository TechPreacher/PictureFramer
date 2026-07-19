import SwiftUI
import UIKit

/// UIScrollView-backed pinch-zoom wrapper for SwiftUI content.
/// One finger stays free for the content's own gestures (the mask brush):
/// the scroll view's pan requires TWO touches, pinch zooms natively.
struct ZoomableContainer<Content: View>: UIViewRepresentable {
    /// Mirrors the scroll view's current zoom so the brush can scale its
    /// radius down while zoomed in (finer strokes in image pixels).
    @Binding var zoomScale: CGFloat
    let maximumZoom: CGFloat
    private let content: Content

    init(
        zoomScale: Binding<CGFloat>,
        maximumZoom: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        _zoomScale = zoomScale
        self.maximumZoom = maximumZoom
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maximumZoom
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        // Leave single-finger drags to the SwiftUI brush gesture.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.delaysContentTouches = false

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            // Content logical size == viewport; zooming scales it.
            host.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            host.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.host = host
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.host?.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(zoomScale: $zoomScale)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var host: UIHostingController<Content>?
        private let zoomScale: Binding<CGFloat>

        init(zoomScale: Binding<CGFloat>) {
            self.zoomScale = zoomScale
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            host?.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            zoomScale.wrappedValue = scrollView.zoomScale
        }
    }
}
