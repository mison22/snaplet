import AppKit
import SwiftUI

/// Hosts the annotation editor (toolbar + canvas) in its own titled window.
///
/// One controller is created per capture (`init(image:)`) and shows a
/// window sized to fit the captured image within the active screen's
/// visible frame. The app is `LSUIElement` (no Dock icon, no regular
/// activation policy transitions here), so `show()` explicitly activates
/// the app and brings the window to the front/key.
@MainActor
final class AnnotationWindowController: NSWindowController {

    /// Largest fraction of the active screen's visible frame the editor
    /// window is allowed to occupy, leaving breathing room around the
    /// window rather than filling the screen edge-to-edge.
    private static let maxScreenFraction: CGFloat = 0.85

    /// Height reserved for the toolbar above the canvas, added on top of the
    /// scaled image height when sizing the window's content view.
    private static let toolbarHeight: CGFloat = 44

    private let baseImage: CGImage
    private let viewModel = AnnotationEditorViewModel()

    /// - Parameter image: The native-resolution capture to annotate. Save
    ///   and Copy always flatten this image, never a scaled preview.
    init(image: CGImage) {
        self.baseImage = image

        let displaySize = Self.fittedDisplaySize(forImage: image)
        let contentSize = CGSize(width: displaySize.width, height: displaySize.height + Self.toolbarHeight)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Snaplet"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let rootView = AnnotationEditorContainerView(
            baseImage: image,
            displaySize: displaySize,
            viewModel: viewModel,
            onRequestClose: { [weak self] in self?.close() }
        )
        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Brings the editor window to the front. See
    /// `NSWindowController.activateAndShowWindow()`.
    func show() {
        activateAndShowWindow()
    }

    /// Computes the on-screen size (in points) the base image should be
    /// displayed at: native size if it already fits within
    /// `maxScreenFraction` of the active screen's visible frame, otherwise
    /// scaled down uniformly to fit while preserving aspect ratio. The
    /// editor never scales an image *up* past its native size.
    private static func fittedDisplaySize(forImage image: CGImage) -> CGSize {
        let nativeSize = CGSize(width: image.width, height: image.height)
        guard let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return nativeSize
        }

        let maxSize = CGSize(
            width: visibleFrame.width * maxScreenFraction,
            height: (visibleFrame.height - toolbarHeight) * maxScreenFraction
        )

        guard nativeSize.width > maxSize.width || nativeSize.height > maxSize.height else {
            return nativeSize
        }

        let widthScale = maxSize.width / nativeSize.width
        let heightScale = maxSize.height / nativeSize.height
        let scale = min(widthScale, heightScale)

        return CGSize(width: nativeSize.width * scale, height: nativeSize.height * scale)
    }
}

extension AnnotationWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
    }
}

/// Combines the toolbar and the annotation canvas into the window's single
/// content view.
private struct AnnotationEditorContainerView: View {
    let baseImage: CGImage
    let displaySize: CGSize
    @ObservedObject var viewModel: AnnotationEditorViewModel
    let onRequestClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AnnotationToolbar(baseImage: baseImage, viewModel: viewModel, onRequestClose: onRequestClose)
            Divider()
            AnnotationView(baseImage: baseImage, displaySize: displaySize, viewModel: viewModel)
        }
    }
}
