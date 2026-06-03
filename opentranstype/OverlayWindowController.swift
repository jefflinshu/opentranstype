import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private enum Layout {
        static let defaultSize = NSSize(width: 360, height: 38)
        static let minimumSize = NSSize(width: 360, height: 38)
        static let maximumSize = NSSize(width: 640, height: 120)
    }

    private let model: TranslatorModel
    private let accessibility: AccessibilityTextController
    private let onRefresh: () -> Void
    private var window: NSPanel?
    private var userMovedWindow = false
    private var dragStartOrigin: CGPoint?
    private var resizeStartFrame: NSRect?

    init(model: TranslatorModel, accessibility: AccessibilityTextController, onRefresh: @escaping () -> Void) {
        self.model = model
        self.accessibility = accessibility
        self.onRefresh = onRefresh
    }

    var isVisible: Bool {
        window?.isVisible == true
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
                onDragEnded: { [weak self] in self?.finishDraggingWindow() },
                onResize: { [weak self] translation in self?.resizeWindow(by: translation) },
                onResizeEnded: { [weak self] in self?.finishResizingWindow() }
            )

            let hostingView = NSHostingView(rootView: contentView)
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Layout.defaultSize),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.contentView = hostingView
            panel.minSize = Layout.minimumSize
            panel.maxSize = Layout.maximumSize
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = false
            window = panel
        }

        positionWindow(near: axFrame)
        window?.orderFrontRegardless()
    }

    func hide() {
        model.disable()
        userMovedWindow = false
        dragStartOrigin = nil
        resizeStartFrame = nil
        window?.orderOut(nil)
    }

    func applyTranslation() {
        guard model.canApplyTranslation else {
            return
        }

        if accessibility.replaceFocusedText(with: model.translatedText) {
            model.recordAppliedTranslation()
            model.updateSourceText(model.translatedText)
        } else {
            model.statusText = "替换失败"
        }
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

    private func resizeWindow(by translation: CGSize) {
        guard let window else {
            return
        }

        if resizeStartFrame == nil {
            resizeStartFrame = window.frame
        }

        guard let resizeStartFrame else {
            return
        }

        userMovedWindow = true
        let width = clamp(resizeStartFrame.width + translation.width, min: Layout.minimumSize.width, max: Layout.maximumSize.width)
        let height = clamp(resizeStartFrame.height + translation.height, min: Layout.minimumSize.height, max: Layout.maximumSize.height)
        let newFrame = NSRect(
            x: resizeStartFrame.minX,
            y: resizeStartFrame.maxY - height,
            width: width,
            height: height
        )

        window.setFrame(constrainedFrame(newFrame), display: true)
    }

    private func finishResizingWindow() {
        resizeStartFrame = nil
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

    private func constrainedFrame(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { screen in
            screen.frame.intersects(frame)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var constrained = frame
        constrained.size.width = clamp(constrained.width, min: Layout.minimumSize.width, max: min(Layout.maximumSize.width, visibleFrame.width - 16))
        constrained.size.height = clamp(constrained.height, min: Layout.minimumSize.height, max: min(Layout.maximumSize.height, visibleFrame.height - 16))
        constrained.origin.x = min(max(constrained.origin.x, visibleFrame.minX + 8), visibleFrame.maxX - constrained.width - 8)
        constrained.origin.y = min(max(constrained.origin.y, visibleFrame.minY + 8), visibleFrame.maxY - constrained.height - 8)
        return constrained
    }

    private func clamp(_ value: CGFloat, min minimumValue: CGFloat, max maximumValue: CGFloat) -> CGFloat {
        min(max(value, minimumValue), maximumValue)
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
