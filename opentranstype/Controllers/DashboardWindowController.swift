import AppKit
import SwiftUI
import Translation

@MainActor
final class DashboardWindowController {
    private let historyStore: TranslationHistoryStore
    private let freeQuotaStore: FreeQuotaStore
    private let model: TranslatorModel
    private let proManager: ProManager
    private let onUpgrade: () -> Void
    private var window: NSWindow?
    private var resizeObserver: NSObjectProtocol?

    init(
        historyStore: TranslationHistoryStore,
        freeQuotaStore: FreeQuotaStore,
        model: TranslatorModel,
        proManager: ProManager,
        onUpgrade: @escaping () -> Void
    ) {
        self.historyStore = historyStore
        self.freeQuotaStore = freeQuotaStore
        self.model = model
        self.proManager = proManager
        self.onUpgrade = onUpgrade
    }

    func show() {
        if window == nil {
            let contentView = DashboardView(
                historyStore: historyStore,
                freeQuotaStore: freeQuotaStore,
                model: model,
                proManager: proManager,
                onUpgrade: onUpgrade
            )
            let hostingView = NSHostingView(rootView: contentView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.title = "Transtype"
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
            return String(localized: "Stats")
        case .history:
            return String(localized: "History")
        case .settings:
            return String(localized: "Settings")
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
    @ObservedObject var freeQuotaStore: FreeQuotaStore
    @ObservedObject var model: TranslatorModel
    @ObservedObject var proManager: ProManager
    let onUpgrade: () -> Void

    @State private var selection: DashboardSection = .stats

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 14) {
                List(DashboardSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.iconName)
                        .tag(section)
                }
                .listStyle(.sidebar)

                FreeQuotaSidebarCard(
                    quotaStore: freeQuotaStore,
                    proManager: proManager,
                    onUpgrade: onUpgrade
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
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
            SettingsDashboardView(model: model, proManager: proManager)
        }
    }

}

private struct FreeQuotaSidebarCard: View {
    @ObservedObject var quotaStore: FreeQuotaStore
    @ObservedObject var proManager: ProManager
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(proManager.isPro ? "Pro quota" : "Free quota")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(quotaText)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                if !proManager.isPro {
                    Button("Upgrade") {
                        onUpgrade()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }

            ProgressView(value: progress)
                .tint(proManager.isPro ? .green : quotaTint)

            Text(descriptionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .liquidGlassPanel(cornerRadius: 12)
        .onAppear {
            quotaStore.refreshMonthIfNeeded()
        }
    }

    private var quotaText: String {
        if proManager.isPro {
            return String(localized: "Unlimited")
        }

        return "\(quotaStore.remainingCount)/\(FreeQuotaStore.monthlyLimit)"
    }

    private var descriptionText: String {
        if proManager.isPro {
            return String(localized: "Unlimited translations are active.")
        }

        return String(localized: "Free translations reset every month.")
    }

    private var progress: Double {
        if proManager.isPro {
            return 1
        }

        return Double(quotaStore.remainingCount) / Double(FreeQuotaStore.monthlyLimit)
    }

    private var quotaTint: Color {
        quotaStore.remainingCount <= 10 ? .orange : .accentColor
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
                    StatCard(title: String(localized: "Translations"), value: "\(historyStore.stats.recordCount)", iconName: "number")
                    StatCard(title: String(localized: "Source characters"), value: "\(historyStore.stats.sourceCharacterCount)", iconName: "character.cursor.ibeam")
                    StatCard(title: String(localized: "Translated characters"), value: "\(historyStore.stats.translatedCharacterCount)", iconName: "textformat")
                    StatCard(title: String(localized: "Average length"), value: "\(historyStore.stats.averageSourceLength)", iconName: "divide")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Current settings")
                        .font(.title3.weight(.semibold))

                    HStack {
                        Label("Default target language", systemImage: "globe")
                        Spacer()
                        Text(model.selectedLanguage.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Listening status", systemImage: model.isEnabled ? "ear" : "pause.circle")
                        Spacer()
                        Text(model.statusText)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Label("Recent target language", systemImage: "clock")
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
        .navigationTitle(DashboardSection.stats.title)
    }
}

private struct HistoryDashboardView: View {
    @ObservedObject var historyStore: TranslationHistoryStore

    var body: some View {
        Group {
            if historyStore.records.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed translations will appear here.")
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
        .navigationTitle(DashboardSection.history.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") {
                    historyStore.clear()
                }
                .disabled(historyStore.records.isEmpty)
            }
        }
    }
}

private struct SettingsDashboardView: View {
    private let supportURL = URL(string: "https://curisaas.com/transtype")!
    private let privacyPolicyURL = URL(string: "https://curisaas.com/transtype/privacy")!
    private let termsURL = URL(string: "https://curisaas.com/transtype/terms")!

    @ObservedObject private var languageCatalog = TranslationLanguageCatalog.shared
    @ObservedObject var model: TranslatorModel
    @ObservedObject var proManager: ProManager

    @State private var languagePackStates: [String: DashboardLanguagePackState] = [:]
    @State private var languageTasks: [String: Task<Void, Never>] = [:]
    @State private var pendingPreparationConfiguration: TranslationSession.Configuration?
    @State private var preparingLanguageID: String?
    @State private var isShowingPaywall = false
    @State private var modelsTab: ModelsTab = .languagePacks

    private enum ModelsTab: String, CaseIterable, Identifiable {
        case languagePacks
        case voiceModels

        var id: String { rawValue }

        var title: String {
            switch self {
            case .languagePacks:
                return String(localized: "Language packs")
            case .voiceModels:
                return String(localized: "Voice models")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: proManager.isPro ? "checkmark.seal.fill" : "sparkles")
                            .font(.title2)
                            .foregroundStyle(proManager.isPro ? Color.green : Color.accentColor)
                            .frame(width: 34)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(proManager.isPro ? "Transtype Pro active" : "Upgrade to Transtype Pro")
                                .font(.title3.weight(.semibold))

                            Text(proManager.isPro ? activePlanDescription : "Unlock unlimited translation workflow and Pro writing utilities.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(proManager.isPro ? "Manage" : "Upgrade") {
                            isShowingPaywall = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(18)
                .liquidGlassPanel(cornerRadius: 10)

                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "globe")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 34)

                    Text("Default target language")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Picker("Default target language", selection: selectedLanguageIDBinding) {
                        ForEach(pickerLanguages) { language in
                            Text(language.name).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                .padding(18)
                .liquidGlassPanel(cornerRadius: 10)

                VStack(alignment: .leading, spacing: 14) {
                    Picker("Models", selection: $modelsTab) {
                        ForEach(ModelsTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch modelsTab {
                    case .languagePacks:
                        languagePacksSection
                    case .voiceModels:
                        LocalSpeechModelsSettingsView(modelManager: model.speechModelManager)
                    }
                }
                .padding(18)
                .liquidGlassPanel(cornerRadius: 10)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Support and legal")
                        .font(.title3.weight(.semibold))

                    VStack(alignment: .leading, spacing: 10) {
                        Link(destination: supportURL) {
                            Label("Support", systemImage: "questionmark.circle")
                        }

                        Link(destination: privacyPolicyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }

                        Link(destination: termsURL) {
                            Label("Terms of Use", systemImage: "doc.text")
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
            languageCatalog.loadIfNeeded()
            checkAllLanguagePacks()
            Task {
                await proManager.refreshProState()
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(proManager: proManager)
        }
        .onChange(of: model.selectedLanguage) { _, _ in
            if languagePackStates[model.selectedLanguage.id] == nil {
                checkLanguagePack(for: model.selectedLanguage)
            }
        }
        .onChange(of: languageCatalog.supportedLanguages) { _, _ in
            checkAllLanguagePacks()
        }
        .onDisappear {
            cancelLanguageTasks()
        }
        .translationTask(pendingPreparationConfiguration) { session in
            guard let preparingLanguageID,
                  let language = languageCatalog.language(withID: preparingLanguageID) else {
                await MainActor.run {
                    pendingPreparationConfiguration = nil
                }
                return
            }

            do {
                try await session.prepareTranslation()
                await MainActor.run {
                    self.preparingLanguageID = nil
                    pendingPreparationConfiguration = nil
                    checkLanguagePack(for: language)
                }
            } catch {
                await MainActor.run {
                    languagePackStates[preparingLanguageID] = .failed(languagePackPreparationErrorMessage(error))
                    self.preparingLanguageID = nil
                    pendingPreparationConfiguration = nil
                }
            }
        }
        .navigationTitle(DashboardSection.settings.title)
    }

    private var languagePacksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(languageCatalog.supportedLanguages) { language in
                    LanguagePackRow(
                        language: language,
                        state: languagePackStates[language.id] ?? .idle,
                        sourceLanguageName: sampleSourceLanguageName(for: language),
                        onPrepare: {
                            prepareLanguagePack(for: language)
                        }
                    )

                    if language.id != languageCatalog.supportedLanguages.last?.id {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }

    private var activePlanDescription: String {
        switch proManager.activeProductID {
        case .month:
            return String(localized: "Monthly plan is active.")
        case .year:
            return String(localized: "Yearly plan is active.")
        case .lifetime:
            return String(localized: "Lifetime access is active.")
        case .none:
            return String(localized: "Pro access is active.")
        }
    }

    private func checkAllLanguagePacks() {
        for language in languageCatalog.supportedLanguages {
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
        preparingLanguageID = language.id
        var configuration = TranslationSession.Configuration(
            source: sampleSourceLanguage(for: language),
            target: language.language
        )
        configuration.invalidate()
        pendingPreparationConfiguration = configuration
    }

    private func cancelLanguageTasks() {
        for task in languageTasks.values {
            task.cancel()
        }

        languageTasks = [:]
    }

    private func sampleSourceLanguage(for language: TranslationLanguage) -> Locale.Language {
        if language.language.languageCode?.identifier == "en" {
            return Locale.Language(identifier: "zh-Hans")
        }

        return Locale.Language(identifier: "en")
    }

    private func sampleSourceLanguageName(for language: TranslationLanguage) -> String {
        language.language.languageCode?.identifier == "en"
            ? String(localized: "Simplified Chinese")
            : String(localized: "English")
    }

    private var pickerLanguages: [TranslationLanguage] {
        mergedLanguages(ensuring: model.selectedLanguage, in: languageCatalog.supportedLanguages)
    }

    // Bind the Picker by language id (String) rather than the whole struct, so the current
    // selection always matches an item in the list and shows up as selected.
    private var selectedLanguageIDBinding: Binding<String> {
        Binding(
            get: { model.selectedLanguage.id },
            set: { newID in
                if let language = pickerLanguages.first(where: { $0.id == newID }) {
                    model.selectedLanguage = language
                }
            }
        )
    }

    private func mergedLanguages(
        ensuring selectedLanguage: TranslationLanguage,
        in languages: [TranslationLanguage]
    ) -> [TranslationLanguage] {
        guard !languages.contains(selectedLanguage) else {
            return languages
        }

        return (languages + [selectedLanguage]).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func languagePackPreparationErrorMessage(_ error: Error) -> String {
        if (error as NSError).localizedDescription.contains("cancel") {
            return String(localized: "Language pack download cancelled")
        }

        let nsError = error as NSError
        let message = nsError.localizedFailureReason ?? nsError.localizedDescription

        if message == "(null)" || message.isEmpty {
            return String(localized: "No error details were returned by the system")
        }

        return message
    }
}

private struct LocalSpeechModelsSettingsView: View {
    @ObservedObject var modelManager: LocalSpeechModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Local voice models")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    modelManager.openModelsFolder()
                } label: {
                    Label("Folder", systemImage: "folder")
                }
                .controlSize(.small)
            }

            if let selectedModel = modelManager.selectedModel {
                Label(
                    String.localizedStringWithFormat(String(localized: "Selected: %@"), selectedModel.name),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
            } else {
                Label("No local voice model selected", systemImage: "waveform.badge.magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(LocalSpeechModel.available) { speechModel in
                    LocalSpeechModelRow(
                        speechModel: speechModel,
                        isDownloaded: modelManager.isDownloaded(speechModel),
                        isSelected: modelManager.selectedModelFilename == speechModel.filename,
                        isDownloading: modelManager.downloadingModelID == speechModel.id,
                        progress: modelManager.downloadProgress[speechModel.id] ?? 0,
                        onDownload: { modelManager.download(speechModel) },
                        onSelect: { modelManager.select(speechModel) },
                        onDelete: { modelManager.delete(speechModel) },
                        onCancel: { modelManager.cancelDownload() }
                    )

                    if speechModel.id != LocalSpeechModel.available.last?.id {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }
        }
    }
}

private struct LocalSpeechModelRow: View {
    let speechModel: LocalSpeechModel
    let isDownloaded: Bool
    let isSelected: Bool
    let isDownloading: Bool
    let progress: Double
    let onDownload: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(speechModel.name)
                        .font(.callout.weight(.medium))

                    Text(speechModel.size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(speechModel.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if isDownloading {
                ProgressView(value: progress)
                    .frame(width: 80)

                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else if isDownloaded {
                Button(isSelected ? "Selected" : "Use") {
                    onSelect()
                }
                .disabled(isSelected)
                .controlSize(.small)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.85))
            } else {
                Button {
                    onDownload()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
    }

    private var iconName: String {
        if isSelected {
            return "checkmark.circle.fill"
        }

        if isDownloaded {
            return "externaldrive.fill"
        }

        return "waveform"
    }

    private var iconColor: Color {
        if isSelected {
            return .green
        }

        if isDownloaded {
            return .accentColor
        }

        return .secondary
    }
}

private struct LanguagePackRow: View {
    let language: TranslationLanguage
    let state: DashboardLanguagePackState
    let sourceLanguageName: String
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

                Text(String.localizedStringWithFormat(
                    String(localized: "%1$@ → %2$@"),
                    sourceLanguageName,
                    language.name
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(state.message)
                .font(.callout)
                .foregroundStyle(.secondary)

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
            return String(localized: "Downloading...")
        case .installed:
            return String(localized: "Installed")
        default:
            return String(localized: "Download")
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
            return String(localized: "Not checked")
        case .checking:
            return String(localized: "Checking")
        case .installed:
            return String(localized: "Installed")
        case .needsDownload:
            return String(localized: "Available to download")
        case .preparing:
            return String(localized: "Preparing download")
        case .unsupported:
            return String(localized: "Unsupported")
        case .failed:
            return String(localized: "Download failed")
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
