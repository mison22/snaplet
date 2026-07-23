import Foundation

/// Extra supersampling applied on top of the display's native
/// `backingScaleFactor` when capturing.
///
/// `standard` reproduces the previous behavior (native resolution only).
/// `high` and `maximum` render ScreenCaptureKit's output at 2x/3x that,
/// then let the annotation editor and Save/Copy downstream consumers work
/// from the larger source image, so exported screenshots stay sharp even
/// when heavily zoomed or projected.
enum CaptureResolution: Int, CaseIterable, Identifiable, Codable {
    case standard = 1
    case high = 2
    case maximum = 3

    var id: Int { rawValue }

    /// Multiplier applied to a display's native pixel dimensions.
    var supersampleFactor: CGFloat { CGFloat(rawValue) }

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High"
        case .maximum: return "Maximum"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "Native resolution"
        case .high: return "2x supersampled"
        case .maximum: return "3x supersampled"
        }
    }
}
