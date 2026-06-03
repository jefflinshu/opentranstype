import AppKit
import SwiftUI
import Translation

@MainActor
final class DashboardWindowController {
    private let historyStore: TranslationHistoryStore
    private let model: TranslatorModel
    private var window: NSWindow?
    private var resizeObserver: NSObjectProtocol?

    init(historyStore: TranslationHistoryStore, model: TranslatorModel) {
        self.historyStore = historyStore
        self.model = model
    }

    func show() {
        if window == nil {
            let contentView = DashboardView(historyStore: historyStore, model: model)
            let hostingView = NSHostingView(rootView: contentView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
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
            window.minSize = NSSize(width: 760, height: 520)
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

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case stats
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stats:
            return "数据统计"
        case .history:
            return "历史记录"
        case .settings:
            return "设置"
        }
    }

    var iconName: String {
        switch self {
        case .stats:
            return "chart.bar.xaxis"
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "gearshape"
        }
    }
}

private struct DashboardView: View {
    @ObservedObject var historyStore: TranslationHistoryStore
    @ObservedObject var model: TranslatorModel

    @State private var selection: DashboardSection = .stats

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.iconName)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            detailView
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .stats:
            StatsDashboardView(historyStore: historyStore, model: model)
        case .history:
            HistoryDashboardView(historyStore: historyStore)
        case .settings:
            SettingsDashboardView(model: model)
        }
    }

}

private struct StatsDashboardView: View {
    @ObservedObject var historyStore: TranslationHistoryStore
    @ObservedObject var model: TranslatorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 14),
                    GridItem(.flexible(), spacing: 14)
                ], spacing: 14) {
                    StatCard(title: "翻译次数", value: "\(historyStore.stats.recordCount)", iconName: "number")
                    StatCard(title: "原文字数", value: "\(historyStore.stats.sourceCharacterCount)", iconName: "character.cursor.ibeam")
                    StatCard(title: "译文字数", value: "\(historyStore.stats.translatedCharacterCount)", iconName: "textformat")
                    StatCard(title: "平均长度", value: "\(historyStore.stats.averageSourceLength)", iconName: "divide")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("当前设置")
                        .font(.title3.weight(.semibold))

                    HStack {
                        Label("默认目标语言", systemImage: "globe")
                        Spacer()
                        Text(model.selectedLanguage.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("监听状态", systemImage: model.isEnabled ? "ear" : "pause.circle")
                        Spacer()
                        Text(model.statusText)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("最近目标语言", systemImage: "clock")
                        Spacer()
                        Text(historyStore.stats.latestTargetLanguage)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .liquidGlassPanel(cornerRadius: 10)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HistoryDashboardView: View {
    @ObservedObject var historyStore: TranslationHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()

                Button("清空") {
                    historyStore.clear()
                }
                .disabled(historyStore.records.isEmpty)
            }

            if historyStore.records.isEmpty {
                ContentUnavailableView(
                    "还没有历史记录",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("完成一次翻译后会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(historyStore.records) { record in
                    HistoryRecordRow(record: record)
                        .padding(.vertical, 8)
                }
                .listStyle(.inset)
            }
        }
        .padding(28)
    }
}

private struct SettingsDashboardView: View {
    @ObservedObject var model: TranslatorModel

    @State private var languagePackStates: [String: DashboardLanguagePackState] = [:]
    @State private var languageTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("默认目标语言")
                        .font(.title3.weight(.semibold))

                    Picker("默认目标语言", selection: $model.selectedLanguage) {
                        ForEach(TranslationLanguage.supported) { language in
                            Text(language.name).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)

                    Text("当前默认：\(model.selectedLanguage.name)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .liquidGlassPanel(cornerRadius: 10)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("语言包")
                            .font(.title3.weight(.semibold))

                        Spacer()

                        Button("全部检查") {
                            checkAllLanguagePacks()
                        }
                    }

                    Text("按示例语言对检查本机翻译语言包。实际翻译时会根据输入内容自动识别源语言。")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ForEach(TranslationLanguage.supported) { language in
                            LanguagePackRow(
                                language: language,
                                state: languagePackStates[language.id] ?? .idle,
                                sourceLanguageName: sampleSourceLanguageName(for: language),
                                onCheck: {
                                    checkLanguagePack(for: language)
                                },
                                onPrepare: {
                                    prepareLanguagePack(for: language)
                                }
                            )

                            if language.id != TranslationLanguage.supported.last?.id {
                                Divider()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                }
                .padding(18)
                .liquidGlassPanel(cornerRadius: 10)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            checkAllLanguagePacks()
        }
        .onChange(of: model.selectedLanguage) { _, _ in
            if languagePackStates[model.selectedLanguage.id] == nil {
                checkLanguagePack(for: model.selectedLanguage)
            }
        }
        .onDisappear {
            cancelLanguageTasks()
        }
    }

    private func checkAllLanguagePacks() {
        for language in TranslationLanguage.supported {
            checkLanguagePack(for: language)
        }
    }

    private func checkLanguagePack(for language: TranslationLanguage) {
        languageTasks[language.id]?.cancel()
        languagePackStates[language.id] = .checking

        let sourceLanguage = sampleSourceLanguage(for: language)
        let targetLanguage = language.language

        languageTasks[language.id] = Task { @MainActor in
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
                languagePackStates[language.id] = .installed
            case .supported:
                languagePackStates[language.id] = .needsDownload
            case .unsupported:
                languagePackStates[language.id] = .unsupported
            @unknown default:
                languagePackStates[language.id] = .unsupported
            }

            languageTasks[language.id] = nil
        }
    }

    private func prepareLanguagePack(for language: TranslationLanguage) {
        guard (languagePackStates[language.id] ?? .idle).canPrepare else {
            return
        }

        languageTasks[language.id]?.cancel()
        languagePackStates[language.id] = .preparing

        let sourceLanguage = sampleSourceLanguage(for: language)
        let targetLanguage = language.language

        languageTasks[language.id] = Task { @MainActor in
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

                languageTasks[language.id] = nil
                checkLanguagePack(for: language)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                languagePackStates[language.id] = .failed(error.localizedDescription)
                languageTasks[language.id] = nil
            }
        }
    }

    private func cancelLanguageTasks() {
        for task in languageTasks.values {
            task.cancel()
        }

        languageTasks = [:]
    }

    private func sampleSourceLanguage(for language: TranslationLanguage) -> Locale.Language {
        if language.id == "en" {
            return Locale.Language(identifier: "zh-Hans")
        }

        return Locale.Language(identifier: "en")
    }

    private func sampleSourceLanguageName(for language: TranslationLanguage) -> String {
        language.id == "en" ? "简体中文" : "English"
    }
}

