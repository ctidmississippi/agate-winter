import SwiftUI
import UIKit

/// The system share sheet for an image. More reliable than ShareLink with a SwiftUI Image.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Renders a card to a light-mode PNG-ready image at 3x.
@MainActor func renderShareImage<V: View>(_ view: V) -> UIImage? {
    let r = ImageRenderer(content: view.environment(\.colorScheme, .light))
    r.scale = 3
    r.isOpaque = true
    return r.uiImage
}
