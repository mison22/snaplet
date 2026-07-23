import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Central entry point for taking a screenshot in any of the three
/// `CaptureMode`s using ScreenCaptureKit.
///
/// Every call starts by verifying Screen Recording access via
/// `ScreenRecordingPermission`; if that check fails, `capture(_:)` returns
/// `nil` immediately without touching ScreenCaptureKit.
/// A screenshot at native pixel resolution, paired with the pixels-per-point
/// scale baked into its dimensions (display `backingScaleFactor` times any
/// `CaptureResolution` supersample factor).
///
/// Downstream consumers that size an `NSImage` in points (e.g. the Copy
/// path's pasteboard image) need this to avoid reporting the pixel count as
/// if it were the point size — which would make a receiving app request more
/// pixels than the image has and upscale it, reading as grainy.
struct CapturedImage {
    let cgImage: CGImage
    let scale: CGFloat
}

@MainActor
final class CaptureEngine {

    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    /// Captures a screenshot for the given mode.
    ///
    /// - Returns: The captured image at native (pixel) resolution together
    ///   with the pixels-per-point scale baked into those dimensions, or
    ///   `nil` if Screen Recording access is missing or the user cancelled
    ///   the selection (Esc).
    func capture(_ mode: CaptureMode) async -> CapturedImage? {
        guard ScreenRecordingPermission.requestIfNeededAndVerify() else {
            return nil
        }

        switch mode {
        case .fullScreen:
            return await captureFullScreen()
        case .window:
            return await captureWindow()
        case .area:
            return await captureArea()
        }
    }

    // MARK: - Full screen

    private func captureFullScreen() async -> CapturedImage? {
        guard let content = await shareableContent() else { return nil }

        // `NSScreen.main` (the screen holding the currently-focused window),
        // not the screen under the cursor: this is commonly invoked from the
        // status-item menu, where the cursor is necessarily on the main
        // screen's menu bar at the moment of the click regardless of which
        // screen the user actually means to capture. `.main` still tracks
        // whichever app/window last had keyboard focus, since opening a
        // status-item menu doesn't itself steal that.
        guard let activeScreen = NSScreen.main, let activeDisplayID = activeScreen.displayID,
              let display = content.displays.first(where: { $0.displayID == activeDisplayID }) else {
            NSLog("Snaplet: could not resolve SCDisplay for the active screen")
            return nil
        }

        let filter = SCContentFilter(display: display, excludingWindows: ownWindows(from: content))
        let configuration = SCStreamConfiguration()
        configuration.colorSpaceName = CGColorSpace.displayP3
        let scale = activeScreen.backingScaleFactor
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)

