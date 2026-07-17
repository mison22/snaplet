import AppKit

/// Owns the annotation editor's mutable state: the annotation stack, the
/// currently selected tool/color, and the in-progress gesture (drag or text
/// entry) that hasn't yet been committed to `annotations`.
///
/// Lives for the lifetime of one `AnnotationView`/`AnnotationWindowController`
/// pair; there is no persistence beyond the in-memory stack, matching the
/// single-level undo (no redo) called for by the spec.
@MainActor
final class AnnotationEditorViewModel: ObservableObject {

    /// Index of the default line/text color within `AppConstants.annotationPalette`.
    private static let defaultColorIndex = 0

    /// Default size for a newly placed bubble body before the user drags,
    /// and the offset used to place its tail when a drag is too small to
    /// read as intentional sizing.
    private static let defaultBubbleTailOffset = CGPoint(x: -24, y: 24)

    @Published var annotations: [Annotation] = []
    @Published var selectedTool: AnnotationTool = .arrow
    @Published var selectedColor: NSColor = AppConstants.annotationPalette[AnnotationEditorViewModel.defaultColorIndex]
    @Published var selectedLineWidth: CGFloat = Arrow.defaultLineWidth
    @Published var selectedFontSize: CGFloat = TextBox.defaultFontSize
    /// Font family for new text/bubbles, or `nil` for the system font.
    @Published var selectedFontName: String?

    /// In-progress arrow drag, tracked in on-screen (view) coordinates so the
    /// live preview can be drawn before the gesture ends.
    @Published var pendingArrowStart: CGPoint?
    @Published var pendingArrowEnd: CGPoint?

    /// In-progress bubble drag (body rect corners), in view coordinates.
    @Published var pendingBubbleStart: CGPoint?
    @Published var pendingBubbleEnd: CGPoint?

    /// A text or bubble draft awaiting the user's typed string. `origin`/
    /// `bodyRect` are already in view coordinates; committed by
    /// `commitTextDraft(_:)`.
    @Published var textDraft: TextDraft?

    /// The annotation currently selected by the `.select` tool, if any.
    /// Drives the selection outline and enables the Delete action.
    ///
    /// Selecting an annotation syncs `selectedColor`/`selectedLineWidth` to
    /// its current values, so the toolbar's swatches reflect what's actually
    /// selected rather than whatever was last picked for new annotations.
    @Published var selectedAnnotationID: Annotation.ID? {
        didSet {
            guard let id = selectedAnnotationID, let selected = annotations.first(where: { $0.id == id }) else { return }
            selectedColor = selected.color
            if case .arrow(let arrow) = selected {
                selectedLineWidth = arrow.lineWidth
            }
            if let fontSize = selected.fontSize {
                selectedFontSize = fontSize
                selectedFontName = selected.fontName
            }
        }
    }

    /// The annotation currently being dragged by the `.select` tool, and the
    /// cumulative native-pixel delta already applied to it. Not `@Published`:
    /// this is drag bookkeeping only, and mutating `annotations` directly
    /// already triggers the redraw the in-progress move needs.
    private var pendingMoveAnnotationID: Annotation.ID?
    private var pendingMoveAppliedDelta: CGSize = .zero

    /// The resize handle currently being dragged, and a snapshot of
    /// `selectedAnnotationID`'s annotation as it was when the drag began.
    /// Every drag tick re-derives from this same snapshot (never the
    /// previous tick's result) so a resize can't drift or compound.
    private var pendingResizeHandle: ResizeHandle.Kind?
    private var pendingResizeOriginal: Annotation?

    struct TextDraft: Identifiable {
        enum Kind {
            case text
            case bubble(bodyRect: CGRect)
        }

        let id = UUID()
        var kind: Kind
        var anchor: CGPoint
        var input: String = ""

        /// When set, committing this draft edits the existing annotation with
        /// this id (preserving its geometry/styling) rather than creating a
        /// new one. Set by double-click-to-edit.
        var editingID: Annotation.ID?
    }

