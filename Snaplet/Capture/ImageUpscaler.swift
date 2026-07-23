import CoreImage

/// Post-capture supersampling via a high-quality Lanczos resample.
///
/// `SCScreenshotManager.captureImage` sizes its output canvas exactly to the
/// requested `SCStreamConfiguration.width`/`height`, but for a *cropped*
/// capture (an `Area` selection's `sourceRect`, or an independent `Window`)
/// asking for more pixels than the source's native resolution doesn't
/// reliably render extra detail into that canvas -- it can leave the excess
/// blank instead. Capturing at native resolution and upscaling afterward
/// sidesteps that: it always produces a fully-painted image at the target
/// size, regardless of what ScreenCaptureKit does or doesn't support for a
/// given capture mode.
enum ImageUpscaler {
    private static let context = CIContext()

    /// Returns `image` scaled up by `factor`, or `nil` if the resample
    /// failed (caller should fall back to the original image).
    static func upscale(_ image: CGImage, factor: CGFloat) -> CGImage? {
        guard factor > 1 else { return image }

        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(factor, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let output = filter.outputImage else { return nil }

        let targetRect = CGRect(
            x: 0,
            y: 0,
            width: (CGFloat(image.width) * factor).rounded(),
            height: (CGFloat(image.height) * factor).rounded()
        )
        return context.createCGImage(output, from: targetRect, format: .RGBA8, colorSpace: image.colorSpace)
    }
}