        return await capturedImage(filter: filter, configuration: configuration, baseScale: scale, context: "full-screen")
    }

    // MARK: - Window

    private func captureWindow() async -> CapturedImage? {
        guard let content = await shareableContent() else { return nil }

        let ownWindowIDs = Set(ownWindows(from: content).map(\.windowID))
        let candidates = content.windows.filter {
            !ownWindowIDs.contains($0.windowID) && $0.isOnScreen && $0.frame.width > 0 && $0.frame.height > 0
        }

        guard let chosen = await WindowSelectionOverlayWindow.present(windows: candidates) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: chosen)
        let configuration = SCStreamConfiguration()
        configuration.colorSpaceName = CGColorSpace.displayP3
        let scale = displayScaleFactor(containingQuartzFrame: chosen.frame)
        configuration.width = max(1, Int(chosen.frame.width * scale))
        configuration.height = max(1, Int(chosen.frame.height * scale))

        return await capturedImage(filter: filter, configuration: configuration, baseScale: scale, context: "window")
    }

    // MARK: - Area

    private func captureArea() async -> CapturedImage? {
        guard let selection = await RegionSelectionOverlayWindow.present() else {
            return nil
        }

        guard let content = await shareableContent() else { return nil }
        guard let displayID = selection.screen.displayID,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            NSLog("Snaplet: could not resolve SCDisplay for the selected screen")
            return nil
        }

        // The selection rect is in AppKit screen points; ScreenCaptureKit's
        // `sourceRect` expects the display's own top-left, Y-down point
        // space. So the rect must be made relative to the display's own
        // origin and flipped vertically — but NOT scaled to pixels, since
        // `sourceRect` (unlike `width`/`height`) is specified in points.
        let displayFrame = selection.screen.frame
        let localRect = selection.rect.offsetBy(dx: -displayFrame.origin.x, dy: -displayFrame.origin.y)
        let flippedY = displayFrame.height - localRect.origin.y - localRect.height
        let sourceRect = CGRect(x: localRect.origin.x, y: flippedY, width: localRect.width, height: localRect.height)

        let filter = SCContentFilter(display: display, excludingWindows: ownWindows(from: content))
        let configuration = SCStreamConfiguration()
        configuration.colorSpaceName = CGColorSpace.displayP3
        let scale = selection.screen.backingScaleFactor
        configuration.sourceRect = sourceRect
        configuration.width = max(1, Int((sourceRect.width * scale).rounded()))
        configuration.height = max(1, Int((sourceRect.height * scale).rounded()))

        return await capturedImage(filter: filter, configuration: configuration, baseScale: scale, context: "area")
    }

    // MARK: - Shared helpers

    private func shareableContent() async -> SCShareableContent? {
        do {
            return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            NSLog("Snaplet: failed to fetch shareable content: \(error)")
            return nil
        }
    }

    /// Snaplet's own windows (selection overlays, and any future annotation
    /// windows), so full-screen and area captures never include them.
    private func ownWindows(from content: SCShareableContent) -> [SCWindow] {
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter { $0.owningApplication?.processID == ownProcessID }
    }

    /// Captures via ScreenCaptureKit at `baseScale` (the display's native
    /// `backingScaleFactor`), then applies any extra `CaptureResolution`
    /// supersampling as a post-capture upscale -- see `ImageUpscaler`.
    private func capturedImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        baseScale: CGFloat,
        context: String
    ) async -> CapturedImage? {
        do {
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let supersampleFactor = settings.captureResolution.supersampleFactor
            guard let upscaled = ImageUpscaler.upscale(cgImage, factor: supersampleFactor) else {
                return CapturedImage(cgImage: cgImage, scale: baseScale)
            }
            return CapturedImage(cgImage: upscaled, scale: baseScale * supersampleFactor)
        } catch {
            NSLog("Snaplet: \(context) capture failed: \(error)")
            return nil
        }
    }

    /// Finds the backing scale factor for the `NSScreen` a Quartz-space
    /// rectangle (e.g. `SCWindow.frame`) falls on.
    private func displayScaleFactor(containingQuartzFrame quartzFrame: CGRect) -> CGFloat {
        let appKitRect = quartzFrame.convertedFromQuartzGlobalSpace()
        return NSScreen.screens.first { $0.frame.intersects(appKitRect) }?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
    }
}

extension NSScreen {
    /// The `CGDirectDisplayID` backing this screen, read from its device
    /// description dictionary (there is no direct AppKit accessor).
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

extension CGRect {
    /// Converts a rectangle from ScreenCaptureKit/Quartz's global display
    /// coordinate space (origin top-left of the main display, Y increasing
    /// downward) into AppKit's screen coordinate space (origin bottom-left
    /// of the main display, Y increasing upward).
    ///
    /// `SCWindow.frame` and other CoreGraphics window-list APIs use the
    /// Quartz space; `NSScreen.frame` uses the AppKit space. Mixing the two
    /// without this conversion silently produces vertically-flipped hit
    /// testing. Shared with `WindowSelectionOverlayWindow`.
    func convertedFromQuartzGlobalSpace() -> CGRect {
        let mainDisplayHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGRect(
            x: origin.x,
            y: mainDisplayHeight - origin.y - height,
            width: width,
            height: height
        )
    }
}
