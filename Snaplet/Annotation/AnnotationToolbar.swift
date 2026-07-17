import AppKit
import SwiftUI

/// The floating tool/style pill shown above the canvas: tool picker, color
/// swatches, contextual arrow thickness, undo, and delete. Export (Save/Copy)
/// lives in `AnnotationActionBar`.
struct AnnotationToolbar: View {
    private static let swatchSize: CGFloat = 16
    private static let selectedSwatchBorderWidth: CGFloat = 2.5
    private static let lineWidthSwatchSize: CGFloat = 26
    private static let toolButtonWidth: CGFloat = 30
    private static let toolButtonHeight: CGFloat = 26

    @ObservedObject var viewModel: AnnotationEditorViewModel

    /// Thickness applies to arrows only, so the control appears when the Arrow
    /// tool is active or an arrow is currently selected for restyling.
    private var showsThickness: Bool {
        if viewModel.selectedTool == .arrow { return true }
        if let id = viewModel.selectedAnnotationID,
           case .arrow = viewModel.annotations.first(where: { $0.id == id }) {
            return true
        }
        return false
    }

    /// Font controls apply to text and bubbles, so they appear when either
    /// tool is active or a textual annotation is selected for restyling.
    private var showsTextStyle: Bool {
        if viewModel.selectedTool == .text || viewModel.selectedTool == .bubble { return true }
        if let id = viewModel.selectedAnnotationID,
           let selected = viewModel.annotations.first(where: { $0.id == id }),
           selected.textContent != nil {
            return true
        }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            toolGroup
            dividerBar
            colorGroup
            if showsThickness {
                dividerBar
                thicknessGroup
            }
            if showsTextStyle {
                dividerBar
                textStyleGroup
            }
            dividerBar
            historyGroup
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .animation(.easeInOut(duration: 0.15), value: showsThickness)
        .animation(.easeInOut(duration: 0.15), value: showsTextStyle)
    }

    // MARK: - Tools

    private var toolGroup: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                toolButton(tool)
            }
        }
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let isSelected = viewModel.selectedTool == tool
        return Button {
            viewModel.selectedTool = tool
            viewModel.cancelPendingGesture()
        } label: {
            Image(systemName: tool.symbolName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: Self.toolButtonWidth, height: Self.toolButtonHeight)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tool.displayName)
    }

    // MARK: - Colors

    private var colorGroup: some View {
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
    }

    private func swatch(for color: NSColor) -> some View {
        let isSelected = color == viewModel.selectedColor
        return Circle()
            .fill(Color(nsColor: color))
            .frame(width: Self.swatchSize, height: Self.swatchSize)
            .overlay(
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: isSelected ? Self.selectedSwatchBorderWidth : 0)
                    .padding(-2.5)
            )
            .onTapGesture {
                viewModel.setColor(color)
            }
    }

    // MARK: - Thickness

    private var thicknessGroup: some View {
        HStack(spacing: 6) {
            ForEach(AppConstants.annotationLineWidths, id: \.self) { lineWidth in
                lineWidthSwatch(for: lineWidth)
            }
        }
    }

    private func lineWidthSwatch(for lineWidth: CGFloat) -> some View {
        let isSelected = lineWidth == viewModel.selectedLineWidth
        // Stored widths are native screenshot pixels (up to ~42), too tall to
        // draw literally; map them to a bounded preview height that still
        // conveys relative thickness.
        let maxWidth = AppConstants.annotationLineWidths.max() ?? lineWidth
        let previewHeight = 2 + (lineWidth / maxWidth) * (Self.lineWidthSwatchSize - 12)
        return RoundedRectangle(cornerRadius: previewHeight / 2)
            .fill(Color.primary)
            .frame(width: Self.lineWidthSwatchSize - 10, height: previewHeight)
            .frame(width: Self.lineWidthSwatchSize, height: Self.lineWidthSwatchSize)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.setLineWidth(lineWidth)
            }
            .help("\(Int(lineWidth)) px")
    }

    // MARK: - Text style

    private var textStyleGroup: some View {
        HStack(spacing: 6) {
            Menu {
                Button("System") { viewModel.setFontName(nil) }
                Divider()
                ForEach(AppConstants.annotationFontNames, id: \.self) { name in
                    Button(name) { viewModel.setFontName(name) }
                }
            } label: {
                Text(viewModel.selectedFontName ?? "System")
                    .lineLimit(1)
                    .frame(minWidth: 76, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Font")

            Menu {
                ForEach(AppConstants.annotationFontSizes, id: \.self) { size in
                    Button("\(Int(size)) px") { viewModel.setFontSize(size) }
                }
            } label: {
                Text("\(Int(viewModel.selectedFontSize)) px")
                    .lineLimit(1)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Font size")
        }
    }

    // MARK: - History

    private var historyGroup: some View {
        HStack(spacing: 4) {
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")

            Button {
                viewModel.deleteSelectedAnnotation()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.selectedAnnotationID == nil)
            .help("Delete Selected")
        }
    }

    private var dividerBar: some View {
        Divider().frame(height: 20)
    }

    // MARK: - Color panel

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
