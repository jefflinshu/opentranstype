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
            window.title = "Transtype"
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

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var languageCatalog = TranslationLanguageCatalog.shared

    @ObservedObject var model: TranslatorModel
    let onFinish: () -> Void

    @State private var page = 0
    @State private var isAccessibilityTrusted = AXIsProcessTrusted()
    @State private var languagePackState: LanguagePackState = .checking
    @State private var languageTask: Task<Void, Never>?
    @State private var pendingPreparationConfiguration: TranslationSession.Configuration?

    var body: some View {
        ZStack {
            OnboardingBackdropView()
                .blur(radius: 1)

            Color.black.opacity(backdropOverlayOpacity)

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
                        Button("Next") {
                            refreshAccessibilityTrust()
                            page = 1
                        }
                        .disabled(!isAccessibilityTrusted)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Get Started") {
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
            .shadow(color: .black.opacity(cardShadowOpacity), radius: 28, x: 0, y: 18)
        }
        .ignoresSafeArea()
        .frame(minWidth: 820, minHeight: 600)
        .onAppear {
            languageCatalog.loadIfNeeded()
            refreshAccessibilityTrust()
            checkLanguagePack()
        }
        .onChange(of: model.selectedLanguage) { _, _ in
            checkLanguagePack()
        }
        .onChange(of: languageCatalog.supportedLanguages) { _, _ in
            checkLanguagePack()
        }
        .onDisappear {
            languageTask?.cancel()
        }
        .translationTask(pendingPreparationConfiguration) { session in
            do {
                try await session.prepareTranslation()
                await MainActor.run {
                    pendingPreparationConfiguration = nil
                    checkLanguagePack()
                }
            } catch {
                await MainActor.run {
                    pendingPreparationConfiguration = nil
                    languagePackState = .failed(languagePackPreparationErrorMessage(error))
                }
            }
        }
    }

    private var backdropOverlayOpacity: Double {
        colorScheme == .dark ? 0.32 : 0.18
    }

    private var cardShadowOpacity: Double {
        colorScheme == .dark ? 0.34 : 0.18
    }

    private var instructionsPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            OnboardingAppMark()
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.tint)

                Text("Transtype")
                    .font(.largeTitle.weight(.bold))
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 22) {
                OnboardingStepRow(iconName: "cursorarrow.rays", text: String(localized: "Type in any app text field and see the translation instantly."))
                OnboardingStepRow(iconName: "keyboard.chevron.compact.down", text: String(localized: "Once the translation is ready, press ↓ or click the overlay button to replace the original text."))
                OnboardingStepRow(iconName: "lock.shield", text: accessibilityStatusText)
            }

            HStack(spacing: 12) {
                Button("Open Accessibility Settings") {
                    requestAccessibilityPermission()
                }

                Button("Check Again") {
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
                Text("Choose a target language")
                    .font(.largeTitle.weight(.bold))

                Text("Choose the language you translate into most often. The first time you use a language pair, Apple may ask you to download the on-device translation pack.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Target language", selection: $model.selectedLanguage) {
                ForEach(pickerLanguages) { language in
                    Text(language.name).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260, alignment: .leading)

            Text(String.localizedStringWithFormat(
                String(localized: "Current default: %@"),
                model.selectedLanguage.name
            ))
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: languagePackState.iconName)
                        .foregroundStyle(languagePackState.iconColor)
                    Text(languagePackState.message)
                        .font(.callout.weight(.medium))
                }

                Text(String.localizedStringWithFormat(
                    String(localized: "Checking sample pair: %1$@ → %2$@. When translating, the source language is detected automatically from your input."),
                    sampleSourceLanguageName,
                    model.selectedLanguage.name
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(languagePackState.actionTitle) {
                        prepareLanguagePack()
                    }
                    .disabled(!languagePackState.canPrepare)
                    .buttonStyle(.bordered)

                    Button("Check Again") {
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
        isAccessibilityTrusted
            ? String(localized: "Accessibility access granted")
            : String(localized: "Accessibility access is required to read and replace text")
    }

    private var sampleSourceLanguage: Locale.Language {
        if model.selectedLanguage.language.languageCode?.identifier == "en" {
            return Locale.Language(identifier: "zh-Hans")
        }

        return Locale.Language(identifier: "en")
    }

    private var pickerLanguages: [TranslationLanguage] {
        mergedLanguages(ensuring: model.selectedLanguage, in: languageCatalog.supportedLanguages)
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

    private var sampleSourceLanguageName: String {
        model.selectedLanguage.language.languageCode?.identifier == "en"
            ? String(localized: "Simplified Chinese")
            : String(localized: "English")
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
        var configuration = TranslationSession.Configuration(
            source: sampleSourceLanguage,
            target: model.selectedLanguage.language
        )
        configuration.invalidate()
        pendingPreparationConfiguration = configuration
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
            return String(localized: "Preparing...")
        case .installed:
            return String(localized: "Ready")
        default:
            return String(localized: "Download language pack")
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
            return String(localized: "Checking language pack...")
        case .installed:
            return String(localized: "Language pack installed. You're ready to go.")
        case .needsDownload:
            return String(localized: "This language pack is not installed yet. Download it first.")
        case .preparing:
            return String(localized: "Asking the system to prepare the language pack")
        case .unsupported:
            return String(localized: "This sample language pair is not supported by the system")
        case .failed(let reason):
            return String.localizedStringWithFormat(
                String(localized: "Failed to prepare language pack: %@"),
                reason
            )
        }
    }
}

private struct OnboardingBackdropView: View {
    var body: some View {
        NavigationSplitView {
            List(selection: .constant("stats")) {
                Section("Transtype") {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                        .tag("stats")
                    Label("History", systemImage: "clock.arrow.circlepath")
                        .tag("history")
                    Label("Settings", systemImage: "gearshape")
                        .tag("settings")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(230)
        } detail: {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text("Stats")
                        .font(.system(size: 34, weight: .bold))

                    Spacer()

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
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
                    ForEach([
                        String(localized: "Translations"),
                        String(localized: "Source characters"),
                        String(localized: "Translated characters"),
                        String(localized: "Average length")
                    ], id: \.self) { title in
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
