import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private enum Layout {
        static let defaultSize = NSSize(width: 360, height: 38)
        static let minimumSize = NSSize(width: 360, height: 38)
        static let maximumSize = NSSize(width: 640, height: 120)
        static let screenMargin: CGFloat = 8
        static let targetSpacing: CGFloat = 8
    }

    private let model: TranslatorModel
    private let accessibility: AccessibilityTextController
    private let onRefresh: () -> Void
    private let onUpgrade: () -> Void
    private var window: NSPanel?
    private var userMovedWindow = false
    private var dragStartOrigin: CGPoint?
    private var resizeStartFrame: NSRect?

    init(model: TranslatorModel, accessibility: AccessibilityTextController, onRefresh: @escaping () -> Void, onUpgrade: @escaping () -> Void) {
        self.model = model
        self.accessibility = accessibility
        self.onRefresh = onRefresh
        self.onUpgrade = onUpgrade
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(near axFrame: CGRect?) {
        if window == nil {
            let contentView = TranslationOverlayView(
                model: model,
                onRefresh: onRefresh,
                onUpgrade: onUpgrade,
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

        let wasVisible = window?.isVisible == true
        if userMovedWindow, wasVisible {
            keepWindowInVisibleBounds()
        } else {
            positionWindow(near: axFrame)
        }

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
        guard !model.isUpgradeRequired else {
            onUpgrade()
            return
        }

        guard model.canApplyTranslation else {
            return
        }

        if accessibility.replaceFocusedText(with: model.translatedText) {
            model.recordAppliedTranslation()
            model.updateSourceText(model.translatedText)
        } else {
            model.statusText = String(localized: "Replace failed")
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

        let targetScreen = axFrame.flatMap(screenContainingAXFrame(_:))
        let screen = targetScreen ?? NSScreen.screens.first { screen in
            screen.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowSize = window.frame.size

        let targetFrame = axFrame.map { convertAXFrameToAppKit($0, on: screen, fallbackVisibleFrame: visibleFrame) }
        let frame = bestWindowFrame(
            windowSize: windowSize,
            near: targetFrame,
            within: visibleFrame,
            fallbackPoint: NSEvent.mouseLocation
        )

        window.setFrame(frame, display: true)
    }

    private func keepWindowInVisibleBounds() {
        guard let window else {
            return
        }

        window.setFrame(constrainedFrame(window.frame), display: true)
    }

    private func constrainedFrame(_ frame: NSRect, visibleFrame: NSRect? = nil) -> NSRect {
        let visibleFrame = visibleFrame ?? {
            let screen = NSScreen.screens.first { screen in
                screen.frame.intersects(frame)
            } ?? NSScreen.main
            return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        }()

        var constrained = frame
        constrained.size.width = clamp(constrained.width, min: Layout.minimumSize.width, max: min(Layout.maximumSize.width, visibleFrame.width - Layout.screenMargin * 2))
        constrained.size.height = clamp(constrained.height, min: Layout.minimumSize.height, max: min(Layout.maximumSize.height, visibleFrame.height - Layout.screenMargin * 2))
        constrained.origin.x = min(max(constrained.origin.x, visibleFrame.minX + Layout.screenMargin), visibleFrame.maxX - constrained.width - Layout.screenMargin)
        constrained.origin.y = min(max(constrained.origin.y, visibleFrame.minY + Layout.screenMargin), visibleFrame.maxY - constrained.height - Layout.screenMargin)
        return constrained
    }

    private func clamp(_ value: CGFloat, min minimumValue: CGFloat, max maximumValue: CGFloat) -> CGFloat {
        min(max(value, minimumValue), maximumValue)
    }

    private func bestWindowFrame(windowSize: NSSize, near targetFrame: CGRect?, within visibleFrame: CGRect, fallbackPoint: CGPoint) -> NSRect {
        guard let targetFrame else {
            let origin = CGPoint(
                x: fallbackPoint.x - windowSize.width / 2,
                y: fallbackPoint.y + Layout.targetSpacing
            )
            return constrainedFrame(NSRect(origin: origin, size: windowSize), visibleFrame: visibleFrame)
        }

        let candidates = [
            CGPoint(
                x: targetFrame.midX - windowSize.width / 2,
                y: targetFrame.maxY + Layout.targetSpacing
            ),
            CGPoint(
                x: targetFrame.midX - windowSize.width / 2,
                y: targetFrame.minY - windowSize.height - Layout.targetSpacing
            ),
            CGPoint(
                x: targetFrame.maxX + Layout.targetSpacing,
                y: targetFrame.midY - windowSize.height / 2
            ),
            CGPoint(
                x: targetFrame.minX - windowSize.width - Layout.targetSpacing,
                y: targetFrame.midY - windowSize.height / 2
            )
        ]

        let protectedTargetFrame = targetFrame.insetBy(dx: -Layout.targetSpacing, dy: -Layout.targetSpacing)

        let bestFrame = candidates
            .map { constrainedFrame(NSRect(origin: $0, size: windowSize), visibleFrame: visibleFrame) }
            .min { lhs, rhs in
                score(frame: lhs, avoiding: protectedTargetFrame, in: visibleFrame)
                    < score(frame: rhs, avoiding: protectedTargetFrame, in: visibleFrame)
            }

        return bestFrame ?? constrainedFrame(NSRect(origin: fallbackPoint, size: windowSize), visibleFrame: visibleFrame)
    }

    private func score(frame: CGRect, avoiding targetFrame: CGRect, in visibleFrame: CGRect) -> CGFloat {
        let overlapArea = frame.intersection(targetFrame).area
        let distance = CGFloat(hypot(frame.midX - targetFrame.midX, frame.midY - targetFrame.midY))
        let offscreenPenalty: CGFloat = visibleFrame.contains(frame) ? 0 : 10_000
        return overlapArea * 100 + distance + offscreenPenalty
    }

    private func screenContainingAXFrame(_ axFrame: CGRect) -> NSScreen? {
        let samplePoints = [
            CGPoint(x: axFrame.midX, y: axFrame.midY),
            CGPoint(x: axFrame.minX, y: axFrame.minY),
            CGPoint(x: axFrame.maxX, y: axFrame.maxY)
        ]

        return NSScreen.screens.first { screen in
            samplePoints.contains { screen.frame.contains($0) }
        }
    }

    private func convertAXFrameToAppKit(_ axFrame: CGRect, on screen: NSScreen?, fallbackVisibleFrame: CGRect) -> CGRect {
        let displayHeight = screen?.frame.maxY ?? fallbackVisibleFrame.maxY
        return CGRect(
            x: axFrame.origin.x,
            y: displayHeight - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }
}
