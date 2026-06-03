import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let model: TranslatorModel
    private let accessibility: AccessibilityTextController
    private let onRefresh: () -> Void
    private var window: NSPanel?
    private var userMovedWindow = false
    private var dragStartOrigin: CGPoint?

    init(model: TranslatorModel, accessibility: AccessibilityTextController, onRefresh: @escaping () -> Void) {
        self.model = model
        self.accessibility = accessibility
        self.onRefresh = onRefresh
    }

    func show(near axFrame: CGRect?) {
        userMovedWindow = false

        if window == nil {
            let contentView = TranslationOverlayView(
                model: model,
                onRefresh: onRefresh,
                onApply: { [weak self] in self?.applyTranslation() },
                onClose: { [weak self] in self?.hide() },
                onDrag: { [weak self] translation in self?.dragWindow(by: translation) },
                onDragEnded: { [weak self] in self?.finishDraggingWindow() }
            )

            let hostingView = NSHostingView(rootView: contentView)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 38),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            window = panel
        }

        positionWindow(near: axFrame)
        window?.orderFrontRegardless()
    }

    func hide() {
        model.disable()
        userMovedWindow = false
        dragStartOrigin = nil
        window?.orderOut(nil)
    }

    func applyTranslation() {
        guard model.canApplyTranslation else {
            return
        }

        accessibility.replaceFocusedText(with: model.translatedText)
        model.updateSourceText(model.translatedText)
    }

    private func dragWindow(by translation: CGSize) {
        guard let window else {
            return
        }

        if dragStartOrigin == nil {
            dragStartOrigin = window.frame.origin
        }

        guard let dragStartOrigin else {
            return
        }

        userMovedWindow = true
        window.setFrameOrigin(CGPoint(
            x: dragStartOrigin.x + translation.width,
            y: dragStartOrigin.y - translation.height
        ))
    }

    private func finishDraggingWindow() {
        dragStartOrigin = nil
    }

    private func positionWindow(near axFrame: CGRect?) {
        guard let window else {
            return
        }

        let screen = NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowSize = window.frame.size

        let targetFrame = axFrame.map { convertAXFrameToAppKit($0, visibleFrame: visibleFrame) }
        let anchorX = targetFrame?.midX ?? NSEvent.mouseLocation.x
        let anchorY = targetFrame?.maxY ?? NSEvent.mouseLocation.y

        var origin = CGPoint(
            x: anchorX - windowSize.width / 2,
            y: anchorY + 8
        )

        if origin.y + windowSize.height > visibleFrame.maxY {
            origin.y = max(visibleFrame.minY, (targetFrame?.minY ?? NSEvent.mouseLocation.y) - windowSize.height - 8)
        }

        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - windowSize.width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - windowSize.height - 8)

        window.setFrameOrigin(origin)
    }

    private func convertAXFrameToAppKit(_ axFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let displayHeight = NSScreen.screens.map(\.frame.maxY).max() ?? visibleFrame.maxY
        return CGRect(
            x: axFrame.origin.x,
            y: displayHeight - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )
    }
}
