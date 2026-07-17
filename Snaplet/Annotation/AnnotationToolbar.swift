import AppKit
import SwiftUI

/// Toolbar shown above the annotation canvas: tool picker, color swatches,
/// undo, and the Save/Copy actions that flatten and export the annotated
/// screenshot.
struct AnnotationToolbar: View {
    private static let swatchSize: CGFloat = 20
    private static let selectedSwatchBorderWidth: CGFloat = 2
    private static let lineWidthSwatchSize: CGFloat = 28

    /// The original, native-resolution capture. Save/Copy always flatten
    /// this image, never a scaled preview, so exported output matches the
    /// screen's native pixel dimensions.
    let baseImage: CGImage
    @ObservedObject var viewModel: AnnotationEditorViewModel

    /// Closes the editor window. Invoked after a successful Save or Copy so
    /// the preview dismisses itself once the screenshot is exported.
    let onRequestClose: () -> Void

    /// How long the "Saved"/"Copied" confirmation flashes before the editor
    /// window auto-closes.
    private static let confirmationDuration = Duration.seconds(1.0)

    @State private var saveErrorMessage: String?
    @State private var showsSaveError = false

    /// Brief "Saved"/"Copied" confirmation shown after a successful action;
    /// `nil` hides it. Set via `confirmThenClose(_:)`.
    @State private var confirmationMessage: String?

    var body: some View {
        HStack(spacing: 16) {
            Picker("Tool", selection: $viewModel.selectedTool) {
                ForEach(AnnotationTool.allCases) { tool in
                    Label(tool.displayName, systemImage: tool.symbolName).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .onChange(of: viewModel.selectedTool) { _, _ in
                viewModel.cancelPendingGesture()
            }

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                ForEach(AppConstants.annotationPalette, id: \.self) { color in
                    swatch(for: color)
                }

                Button {
                    presentColorPanel()
                } label: {
                    Image(systemName: "paintpalette")
                }
                .buttonStyle(.borderless)
                .help("More colors…")
            }

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                ForEach(AppConstants.annotationLineWidths, id: \.self) { lineWidth in
                    lineWidthSwatch(for: lineWidth)
                }
            }

            Divider().frame(height: 20)

            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .help("Undo")

            Button {
                viewModel.deleteSelectedAnnotation()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(viewModel.selectedAnnotationID == nil)
            .help("Delete Selected")

            Spacer()

            if let confirmationMessage {
                Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                    .transition(.opacity)
            }

            Button("Copy") {
                copyToPasteboard()
            }

            Button("Save") {
                save()
            }
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(8)
        .animation(.easeInOut(duration: 0.2), value: confirmationMessage)
        .alert("Couldn't Save Screenshot", isPresented: $showsSaveError, presenting: saveErrorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func swatch(for color: NSColor) -> some View {
        let isSelected = color == viewModel.selectedColor
        return Circle()
            .fill(Color(nsColor: color))
            .frame(width: Self.swatchSize, height: Self.swatchSize)
            .overlay(
                Circle().stroke(Color.primary, lineWidth: isSelected ? Self.selectedSwatchBorderWidth : 0)
            )
            .onTapGesture {
                viewModel.setColor(color)
            }
    }

    private func lineWidthSwatch(for lineWidth: CGFloat) -> some View {
        let isSelected = lineWidth == viewModel.selectedLineWidth
        // The stored widths are native screenshot pixels (up to ~42), far too
        // tall to draw literally inside the toolbar. Map them to a bounded
        // preview height that still shows their relative thickness.
        let maxWidth = AppConstants.annotationLineWidths.max() ?? lineWidth
        let previewHeight = 2 + (lineWidth / maxWidth) * (Self.lineWidthSwatchSize - 10)
        return RoundedRectangle(cornerRadius: previewHeight / 2)
            .fill(Color.primary)
            .frame(width: Self.lineWidthSwatchSize - 8, height: previewHeight)
            .frame(width: Self.lineWidthSwatchSize, height: Self.lineWidthSwatchSize)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.setLineWidth(lineWidth)
            }
            .help("\(Int(lineWidth)) px")
    }

    private func presentColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(ColorPanelTarget.shared)
        panel.setAction(#selector(ColorPanelTarget.colorPanelDidChangeColor(_:)))
        ColorPanelTarget.shared.onColorChange = { color in
            viewModel.setColor(color)
        }
        panel.color = viewModel.selectedColor
        panel.makeKeyAndOrderFront(nil)
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

    /// Flashes `message` in the toolbar, then closes the editor window once
    /// the confirmation has been visible long enough to read.
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

/// `NSColorPanel` drives its target/action via Objective-C selectors, which
/// requires an `NSObject` subclass -- a plain closure can't be the target.
/// This singleton bridges the panel's `-changeColor:` callback back into a
/// Swift closure supplied by whichever `AnnotationToolbar` last opened the
/// panel.
private final class ColorPanelTarget: NSObject {
    static let shared = ColorPanelTarget()

    var onColorChange: ((NSColor) -> Void)?

    @objc func colorPanelDidChangeColor(_ sender: NSColorPanel) {
        onColorChange?(sender.color)
    }
}
