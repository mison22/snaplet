import Foundation

/// The tool the user has selected in the annotation toolbar.
enum AnnotationTool: CaseIterable, Identifiable, Hashable {
    case select
    case arrow
    case text
    case bubble

    var id: Self { self }

    var displayName: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .bubble: return "Bubble"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .bubble: return "bubble.left"
        }
    }
}
