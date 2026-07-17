import AppKit
import SwiftUI

/// The editor's export controls (Copy and Save), shown bottom-right over the
/// matte. On success a brief confirmation flashes and the window closes; on
/// failure the window stays open with an alert. Kept separate from the
/// tool/style pill so each surface has one clear job.
struct AnnotationActionBar: View {

    /// How long the "Saved"/"Copied" confirmation flashes before the editor
    /// window auto-closes.
    private static let confirmationDuration = Duration.seconds(1.0)

    /// The original, native-resolution capture. Save/Copy always flatten this
    /// image, never a scaled preview, so exported output matches the screen's
    /// native pixel dimensions.
    let baseImage: CGImage
    @ObservedObject var viewModel: AnnotationEditorViewModel
    let onRequestClose: () -> Void

    @State private var saveErrorMessage: String?
    @State private var showsSaveError = false
    @State private var confirmationMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            if let confirmationMessage {
                Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
                    .transition(.opacity)
            }

            Button("Copy", action: copyToPasteboard)
                .controlSize(.large)

            Button("Save", action: save)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
        }
        .animation(.easeInOut(duration: 0.2), value: confirmationMessage)
        .alert("Couldn't Save Screenshot", isPresented: $showsSaveError, presenting: saveErrorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Save

    private func save() {
        do {
            try AppSettings.shared.ensureSaveDirectoryExists()
            guard let flattened = AnnotationRenderer.flatten(base: baseImage, annotations: viewModel.annotations) else {
                throw AnnotationExportError.flattenFailed
            }
            guard let pngData = Self.pngData(for: flattened) else {
                throw AnnotationExportError.encodeFailed
            }

            let formatter = DateFormatter()
            formatter.dateFormat = AppConstants.filenameDateFormat
            let filename = "\(formatter.string(from: Date())).\(AppConstants.imageFileExtension)"
            let destination = AppSettings.shared.saveDirectory.appendingPathComponent(filename)

            try pngData.write(to: destination, options: .atomic)
            confirmThenClose("Saved")
        } catch {
            saveErrorMessage = error.localizedDescription
            showsSaveError = true
        }
    }

    private static func pngData(for image: CGImage) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        return bitmapRep.representation(using: .png, properties: [:])
    }

    // MARK: - Copy

    private func copyToPasteboard() {
        guard let flattenedImage = AnnotationRenderer.flattenToNSImage(base: baseImage, annotations: viewModel.annotations) else {
            saveErrorMessage = "Couldn't render the annotated screenshot."
            showsSaveError = true
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([flattenedImage])
        confirmThenClose("Copied")
    }

    // MARK: - Confirmation

    /// Flashes `message`, then closes the editor window once it has been
    /// visible long enough to read.
    private func confirmThenClose(_ message: String) {
        confirmationMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: Self.confirmationDuration)
            onRequestClose()
        }
    }
}

private enum AnnotationExportError: LocalizedError {
    case flattenFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .flattenFailed:
            return "Couldn't render the annotated screenshot."
        case .encodeFailed:
            return "Couldn't encode the screenshot as PNG."
        }
    }
}
