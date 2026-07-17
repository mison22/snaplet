import AppKit
import SwiftUI

/// SwiftUI editor surface: renders the base screenshot with the live
/// annotation stack overlaid, and turns pointer gestures into new
/// `Annotation` values via `viewModel`.
///
/// ## Coordinate mapping
/// The base image is displayed scaled to fit `displaySize` (the size this
/// view is laid out at, itself chosen by `AnnotationWindowController` to fit
/// the screen). All gesture locations SwiftUI reports arrive in that same
/// top-left-origin *view-point* space, which already matches the flipped,
/// top-left-origin convention `Annotation`/`AnnotationRenderer` use — the
/// only difference is scale. So mapping a view point to a base-image pixel
/// point is a uniform scale by `imagePixelSize / displaySize` on both axes;
/// no axis flip is needed. `scaleToImage(_:)` performs that conversion, and
/// annotations are constructed with the *scaled* (native-pixel) points so
/// the flattened output lands at the correct native-resolution position
/// regardless of how small/large the editor window is on screen.
struct AnnotationView: View {
    /// Visual diameter of a resize handle dot, and the click tolerance
    /// (radius) around its center that counts as grabbing it -- both in view
    /// points, so handles feel the same size on screen regardless of the
    /// screenshot's native resolution.
    private static let handleDiameter: CGFloat = 8
    private static let handleHitRadius: CGFloat = 8

    let baseImage: CGImage
    let displaySize: CGSize
    @ObservedObject var viewModel: AnnotationEditorViewModel

    @FocusState private var isTextDraftFocused: Bool
    @FocusState private var isCanvasFocused: Bool

    private var imagePixelSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    private var scale: CGSize {
        CGSize(
            width: imagePixelSize.width / displaySize.width,
            height: imagePixelSize.height / displaySize.height
        )
    }

    var body: some View {
        Image(baseImage, scale: 1, label: Text("Screenshot"))
            .resizable()
            .frame(width: displaySize.width, height: displaySize.height)
            .overlay(
                Canvas { context, size in
                    draw(in: &context, size: size)
                }
                .frame(width: displaySize.width, height: displaySize.height)
                // `.simultaneousGesture` (not `.gesture`) so this drag
                // recognizer doesn't wait on `.onTapGesture` below to fail
                // before it starts streaming `onChanged` updates -- with
                // `.gesture`, SwiftUI disambiguates the two by withholding
                // drag updates until release, so the arrow/bubble preview
                // never appeared until the gesture ended.
                .simultaneousGesture(dragGesture)
                .onTapGesture { location in
                    handleTap(at: location)
                }
                .focusable()
                .focused($isCanvasFocused)
                .onAppear { isCanvasFocused = true }
                .onDeleteCommand {
                    viewModel.deleteSelectedAnnotation()
                }
                .onContinuousHover { phase in
                    updateCursor(for: phase)
                }
            )
            .overlay(alignment: .topLeading) {
                if let draft = viewModel.textDraft {
                    textDraftField(for: draft)
                }
            }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        for annotation in viewModel.annotations {
            drawPreview(of: annotation, in: &context)
        }

        if let start = viewModel.pendingArrowStart, let end = viewModel.pendingArrowEnd {
            // `drawPreview` expects native-pixel geometry (like every committed
            // annotation) and scales it back down to view points itself; feeding
            // it raw view-space points here double-shrinks the preview, which is
            // why it used to render away from the cursor instead of under it.
            drawPreview(
                of: .arrow(
                    Arrow(
                        start: scaleToImage(start),
                        end: scaleToImage(end),
                        color: viewModel.selectedColor,
                        lineWidth: viewModel.selectedLineWidth
                    )
                ),
                in: &context
            )
        }

        if let start = viewModel.pendingBubbleStart, let end = viewModel.pendingBubbleEnd {
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.stroke(Path(roundedRect: rect, cornerRadius: 12), with: .color(Color(nsColor: viewModel.selectedColor)), lineWidth: 2)
        }

        if let selectedID = viewModel.selectedAnnotationID,
           let selected = viewModel.annotations.first(where: { $0.id == selectedID }) {
            drawSelectionOutline(around: selected.boundingBox, in: &context)
            drawResizeHandles(for: selected, in: &context)
        }
    }

