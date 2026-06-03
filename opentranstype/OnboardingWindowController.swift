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
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.title = "OpenTransType"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = false
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 820, height: 600)
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
        ZStack {
            OnboardingBackdropView()
                .blur(radius: 1)

            Color.black.opacity(0.18)

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
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("开始使用") {
                            onFinish()
                        }
                        .disabled(!languagePackState.canContinue)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 36)
            }
            .frame(width: 540, height: 560)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.secondary.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 18)
        }
        .ignoresSafeArea()
        .frame(minWidth: 820, minHeight: 600)
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
        VStack(alignment: .leading, spacing: 28) {
            OnboardingAppMark()
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("欢迎使用")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.tint)

                Text("OpenTransType")
                    .font(.largeTitle.weight(.bold))
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 22) {
                OnboardingStepRow(iconName: "cursorarrow.rays", text: "在任意 App 的输入框里输入文字，并自动显示译文。")
                OnboardingStepRow(iconName: "keyboard.chevron.compact.down", text: "译文准备好后，按 ↓ 或点击浮窗按钮直接替换原文。")
                OnboardingStepRow(iconName: "lock.shield", text: accessibilityStatusText)
            }

            HStack(spacing: 12) {
                Button("打开辅助功能设置") {
                    requestAccessibilityPermission()
                }

                Button("重新检查") {
                    refreshAccessibilityTrust()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 64)
        .padding(.top, 54)
    }

    private var languagePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingAppMark()
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("选择目标语言")
                    .font(.largeTitle.weight(.bold))

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
                    .buttonStyle(.bordered)

                    Button("重新检查") {
                        checkLanguagePack()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer()
        }
        .padding(.horizontal, 64)
        .padding(.top, 54)
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

private struct OnboardingBackdropView: View {
    var body: some View {
        NavigationSplitView {
            List(selection: .constant("stats")) {
                Section("OpenTransType") {
                    Label("数据统计", systemImage: "chart.bar.xaxis")
                        .tag("stats")
                    Label("历史记录", systemImage: "clock.arrow.circlepath")
                        .tag("history")
                    Label("设置", systemImage: "gearshape")
                        .tag("settings")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(230)
        } detail: {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("数据统计")
                        .font(.system(size: 34, weight: .bold))

                    Spacer()

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("搜索")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .frame(width: 260, height: 44)
                    .background(.thinMaterial, in: Capsule())
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 18),
                    GridItem(.flexible(), spacing: 18)
                ], spacing: 18) {
                    ForEach(["翻译次数", "原文字数", "译文字数", "平均长度"], id: \.self) { title in
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.secondary.opacity(0.10))
                                .frame(height: 96)

                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Spacer()
            }
            .padding(.top, 64)
            .padding(.horizontal, 44)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.purple)
        .disabled(true)
    }
}

private struct OnboardingAppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.17, green: 0.18, blue: 0.32),
                            Color(red: 0.08, green: 0.09, blue: 0.17)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)

            Image(systemName: "character.bubble.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

private struct OnboardingStepRow: View {
    let iconName: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            Image(systemName: iconName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 48)

            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body.weight(.medium))
    }
}