private struct LanguagePackRow: View {
    let language: TranslationLanguage
    let state: DashboardLanguagePackState
    let sourceLanguageName: String
    let onCheck: () -> Void
    let onPrepare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(state.iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(language.name)
                    .font(.callout.weight(.medium))

                Text("\(sourceLanguageName) → \(language.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(state.message)
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("检查") {
                onCheck()
            }
            .disabled(state.isBusy)

            Button(state.actionTitle) {
                onPrepare()
            }
            .disabled(!state.canPrepare)
        }
        .padding(.vertical, 10)
    }
}

private enum DashboardLanguagePackState: Equatable {
    case idle
    case checking
    case installed
    case needsDownload
    case preparing
    case unsupported
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .preparing:
            return true
        case .idle, .installed, .needsDownload, .unsupported, .failed:
            return false
        }
    }

    var canPrepare: Bool {
        switch self {
        case .needsDownload, .failed:
            return true
        case .idle, .checking, .installed, .preparing, .unsupported:
            return false
        }
    }

    var actionTitle: String {
        switch self {
        case .preparing:
            return "下载中..."
        case .installed:
            return "已安装"
        default:
            return "下载"
        }
    }

    var iconName: String {
        switch self {
        case .idle, .checking, .preparing:
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
        case .idle, .checking, .preparing:
            return .secondary
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "未检查"
        case .checking:
            return "检查中"
        case .installed:
            return "已安装"
        case .needsDownload:
            return "可下载"
        case .preparing:
            return "准备下载"
        case .unsupported:
            return "不支持"
        case .failed:
            return "下载失败"
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let iconName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.tint)

            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))

            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .padding(18)
        .liquidGlassPanel(cornerRadius: 10)
    }
}

private struct HistoryRecordRow: View {
    let record: TranslationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Self.dateFormatter.string(from: record.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.targetLanguageName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(record.sourceText)
                .font(.body.weight(.medium))
                .lineLimit(2)

            Text(record.translatedText)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
