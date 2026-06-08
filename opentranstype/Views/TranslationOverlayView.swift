import SwiftUI
import AppKit

struct TranslationOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let cornerRadius: CGFloat = 14
        static let minHeight: CGFloat = 38
        static let singleLineTextHeight: CGFloat = 22
    }

    @ObservedObject var model: TranslatorModel
    let onRefresh: () -> Void
    let onUpgrade: () -> Void
    let onApply: () -> Void
    let onClose: () -> Void
    let onManageLanguages: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void
    let onResize: (CGSize) -> Void
    let onResizeEnded: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isExpanded = proxy.size.height > 58

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    DragHandle(onDrag: onDrag, onDragEnded: onDragEnded)
                        .frame(width: 16, height: 24)
                        .help(String(localized: "Drag to move toolbar"))

                    LanguagePopUpButton(selection: $model.selectedLanguage, onManageLanguages: onManageLanguages)
                        .frame(width: 46, height: 22)
                        .help(String(localized: "Choose target language"))

                    if isExpanded {
                        Spacer(minLength: 8)
                    } else {
                        resultTextView(lineLimit: 1)
                    }

                    Button(action: applyOrRefresh) {
                        Image(systemName: model.isUpgradeRequired ? "crown.fill" : "arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(toolbarButtonHelp)
                    .layoutPriority(2)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Close"))
                    .layoutPriority(2)
                }

                if isExpanded {
                    resultTextView(lineLimit: 3)
                        .padding(.leading, 26)
                }
            }
            .padding(.leading, 13)
            .padding(.trailing, 38)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottomTrailing) {
                ResizeGrip(onResize: onResize, onResizeEnded: onResizeEnded)
                    .frame(width: 28, height: 28)
                    .padding(.trailing, 2)
                    .padding(.bottom, 2)
                    .help(String(localized: "Drag to resize toolbar"))
            }
        }
        .frame(minWidth: 360, minHeight: Layout.minHeight)
        .liquidGlassPanel(cornerRadius: Layout.cornerRadius)
        .shadow(color: shadowColor, radius: 8, x: 0, y: 3)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.28 : 0.06)
    }

    private var resultText: String {
        if model.translatedText.isEmpty {
            return model.statusText
        }

        return model.translatedText
    }

    private func resultTextView(lineLimit: Int) -> some View {
        Text(resultText)
            .font(.callout)
            .foregroundStyle(model.translatedText.isEmpty ? .secondary : .primary)
            .lineLimit(lineLimit)
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
    }

    private func applyOrRefresh() {
        if model.isUpgradeRequired {
            onUpgrade()
            return
        }

        if model.canApplyTranslation {
            onApply()
        } else {
            onRefresh()
        }
    }

    private var toolbarButtonHelp: String {
        if model.isUpgradeRequired {
            return String(localized: "Upgrade to continue")
        }

        return model.canApplyTranslation ? String(localized: "Replace original text") : String(localized: "Read current input")
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
    private static let manageSentinel = "__manage_languages__"

    @ObservedObject private var languageCatalog = TranslationLanguageCatalog.shared
    @Binding var selection: TranslationLanguage
    var onManageLanguages: () -> Void = {}

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = context.coordinator
        button.action = #selector(Coordinator.languageChanged(_:))
        button.autoenablesItems = false
        // Keep the button showing the compact short name even though the menu items use full
        // names. Without this, NSPopUpButton mirrors the selected item's (full-name) title.
        button.cell.map { ($0 as? NSPopUpButtonCell)?.usesItemFromMenu = false }
        languageCatalog.loadIfNeeded()
        reloadItems(in: button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if currentLanguageIDs(in: button) != menuLanguages.map(\.id) {
            reloadItems(in: button)
        }

        if let index = menuLanguages.firstIndex(where: { $0.id == selection.id }),
           button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
        applyButtonTitle(button)
    }

    // Show the short name on the compact toolbar button. usesItemFromMenu = false stops the
    // popup from overwriting this with the selected menu item's full-name title.
    fileprivate func applyButtonTitle(_ button: NSPopUpButton) {
        guard let cell = button.cell as? NSPopUpButtonCell else {
            button.title = selection.shortName
            return
        }

        cell.usesItemFromMenu = false
        cell.menuItem = NSMenuItem(title: selection.shortName, action: nil, keyEquivalent: "")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    // Only languages whose pack is installed. Always include the current selection so the
    // toolbar never shows a blank title even if its pack check hasn't completed yet.
    private var menuLanguages: [TranslationLanguage] {
        var languages = languageCatalog.installedLanguages
        if !languages.contains(where: { $0.id == selection.id }) {
            languages.append(selection)
            languages.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return languages
    }

    private func reloadItems(in button: NSPopUpButton) {
        button.removeAllItems()
        for language in menuLanguages {
            button.addItem(withTitle: language.name)
            button.lastItem?.representedObject = language.id
            button.lastItem?.toolTip = language.name
        }

        button.menu?.addItem(.separator())
        let manageItem = NSMenuItem(title: String(localized: "Download languages…"), action: nil, keyEquivalent: "")
        manageItem.representedObject = Self.manageSentinel
        button.menu?.addItem(manageItem)

        if let index = menuLanguages.firstIndex(where: { $0.id == selection.id }) {
            button.selectItem(at: index)
        }
        applyButtonTitle(button)
    }

    private func currentLanguageIDs(in button: NSPopUpButton) -> [String] {
        button.itemArray.compactMap { $0.representedObject as? String }
            .filter { $0 != Self.manageSentinel }
    }

    final class Coordinator: NSObject {
        var parent: LanguagePopUpButton

        init(parent: LanguagePopUpButton) {
            self.parent = parent
        }

        @objc func languageChanged(_ sender: NSPopUpButton) {
            guard let representedID = sender.selectedItem?.representedObject as? String else {
                return
            }

            if representedID == LanguagePopUpButton.manageSentinel {
                // Reselect the current language so the menu doesn't stick on the action item.
                if let index = sender.itemArray.firstIndex(where: { $0.representedObject as? String == parent.selection.id }) {
                    sender.selectItem(at: index)
                }
                parent.applyButtonTitle(sender)
                parent.onManageLanguages()
                return
            }

            guard let language = TranslationLanguageCatalog.shared.language(withID: representedID) else {
                return
            }

            parent.selection = language
            parent.applyButtonTitle(sender)
        }
    }
}
