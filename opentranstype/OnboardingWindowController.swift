import AppKit
import ApplicationServices
import SwiftUI
import Translation

@MainActor
final class OnboardingWindowController {
    private let model: TranslatorModel
    private let onFinish: () -> Void
    private var window: NSWindow?
    private var resizeObserver: NSObjectProtocol?

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
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 18
            hostingView.layer?.masksToBounds = true

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
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.center()
            WindowChrome.placeTrafficLightsInsidePanel(window)
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    WindowChrome.placeTrafficLightsInsidePanel(window)
                }
            }
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
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()
    @State private var languagePackState: LanguagePackState = .checking
    @State private var languageTask: Task<Void, Never>?

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
                        refreshAccessibilityTrust()
                        page = 1
                    }
                    .disabled(!isAccessibilityTrusted)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("开始使用") {
                        onFinish()
                    }
                    .disabled(!languagePackState.canContinue)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 420)
        .liquidGlassPanel(cornerRadius: 18)
        .onAppear {
            refreshAccessibilityTrust()
            checkLanguagePack()
        }
        .onChange(of: model.selectedLanguage) { _, _ in
            checkLanguagePack()
        }
        .onDisappear {
            languageTask?.cancel()
        }
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
                OnboardingStepRow(iconName: "lock.shield", text: accessibilityStatusText)
            }

            HStack(spacing: 10) {
                Button("打开辅助功能设置") {
                    requestAccessibilityPermission()
                }

                Button("重新检查") {
                    refreshAccessibilityTrust()
                }
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

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: languagePackState.iconName)
                        .foregroundStyle(languagePackState.iconColor)
                    Text(languagePackState.message)
                        .font(.callout.weight(.medium))
                }

                Text("检查示例语言对：\(sampleSourceLanguageName) → \(model.selectedLanguage.name)。实际使用时会按输入内容自动识别源语言。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(languagePackState.actionTitle) {
                        prepareLanguagePack()
                    }
                    .disabled(!languagePackState.canPrepare)

                    Button("重新检查") {
                        checkLanguagePack()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassPanel(cornerRadius: 10)

            Spacer()
        }
        .padding(28)
    }

    private var accessibilityStatusText: String {
        isAccessibilityTrusted ? "辅助功能权限已允许" : "需要允许辅助功能权限才能读取和替换文本"
    }

    private var sampleSourceLanguage: Locale.Language {
        if model.selectedLanguage.id == "en" {
            return Locale.Language(identifier: "zh-Hans")
        }

        return Locale.Language(identifier: "en")
    }

    private var sampleSourceLanguageName: String {
        model.selectedLanguage.id == "en" ? "简体中文" : "English"
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        refreshAccessibilityTrust()
    }

    private func refreshAccessibilityTrust() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    private func checkLanguagePack() {
        languageTask?.cancel()
        languagePackState = .checking
        let sourceLanguage = sampleSourceLanguage
        let targetLanguage = model.selectedLanguage.language

        languageTask = Task { @MainActor in
            let availability: LanguageAvailability
            if #available(macOS 26.4, *) {
                availability = LanguageAvailability(preferredStrategy: .lowLatency)
            } else {
                availability = LanguageAvailability()
            }

            let status = await availability.status(from: sourceLanguage, to: targetLanguage)
            guard !Task.isCancelled else {
                return
            }

            switch status {
            case .installed:
                languagePackState = .installed
            case .supported:
                languagePackState = .needsDownload
            case .unsupported:
                languagePackState = .unsupported
            @unknown default:
                languagePackState = .unsupported
            }
        }
    }

    private func prepareLanguagePack() {
        guard languagePackState.canPrepare else {
            return
        }

        languageTask?.cancel()
        languagePackState = .preparing
        let sourceLanguage = sampleSourceLanguage
        let targetLanguage = model.selectedLanguage.language

        languageTask = Task { @MainActor in
            do {
                let session: TranslationSession
                if #available(macOS 26.4, *) {
                    session = TranslationSession(
                        installedSource: sourceLanguage,
                        target: targetLanguage,
                        preferredStrategy: .lowLatency
                    )
                } else {
                    session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
                }

                try await session.prepareTranslation()
                guard !Task.isCancelled else {
                    return
                }

                checkLanguagePack()
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                languagePackState = .failed(error.localizedDescription)
            }
        }
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

private enum LanguagePackState: Equatable {
    case checking
    case installed
    case needsDownload
    case preparing
    case unsupported
    case failed(String)

    var canContinue: Bool {
        switch self {
        case .installed:
            return true
        case .checking, .needsDownload, .preparing, .unsupported, .failed:
            return false
        }
    }

    var canPrepare: Bool {
        switch self {
        case .needsDownload, .failed:
            return true
        case .checking, .installed, .preparing, .unsupported:
            return false
        }
    }

    var actionTitle: String {
        switch self {
        case .preparing:
            return "准备中..."
        case .installed:
            return "已准备好"
        default:
            return "下载语言包"
        }
    }

    var iconName: String {
        switch self {
        case .checking, .preparing:
            return "arrow.triangle.2.circlepath"
        case .installed:
            return "checkmark.circle.fill"
        case .needsDownload:
            return "arrow.down.circle.fill"
        case .unsupported, .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .installed:
            return .green
        case .needsDownload:
            return .accentColor
        case .unsupported, .failed:
            return .orange
        case .checking, .preparing:
            return .secondary
        }
    }

    var message: String {
        switch self {
        case .checking:
            return "正在检查语言包..."
        case .installed:
            return "语言包已安装，可以开始使用"
        case .needsDownload:
            return "这个语言包还没安装，请先下载"
        case .preparing:
            return "正在请求系统准备语言包"
        case .unsupported:
            return "系统暂不支持这个示例语言对"
        case .failed(let reason):
            return "语言包准备失败：\(reason)"
        }
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
