import AppKit
import SwiftUI

/// Hosts the annotation editor (floating tool pill + canvas + export bar) in
/// its own window.
///
/// One controller is created per capture (`init(image:)`) and shows a window
/// sized so the captured image floats on a matte with room for the toolbar
/// above and the export actions below. The app is `LSUIElement` (no Dock
/// icon), so `show()` explicitly activates the app and brings the window to
/// the front/key.
@MainActor
final class AnnotationWindowController: NSWindowController {

    /// Largest fraction of the active screen's visible frame the editor window
    /// is allowed to occupy.
    private static let maxScreenFraction: CGFloat = 0.85

    /// Matte inset around the whole composition.
    private static let mattePadding: CGFloat = 24
    /// Vertical room reserved for the floating tool pill (including its shadow).
    private static let toolbarZone: CGFloat = 46
    /// Vertical room reserved for the bottom export bar.
    private static let actionZone: CGFloat = 34
    /// Gap between the pill, the image, and the export bar.
    private static let stackSpacing: CGFloat = 16
    /// Floor on window width so the tool pill and export bar never clip on a
    /// narrow capture.
    private static let minContentWidth: CGFloat = 600

    private static var verticalChrome: CGFloat {
        mattePadding * 2 + toolbarZone + stackSpacing + stackSpacing + actionZone
    }

    private let baseImage: CGImage
    private let viewModel = AnnotationEditorViewModel()

    /// - Parameter image: The native-resolution capture to annotate. Save and
    ///   Copy always flatten this image, never a scaled preview.
    init(image: CGImage) {
        self.baseImage = image

        let displaySize = Self.fittedDisplaySize(forImage: image)
        let contentSize = CGSize(
            width: max(displaySize.width + Self.mattePadding * 2, Self.minContentWidth),
            height: displaySize.height + Self.verticalChrome
        )

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(image.width) × \(image.height)"
        window.titlebarAppearsTransparent = true
        // Not `isMovableByWindowBackground`: it treats a drag anywhere on the
        // matte -- including over the canvas -- as a window move, which would
        // hijack the arrow/area drawing drags. The title bar still moves the
        // window normally.
        window.backgroundColor = .underPageBackgroundColor
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

    /// Computes the on-screen size (in points) the base image should display
    /// at: native size if it fits within `maxScreenFraction` of the active
    /// screen's visible frame (after reserving the editor's chrome), otherwise
    /// scaled down uniformly to fit while preserving aspect ratio. Never
    /// scales an image up past its native size.
    private static func fittedDisplaySize(forImage image: CGImage) -> CGSize {
        let nativeSize = CGSize(width: image.width, height: image.height)
        guard let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return nativeSize
        }

        let maxSize = CGSize(
            width: visibleFrame.width * maxScreenFraction - mattePadding * 2,
            height: visibleFrame.height * maxScreenFraction - verticalChrome
        )

        guard nativeSize.width > maxSize.width || nativeSize.height > maxSize.height else {
            return nativeSize
        }

        let scale = min(maxSize.width / nativeSize.width, maxSize.height / nativeSize.height)
        return CGSize(width: nativeSize.width * scale, height: nativeSize.height * scale)
    }
}

extension AnnotationWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
    }
}

/// Lays out the editor over a matte: the floating tool pill on top, the
/// captured image floating with a shadow in the middle, and the export bar
/// bottom-right.
private struct AnnotationEditorContainerView: View {
    private static let imageCornerRadius: CGFloat = 8

    let baseImage: CGImage
    let displaySize: CGSize
    @ObservedObject var viewModel: AnnotationEditorViewModel
    let onRequestClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            AnnotationToolbar(viewModel: viewModel)

            AnnotationView(baseImage: baseImage, displaySize: displaySize, viewModel: viewModel)
                .frame(width: displaySize.width, height: displaySize.height)
                .clipShape(RoundedRectangle(cornerRadius: Self.imageCornerRadius))
                .shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 8)

            HStack {
                Spacer()
                AnnotationActionBar(baseImage: baseImage, viewModel: viewModel, onRequestClose: onRequestClose)
            }
            .frame(width: displaySize.width)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
