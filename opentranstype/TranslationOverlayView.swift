import SwiftUI
import AppKit

struct TranslationOverlayView: View {
    @ObservedObject var model: TranslatorModel
    let onRefresh: () -> Void
    let onApply: () -> Void
    let onClose: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            LanguagePopUpButton(selection: $model.selectedLanguage)
                .frame(width: 44, height: 21)
                .help("选择目标语言")

            Spacer(minLength: 8)

            Text(resultText)
                .font(.callout)
                .foregroundStyle(model.translatedText.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .frame(maxWidth: 248, alignment: .trailing)

            Button(action: applyOrRefresh) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(model.canApplyTranslation ? "覆盖原文" : "读取当前输入")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 360, height: 38)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
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

        if let index = TranslationLanguage.supported.firstIndex(of: selection),
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

        if let index = TranslationLanguage.supported.firstIndex(of: selection) {
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
            let index = sender.indexOfSelectedItem
            guard TranslationLanguage.supported.indices.contains(index) else {
                return
            }

            parent.selection = TranslationLanguage.supported[index]
            sender.title = parent.selection.shortName
        }
    }
}