    var canUndo: Bool { !annotations.isEmpty }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    func append(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    /// Cancels any drag/text state in progress without committing an
    /// annotation. Used when the user switches tools mid-gesture.
    func cancelPendingGesture() {
        pendingArrowStart = nil
        pendingArrowEnd = nil
        pendingBubbleStart = nil
        pendingBubbleEnd = nil
        textDraft = nil
        selectedAnnotationID = nil
        pendingMoveAnnotationID = nil
        pendingMoveAppliedDelta = .zero
        pendingResizeHandle = nil
        pendingResizeOriginal = nil
    }

    static var defaultBubbleTailOffsetValue: CGPoint { defaultBubbleTailOffset }

    // MARK: - Select, move, delete

    /// The topmost (last-drawn) annotation whose visible geometry contains
    /// `point` (native-pixel space), or `nil` if none does.
    func annotation(at point: CGPoint) -> Annotation? {
        annotations.last(where: { $0.hitTest(point) })
    }

    /// Which annotation a move drag starting at `point` should grab. Prefers
    /// the already-selected annotation if `point` falls anywhere within its
    /// bounding box -- matching the generous area its selection outline
    /// visually implies, rather than requiring the precise per-shape
    /// `hitTest` a first click needs -- and otherwise falls back to that
    /// precise hit-test so clicking a different (or no) annotation still
    /// works as expected.
    private func annotationForMove(at point: CGPoint) -> Annotation.ID? {
        if let selectedID = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == selectedID }),
           selected.boundingBox.contains(point) {
            return selectedID
        }
        return annotation(at: point)?.id
    }

    /// Selects whichever annotation is under `point`, or clears the
    /// selection if none is. Used for a plain tap/click with the `.select`
    /// tool, separately from the drag-to-move gesture below.
    func selectAnnotation(at point: CGPoint) {
        selectedAnnotationID = annotation(at: point)?.id
    }

    /// Drives one tick of a `.select`-tool drag. `hitHandle` is the resize
    /// handle (if any) under the drag's start location, hit-tested by the
    /// caller since only it knows the view/image scale factor; on the first
    /// tick of a gesture this decides once whether the drag resizes the
    /// currently selected annotation or moves/selects whichever annotation
    /// is under `startPoint`, and sticks with that choice for the rest of
    /// the gesture. Both points are native-pixel space.
    func continueSelectDrag(hitHandle: ResizeHandle.Kind?, from startPoint: CGPoint, to currentPoint: CGPoint) {
        if pendingMoveAnnotationID == nil, pendingResizeHandle == nil, let handle = hitHandle {
            beginResize(handle: handle)
        }

        if pendingResizeHandle != nil {
            continueResize(to: currentPoint)
        } else {
            beginOrContinueMove(from: startPoint, to: currentPoint)
        }
    }

    /// Ends a `.select`-tool drag started by `continueSelectDrag`, leaving
    /// the moved/resized annotation selected.
    func endSelectDrag() {
        endMove()
        endResize()
    }

    /// Deletes the currently selected annotation, if any.
    func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        annotations.removeAll { $0.id == id }
        selectedAnnotationID = nil
    }

    /// Replaces the text of the annotation with `id`, preserving its geometry
    /// and styling. Used when committing a double-click edit.
    func updateText(id: Annotation.ID, to text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = annotations[index].withText(text)
    }

    /// Removes the annotation with `id` (e.g. when an edit clears its text).
    func removeAnnotation(id: Annotation.ID) {
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id { selectedAnnotationID = nil }
    }

    /// Sets the color used for new annotations and, if one is selected,
    /// recolors it too.
    func setColor(_ color: NSColor) {
        selectedColor = color
        applyToSelected { $0.withColor(color) }
    }

    /// Sets the line width used for new arrows and, if an arrow is selected,
    /// re-strokes it too. A no-op on the selection for any other annotation
    /// kind, since only arrows have an adjustable line width.
    func setLineWidth(_ lineWidth: CGFloat) {
        selectedLineWidth = lineWidth
        applyToSelected { $0.withLineWidth(lineWidth) }
    }

    /// Sets the font size for new text/bubbles and, if a textual annotation is
    /// selected, resizes it too.
    func setFontSize(_ fontSize: CGFloat) {
        selectedFontSize = fontSize
        applyToSelected { $0.withFontSize(fontSize) }
    }

    /// Sets the font family (`nil` = system) for new text/bubbles and, if a
    /// textual annotation is selected, restyles it too.
    func setFontName(_ fontName: String?) {
        selectedFontName = fontName
        applyToSelected { $0.withFontName(fontName) }
    }

    private func applyToSelected(_ transform: (Annotation) -> Annotation) {
        guard let id = selectedAnnotationID, let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = transform(annotations[index])
    }

    /// On the first call for a gesture, decides which annotation (if any) is
    /// being dragged; on every call, applies only the incremental delta
    /// since the last call so the move doesn't drift. A no-op if the drag
    /// didn't start on an annotation, and a no-op once a resize has claimed
    /// this gesture (see `continueSelectDrag`).
    private func beginOrContinueMove(from startPoint: CGPoint, to currentPoint: CGPoint) {
        if pendingMoveAnnotationID == nil {
            pendingMoveAnnotationID = annotationForMove(at: startPoint)
            selectedAnnotationID = pendingMoveAnnotationID
            pendingMoveAppliedDelta = .zero
        }

        guard let id = pendingMoveAnnotationID else { return }

        let totalDelta = CGSize(width: currentPoint.x - startPoint.x, height: currentPoint.y - startPoint.y)
        let incrementalDelta = CGSize(
            width: totalDelta.width - pendingMoveAppliedDelta.width,
            height: totalDelta.height - pendingMoveAppliedDelta.height
        )
        moveAnnotation(id: id, by: incrementalDelta)
        pendingMoveAppliedDelta = totalDelta
    }

    private func endMove() {
        pendingMoveAnnotationID = nil
        pendingMoveAppliedDelta = .zero
    }

    private func moveAnnotation(id: Annotation.ID, by delta: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = annotations[index].translated(by: delta)
    }

    /// Snapshots the currently selected annotation so `continueResize` has a
    /// stable, unmodified reference to re-derive from on every drag tick.
    private func beginResize(handle: ResizeHandle.Kind) {
        guard let id = selectedAnnotationID, let original = annotations.first(where: { $0.id == id }) else { return }
        pendingResizeHandle = handle
        pendingResizeOriginal = original
    }

    private func continueResize(to point: CGPoint) {
        guard let id = selectedAnnotationID,
              let handle = pendingResizeHandle,
              let original = pendingResizeOriginal,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = original.resized(handle: handle, to: point)
    }

    private func endResize() {
        pendingResizeHandle = nil
        pendingResizeOriginal = nil
    }
}
