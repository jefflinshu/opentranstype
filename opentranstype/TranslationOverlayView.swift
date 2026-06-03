import SwiftUI
import AppKit

struct TranslationOverlayView: View {
    private enum Layout {
        static let cornerRadius: CGFloat = 14
        static let minHeight: CGFloat = 38
        static let singleLineTextHeight: CGFloat = 22
    }

    @ObservedObject var model: TranslatorModel
    let onRefresh: () -> Void
    let onApply: () -> Void
    let onClose: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void
    let onResize: (CGSize) -> Void
    let onResizeEnded: () -> Void

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 10) {
                DragHandle(onDrag: onDrag, onDragEnded: onDragEnded)
                    .frame(width: 16, height: 24)
                    .help("拖拽移动工具栏")

                LanguagePopUpButton(selection: $model.selectedLanguage)
                    .frame(width: 46, height: 22)
                    .help("选择目标语言")

                Text(resultText)
                    .font(.callout)
                    .foregroundStyle(model.translatedText.isEmpty ? .secondary : .primary)
                    .lineLimit(proxy.size.height > 58 ? 3 : 1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: Layout.singleLineTextHeight,
                        alignment: .topTrailing
                    )
                    .clipped()
                    .layoutPriority(0)

                Button(action: applyOrRefresh) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(model.canApplyTranslation ? "覆盖原文" : "读取当前输入")
                .layoutPriority(2)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("关闭")
                .layoutPriority(2)
            }
            .padding(.leading, 13)
            .padding(.trailing, 38)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                ResizeGrip(onResize: onResize, onResizeEnded: onResizeEnded)
                    .frame(width: 28, height: 28)
                    .padding(.trailing, 2)
                    .padding(.bottom, 2)
                    .help("拖拽调整工具栏大小")
            }
        }
        .frame(minWidth: 360, minHeight: Layout.minHeight)
        .liquidGlassPanel(cornerRadius: Layout.cornerRadius)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }

    private var resultText: String {
        if model.translatedText.isEmpty {
            return model.statusText
        }

        return model.translatedText
    }

    private func applyOrRefresh() {
        if model.canApplyTranslation {
            onApply()
        } else {
            onRefresh()
        }
    }
}

private struct DragHandle: NSViewRepresentable {
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: DragHandleView, context: Context) {
        view.onDrag = onDrag
        view.onDragEnded = onDragEnded
    }

    final class DragHandleView: NSView {
        var onDrag: ((CGSize) -> Void)?
        var onDragEnded: (() -> Void)?
        private var dragStartLocation: NSPoint?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        override func mouseDown(with event: NSEvent) {
            dragStartLocation = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            NSCursor.closedHand.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStartLocation else {
                return
            }

            let currentLocation = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            onDrag?(CGSize(
                width: currentLocation.x - dragStartLocation.x,
                height: dragStartLocation.y - currentLocation.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            dragStartLocation = nil
            onDragEnded?()
            NSCursor.openHand.set()
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setFill()

            for row in 0..<3 {
                for column in 0..<2 {
                    let rect = NSRect(
                        x: bounds.midX - 4 + CGFloat(column * 5),
                        y: bounds.midY - 6 + CGFloat(row * 5),
                        width: 2,
                        height: 2
                    )
                    NSBezierPath(ovalIn: rect).fill()
                }
            }
        }
    }
}

private struct ResizeGrip: NSViewRepresentable {
    let onResize: (CGSize) -> Void
    let onResizeEnded: () -> Void

    func makeNSView(context: Context) -> ResizeGripView {
        let view = ResizeGripView()
        view.onResize = onResize
        view.onResizeEnded = onResizeEnded
        return view
    }

    func updateNSView(_ view: ResizeGripView, context: Context) {
        view.onResize = onResize
        view.onResizeEnded = onResizeEnded
    }

    final class ResizeGripView: NSView {
        var onResize: ((CGSize) -> Void)?
        var onResizeEnded: (() -> Void)?
        private var dragStartLocation: NSPoint?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func mouseDown(with event: NSEvent) {
            dragStartLocation = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStartLocation else {
                return
            }

            let currentLocation = window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
            onResize?(CGSize(
                width: currentLocation.x - dragStartLocation.x,
                height: dragStartLocation.y - currentLocation.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            dragStartLocation = nil
            onResizeEnded?()
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()

            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round

            let startX = bounds.maxX - 12
            let startY = bounds.minY + 6
            for offset in stride(from: 0, through: 8, by: 4) {
                path.move(to: NSPoint(x: startX + CGFloat(offset), y: startY))
                path.line(to: NSPoint(x: bounds.maxX - 6, y: startY + CGFloat(offset)))
            }

            path.stroke()
        }
    }
}

struct LanguagePopUpButton: NSViewRepresentable {
    @Binding var selection: TranslationLanguage

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = context.coordinator
        button.action = #selector(Coordinator.languageChanged(_:))
        button.autoenablesItems = false
        reloadItems(in: button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if button.numberOfItems != TranslationLanguage.supported.count {
            reloadItems(in: button)
        }

        if let index = TranslationLanguage.supported.firstIndex(where: { $0.id == selection.id }),
           button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
        button.title = selection.shortName
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func reloadItems(in button: NSPopUpButton) {
        button.removeAllItems()
        for language in TranslationLanguage.supported {
            button.addItem(withTitle: language.shortName)
            button.lastItem?.representedObject = language.id
            button.lastItem?.toolTip = language.name
        }

        if let index = TranslationLanguage.supported.firstIndex(where: { $0.id == selection.id }) {
            button.selectItem(at: index)
            button.title = selection.shortName
        }
    }

    final class Coordinator: NSObject {
        var parent: LanguagePopUpButton

        init(parent: LanguagePopUpButton) {
            self.parent = parent
        }

        @objc func languageChanged(_ sender: NSPopUpButton) {
            guard let languageID = sender.selectedItem?.representedObject as? String,
                  let language = TranslationLanguage.language(withID: languageID) else {
                return
            }

            parent.selection = language
            sender.title = parent.selection.shortName
        }
    }
}
