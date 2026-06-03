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
                        maxWidth: .infinity,
                        minHeight: Layout.singleLineTextHeight,
                        alignment: .topTrailing
                    )

                Button(action: applyOrRefresh) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(model.canApplyTranslation ? "覆盖原文" : "读取当前输入")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.leading, 13)
            .padding(.trailing, 16)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) {
                ResizeGrip()
                    .padding(.trailing, 5)
                    .padding(.bottom, 5)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                onResize(value.translation)
                            }
                            .onEnded { _ in
                                onResizeEnded()
                            }
                    )
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

private struct ResizeGrip: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.55))
            .rotationEffect(.degrees(-45))
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
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