    /// Draws a small filled dot at each of `annotation`'s resize handles, in
    /// view points -- the inverse of `scaleToImage(_:)`, matching how every
    /// other native-pixel geometry is brought back down to view space.
    private func drawResizeHandles(for annotation: Annotation, in context: inout GraphicsContext) {
        for handle in annotation.resizeHandles {
            let center = viewPoint(for: handle.position)
            let rect = CGRect(
                x: center.x - Self.handleDiameter / 2,
                y: center.y - Self.handleDiameter / 2,
                width: Self.handleDiameter,
                height: Self.handleDiameter
            )
            let path = Path(ellipseIn: rect)
            context.fill(path, with: .color(.accentColor))
            context.stroke(path, with: .color(.white), lineWidth: 1)
        }
    }

    /// Draws a dashed selection indicator around `box` (native-pixel space,
    /// same convention as `Annotation.boundingBox`).
    private func drawSelectionOutline(around box: CGRect, in context: inout GraphicsContext) {
        let viewRect = CGRect(
            x: box.minX / scale.width,
            y: box.minY / scale.height,
            width: box.width / scale.width,
            height: box.height / scale.height
        ).insetBy(dx: -4, dy: -4)

        context.stroke(
            Path(roundedRect: viewRect, cornerRadius: 4),
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
    }

    /// Draws one annotation using its *native-pixel* geometry scaled back
    /// down to view points -- the inverse of `scaleToImage(_:)` -- so the
    /// on-screen preview matches what `AnnotationRenderer` will produce.
    ///
    /// `GraphicsContext.withCGContext` hands out a `CGContext` already in
    /// SwiftUI's top-left-origin, y-down space -- the same convention
    /// `Annotation.draw(in:)` assumes -- so only a uniform scale (no axis
    /// flip) is needed to go from native pixels to view points.
    private func drawPreview(of annotation: Annotation, in context: inout GraphicsContext) {
        context.withCGContext { cgContext in
            cgContext.saveGState()
            cgContext.scaleBy(x: 1 / scale.width, y: 1 / scale.height)
            annotation.draw(in: cgContext)
            cgContext.restoreGState()
        }
    }

    // MARK: - Coordinate mapping

    /// Converts a point in this view's on-screen point space to the base
    /// image's native pixel space. See the type-level doc comment.
    private func scaleToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale.width, y: point.y * scale.height)
    }

    private func scaleToImage(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * scale.width,
            y: rect.origin.y * scale.height,
            width: rect.width * scale.width,
            height: rect.height * scale.height
        )
    }

    /// Converts a native-pixel point back to this view's on-screen point
    /// space -- the inverse of `scaleToImage(_:)`.
    private func viewPoint(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale.width, y: point.y / scale.height)
    }

    /// Which resize handle of the currently selected annotation, if any, is
    /// under `location` (view space) within `handleHitRadius`.
    private func hitTestHandle(at location: CGPoint) -> ResizeHandle.Kind? {
        guard let selectedID = viewModel.selectedAnnotationID,
              let selected = viewModel.annotations.first(where: { $0.id == selectedID }) else {
            return nil
        }

        return selected.resizeHandles.first { handle in
            let center = viewPoint(for: handle.position)
            return hypot(center.x - location.x, center.y - location.y) <= Self.handleHitRadius
        }?.kind
    }

    // MARK: - Cursor

    /// Shows a crosshair cursor while hovering a resize handle of the
    /// selected annotation, so its draggability is visible before the user
    /// commits to a click -- reverts to the default arrow everywhere else,
    /// including when the pointer leaves the canvas entirely.
    private func updateCursor(for phase: HoverPhase) {
        switch phase {
        case .active(let location):
            if hitTestHandle(at: location) != nil {
                NSCursor.crosshair.set()
            } else {
                NSCursor.arrow.set()
            }
        case .ended:
            NSCursor.arrow.set()
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                switch viewModel.selectedTool {
                case .select:
                    viewModel.continueSelectDrag(
                        hitHandle: hitTestHandle(at: value.startLocation),
                        from: scaleToImage(value.startLocation),
                        to: scaleToImage(value.location)
                    )
                case .arrow:
                    viewModel.pendingArrowStart = viewModel.pendingArrowStart ?? value.startLocation
                    viewModel.pendingArrowEnd = value.location
                case .bubble:
                    viewModel.pendingBubbleStart = viewModel.pendingBubbleStart ?? value.startLocation
                    viewModel.pendingBubbleEnd = value.location
                case .text:
                    break
                }
            }
            .onEnded { value in
                switch viewModel.selectedTool {
                case .select:
                    viewModel.endSelectDrag()
                case .arrow:
                    let start = viewModel.pendingArrowStart ?? value.startLocation
                    let end = value.location
                    viewModel.pendingArrowStart = nil
                    viewModel.pendingArrowEnd = nil
                    viewModel.append(
                        .arrow(
                            Arrow(
                                start: scaleToImage(start),
                                end: scaleToImage(end),
                                color: viewModel.selectedColor,
                                lineWidth: viewModel.selectedLineWidth
                            )
                        )
                    )
                case .bubble:
                    let start = viewModel.pendingBubbleStart ?? value.startLocation
                    let end = value.location
                    viewModel.pendingBubbleStart = nil
                    viewModel.pendingBubbleEnd = nil
                    let bodyRect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: abs(end.x - start.x),
                        height: abs(end.y - start.y)
                    )
                    viewModel.textDraft = AnnotationEditorViewModel.TextDraft(kind: .bubble(bodyRect: bodyRect), anchor: end)
                case .text:
                    break
                }
            }
    }

    private func handleTap(at location: CGPoint) {
        switch viewModel.selectedTool {
        case .text:
            viewModel.textDraft = AnnotationEditorViewModel.TextDraft(kind: .text, anchor: location)
        case .select:
            viewModel.selectAnnotation(at: scaleToImage(location))
        case .arrow, .bubble:
            break
        }
    }

    // MARK: - Text entry

    @ViewBuilder
    private func textDraftField(for draft: AnnotationEditorViewModel.TextDraft) -> some View {
        let position: CGPoint = {
            switch draft.kind {
            case .text:
                return draft.anchor
            case .bubble(let bodyRect):
                return CGPoint(x: bodyRect.minX + 4, y: bodyRect.minY + 4)
            }
        }()

        TextField(
            "Type text",
            text: Binding(
                get: { viewModel.textDraft?.input ?? "" },
                set: { viewModel.textDraft?.input = $0 }
            )
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 220)
        .position(x: position.x + 110, y: position.y + 10)
        .focused($isTextDraftFocused)
        .onAppear {
            isTextDraftFocused = true
        }
        .onSubmit {
            commitTextDraft(draft)
        }
    }

    private func commitTextDraft(_ draft: AnnotationEditorViewModel.TextDraft) {
        defer {
            viewModel.textDraft = nil
            // The text field is about to leave the view hierarchy; hand
            // keyboard focus back to the canvas so Delete keeps working
            // without requiring an extra click first.
            isCanvasFocused = true
        }
        guard !draft.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        switch draft.kind {
        case .text:
            let origin = scaleToImage(draft.anchor)
            viewModel.append(.text(TextBox(origin: origin, text: draft.input, color: viewModel.selectedColor)))
        case .bubble(let bodyRect):
            let scaledBodyRect = scaleToImage(bodyRect)
            let tailTarget = CGPoint(
                x: scaledBodyRect.minX + AnnotationEditorViewModel.defaultBubbleTailOffsetValue.x,
                y: scaledBodyRect.maxY + AnnotationEditorViewModel.defaultBubbleTailOffsetValue.y
            )
            viewModel.append(
                .bubble(
                    SpeechBubble(
                        bodyRect: scaledBodyRect,
                        tailTarget: tailTarget,
                        text: draft.input,
                        color: viewModel.selectedColor
                    )
                )
            )
        }
    }
}
