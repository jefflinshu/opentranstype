import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let model: TranslatorModel
    private let onFinish: () -> Void
    private var window: NSWindow?

    init(model: TranslatorModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    func show() {
        if window == nil {
            let contentView = OnboardingView(
                model: model,
                onFinish: { [weak self] in
                    self?.complete()
                }
            )

            let hostingView = NSHostingView(rootView: contentView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.title = "OpenTransType"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: OnboardingView.didCompleteKey)
        window?.orderOut(nil)
        onFinish()
    }
}

struct OnboardingView: View {
    static let didCompleteKey = "didCompleteOnboarding"

    @ObservedObject var model: TranslatorModel
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                instructionsPage
                    .opacity(page == 0 ? 1 : 0)
                    .allowsHitTesting(page == 0)

                languagePage
                    .opacity(page == 1 ? 1 : 0)
                    .allowsHitTesting(page == 1)
            }
            .animation(.easeInOut(duration: 0.16), value: page)

            HStack {
                pageIndicator

                Spacer()

                if page == 0 {
                    Button("下一步") {
                        page = 1
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("开始使用") {
                        onFinish()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 420)
        .background(.regularMaterial)
    }

    private var instructionsPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "text.bubble")
                .font(.system(size: 42))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 8) {
                Text("边写边译")
                    .font(.largeTitle.weight(.semibold))

                Text("在任意 App 的输入框里输入文字，OpenTransType 会读取当前内容并显示译文。按下 ↓ 或浮窗里的向下箭头，就可以用译文覆盖原文。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingStepRow(iconName: "cursorarrow.rays", text: "右键输入框可手动唤出翻译浮窗")
                OnboardingStepRow(iconName: "keyboard.chevron.compact.down", text: "译文准备好后按 ↓ 直接替换")
                OnboardingStepRow(iconName: "lock.shield", text: "需要允许辅助功能权限才能读取和替换文本")
            }

            Spacer()
        }
        .padding(28)
    }

    private var languagePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 42))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 8) {
                Text("选择目标语言")
                    .font(.largeTitle.weight(.semibold))

                Text("选择你最常翻译到的语言。首次使用对应语言对时，系统可能会提示下载 Apple 本机翻译语言包。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("目标语言", selection: $model.selectedLanguage) {
                ForEach(TranslationLanguage.supported) { language in
                    Text(language.name).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)

            Text("当前默认：\(model.selectedLanguage.name)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(28)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<2) { index in
                Circle()
                    .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingStepRow: View {
    let iconName: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24)

            Text(text)
                .foregroundStyle(.primary)
        }
        .font(.callout)
    }
}
