import AppKit
import SwiftUI

enum DiagnosticLog {
    static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/OpenTransType/diagnostics.log")

    private static let queue = DispatchQueue(label: "com.curisaas.opentranstype.diagnostic-log")

    static func reset() {
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func write(_ message: String) {
        queue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            let directory = url.deletingLastPathComponent()

            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }

                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } catch {
                NSLog("OpenTransType diagnostics log failed: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private static let maximumAutomaticTextLength = 2_000
    private static let maximumManualTextLength = 2_000
    private static let ignoredCapturedTexts: Set<String> = [
        "要求后续变更",
        "Require follow-up changes"
    ]

    private let historyStore: TranslationHistoryStore
    private let model: TranslatorModel
    private let accessibility = AccessibilityTextController()
    private var overlayController: OverlayWindowController?
    private var onboardingController: OnboardingWindowController?
    private var dashboardController: DashboardWindowController?
    private var statusItem: NSStatusItem?
    private var rightMouseMonitor: Any?
    private var activeApplicationObserver: NSObjectProtocol?
    private var keyEventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var automaticReadTask: Task<Void, Never>?
    private var frontmostMonitor: Timer?
    private var lastFrontmostPID: pid_t = 0
    private var frontmostMonitorTick = 0
    private var lastAXMissLogAt = Date.distantPast
    private var lastAutomaticText = ""
    private var didStartTranslationExperience = false

    override init() {
        let historyStore = TranslationHistoryStore()
        self.historyStore = historyStore
        self.model = TranslatorModel(historyStore: historyStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard claimSingleRunningInstance() else {
            return
        }

        DiagnosticLog.write("app launched pid=\(getpid()), trusted=\(accessibility.isTrusted), log=\(DiagnosticLog.url.path)")
        overlayController = OverlayWindowController(
            model: model,
            accessibility: accessibility,
            onRefresh: { [weak self] in
                Task { @MainActor in
                    await self?.refreshCurrentText(showFailure: true)
                }
            }
        )
        dashboardController = DashboardWindowController(historyStore: historyStore, model: model)
        installStatusItem()

        if UserDefaults.standard.bool(forKey: OnboardingView.didCompleteKey) {
            startTranslationExperience()
        } else {
            onboardingController = OnboardingWindowController(model: model) { [weak self] in
                self?.startTranslationExperience()
            }
            onboardingController?.show()
            DiagnosticLog.write("onboarding shown")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardController?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func claimSingleRunningInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentPID = getpid()
        let existingApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentPID && !$0.isTerminated }

        guard let existingApplication else {
            return true
        }

        DiagnosticLog.write("duplicate instance pid=\(currentPID) exiting, existing pid=\(existingApplication.processIdentifier)")
        existingApplication.activate()
        NSApp.terminate(nil)
        return false
    }

    private func installStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "OpenTransType")
            button.image?.isTemplate = true
            button.toolTip = "OpenTransType"
        }

        statusItem = item
        refreshStatusMenu()
    }

    @objc private func showDashboardFromStatusItem() {
        dashboardController?.show()
    }

    @objc private func toggleTranslationFromStatusItem() {
        if model.isEnabled {
            model.disable()
            overlayController?.hide()
        } else {
            model.enable()
            overlayController?.show(near: nil)
        }

        refreshStatusMenu()
    }

    @objc private func showOverlayFromStatusItem() {
        model.enable()
        model.statusText = model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "正在监听输入" : model.statusText
        overlayController?.show(near: nil)
        refreshStatusMenu()
    }

    @objc private func quitFromStatusItem() {
        NSApp.terminate(nil)
    }

    private func refreshStatusMenu() {
        let menu = NSMenu()

        let statusItem = NSMenuItem(title: model.isEnabled ? "翻译已启用" : "翻译已禁用", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem(
            title: model.isEnabled ? "禁用翻译" : "启用翻译",
            action: #selector(toggleTranslationFromStatusItem),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开主窗口", action: #selector(showDashboardFromStatusItem), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "显示翻译浮窗", action: #selector(showOverlayFromStatusItem), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitFromStatusItem), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        self.statusItem?.menu = menu
    }

    private func startTranslationExperience() {
        guard !didStartTranslationExperience else {
            return
        }

        didStartTranslationExperience = true
        NSApp.setActivationPolicy(.regular)
        model.enable()
        model.statusText = "正在监听输入"
        refreshStatusMenu()
        dashboardController?.show()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            startTranslationServicesAfterLaunch()
        }
    }

    private func startTranslationServicesAfterLaunch() {
        guard accessibility.isTrusted else {
            model.statusText = "请在系统设置中允许辅助功能权限"
            refreshStatusMenu()
            DiagnosticLog.write("translation services deferred, accessibility not trusted")
            return
        }

        installActiveApplicationObserver()
        startFrontmostApplicationMonitor()
        accessibility.startObservingTextChanges { [weak self] text in
            self?.handleObservedText(text)
        }
        installRightClickMonitor()
        installKeyEventTap()
        overlayController?.show(near: nil)
        DiagnosticLog.write("overlay shown")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let rightMouseMonitor {
            NSEvent.removeMonitor(rightMouseMonitor)
        }

        if let activeApplicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeApplicationObserver)
        }

        accessibility.stopObservingTextChanges()
        frontmostMonitor?.invalidate()
        frontmostMonitor = nil
        automaticReadTask?.cancel()
        automaticReadTask = nil

        if let keyEventTap {
            CGEvent.tapEnable(tap: keyEventTap, enable: false)
        }
    }

    private func installActiveApplicationObserver() {
        activeApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            MainActor.assumeIsolated {
                self.lastFrontmostPID = 0
                self.accessibility.refreshFrontmostApplicationObserver()
            }
        }
    }

    private func startFrontmostApplicationMonitor() {
        frontmostMonitor?.invalidate()
        DiagnosticLog.write("frontmost monitor started")
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }

                self.frontmostMonitorTick += 1
                guard let app = self.currentUserFacingApplication() else {
                    if self.frontmostMonitorTick % 2 == 0 {
                        self.accessibility.refreshFrontmostApplicationObserver()
                    }
                    if self.frontmostMonitorTick % 10 == 0 {
                        DiagnosticLog.write("frontmost monitor unresolved, \(self.workspaceApplicationSummary())")
                    }
                    return
                }

                guard app.processIdentifier != self.lastFrontmostPID else {
                    return
                }

                self.lastFrontmostPID = app.processIdentifier
                DiagnosticLog.write("frontmost monitor app=\(app.bundleIdentifier ?? "unknown"), pid=\(app.processIdentifier), active=\(app.isActive)")
                self.accessibility.refreshFrontmostApplicationObserver()
            }
        }
        frontmostMonitor = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func currentUserFacingApplication() -> NSRunningApplication? {
        let ignoredBundleIDs: Set<String> = [
            Bundle.main.bundleIdentifier ?? "",
            "com.apple.loginwindow",
            "com.apple.UserNotificationCenter"
        ]

        return NSWorkspace.shared.runningApplications.first { app in
            guard app.isActive,
                  app.processIdentifier != getpid(),
                  !ignoredBundleIDs.contains(app.bundleIdentifier ?? "") else {
                return false
            }

            return true
        } ?? NSWorkspace.shared.frontmostApplication.flatMap { app in
            guard app.processIdentifier != getpid(),
                  !ignoredBundleIDs.contains(app.bundleIdentifier ?? "") else {
                return nil
            }

            return app
        }
    }

    private func workspaceApplicationSummary() -> String {
        let activeApps = NSWorkspace.shared.runningApplications
            .filter(\.isActive)
            .map { "\($0.bundleIdentifier ?? "unknown"):\($0.processIdentifier)" }
            .joined(separator: ",")
        return "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"), active=[\(activeApps)]"
    }

    private func handleObservedText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        acceptAutomaticText(trimmedText, source: "observed")
    }

    private func installRightClickMonitor() {
        rightMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                await self?.showOverlayForFocusedText(at: NSEvent.mouseLocation)
            }
        }
    }

    private func showOverlayForFocusedText(at appKitPoint: CGPoint? = nil) async {
        if !accessibility.requestPermission() {
            overlayController?.show(near: nil)
            model.statusText = "请在系统设置中允许辅助功能权限"
            DiagnosticLog.write("accessibility permission missing")
            return
        }

        let didFindElement = appKitPoint.map { accessibility.refreshEditableElement(at: $0) }
            ?? accessibility.refreshEditableElementAtMouseLocation()
        DiagnosticLog.write("manual bind didFindElement=\(didFindElement), element=\(accessibility.focusedElementDebugSummary())")

        model.enable()
        accessibility.observeCurrentFocusedElement()
        overlayController?.show(near: didFindElement ? accessibility.focusedElementFrame() : nil)

        let axText = didFindElement ? accessibility.currentText().trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if !axText.isEmpty {
            guard canTranslateManualText(axText, source: "manual AX") else {
                return
            }

            DiagnosticLog.write("manual AX text length=\(axText.count)")
            model.forceTranslation(for: axText)
            return
        }

        await refreshCurrentText(showFailure: true)
    }

    private func refreshCurrentText(showFailure: Bool = true) async {
        model.enable()
        if showFailure {
            model.statusText = "读取输入中..."
        }

        let axText = accessibility.currentText().trimmingCharacters(in: .whitespacesAndNewlines)
        if !axText.isEmpty {
            guard canTranslateManualText(axText, source: "refresh AX") else {
                return
            }

            accessibility.observeCurrentFocusedElement()
            DiagnosticLog.write("refresh AX text length=\(axText.count), element=\(accessibility.focusedElementDebugSummary())")
            model.forceTranslation(for: axText)
            return
        }

        if let copiedText = await readCurrentTextWithTimeout() {
            guard canTranslateManualText(copiedText, source: "manual copy") else {
                return
            }

            DiagnosticLog.write("manual copy fallback text length=\(copiedText.count)")
            model.forceTranslation(for: copiedText)
        } else if showFailure {
            model.statusText = "未读到文本"
            DiagnosticLog.write("manual read failed, element=\(accessibility.focusedElementDebugSummary())")
            accessibility.logFocusedElementDiagnostics(reason: "manual read failed")
        }
    }

    private func scheduleAutomaticTextRead() {
        automaticReadTask?.cancel()
        automaticReadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else {
                return
            }

            await readTextAfterKeystroke()
        }
    }

    private func readTextAfterKeystroke() async {
        accessibility.refreshFrontmostApplicationObserver()
        let axText = accessibility.currentText().trimmingCharacters(in: .whitespacesAndNewlines)
        if acceptAutomaticText(axText, source: "keystroke AX") {
            return
        }

        if Date().timeIntervalSince(lastAXMissLogAt) > 5 {
            lastAXMissLogAt = Date()
            DiagnosticLog.write("keystroke AX miss, element=\(accessibility.focusedElementDebugSummary())")
            accessibility.logFocusedElementDiagnostics(reason: "keystroke miss")
        }
    }

    @discardableResult
    private func acceptAutomaticText(_ text: String, source: String) -> Bool {
        guard !text.isEmpty else {
            if !lastAutomaticText.isEmpty {
                lastAutomaticText = ""
                model.updateSourceText("")
                DiagnosticLog.write("\(source) text empty")
            }
            return false
        }

        guard !shouldIgnoreCapturedText(text) else {
            if lastAutomaticText != text {
                lastAutomaticText = text
                model.updateSourceText("")
                DiagnosticLog.write("\(source) ignored UI text, length=\(text.count), app=\(accessibility.focusedApplicationBundleIdentifier() ?? "unknown")")
            }
            return false
        }

        guard text.count <= Self.maximumAutomaticTextLength else {
            if lastAutomaticText != text {
                lastAutomaticText = text
                DiagnosticLog.write("\(source) ignored too long, length=\(text.count), element=\(accessibility.focusedElementDebugSummary())")
            }
            return false
        }

        guard text != lastAutomaticText else {
            return true
        }

        lastAutomaticText = text
        accessibility.observeCurrentFocusedElement()
        model.enable()
        if overlayController?.isVisible != true {
            overlayController?.show(near: accessibility.focusedElementFrame())
        }
        model.updateSourceText(text)
        DiagnosticLog.write("\(source) text accepted, length=\(text.count), element=\(accessibility.focusedElementDebugSummary())")
        return true
    }

    private func readCurrentTextWithTimeout() async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { @MainActor in
                await self.accessibility.readTextByCopyingCurrentField()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private func installKeyEventTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let coordinator = Unmanaged<AppCoordinator>.fromOpaque(refcon).takeUnretainedValue()
            return coordinator.handleKeyEvent(proxy: proxy, type: type, event: event)
        }

        keyEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let keyEventTap else {
            DiagnosticLog.write("key event tap install failed")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyEventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: keyEventTap, enable: true)
        DiagnosticLog.write("key event tap installed")
    }

    private nonisolated func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let keyEventTap = self.keyEventTap {
                    CGEvent.tapEnable(tap: keyEventTap, enable: true)
                }
                DiagnosticLog.write("key event tap re-enabled, type=\(type.rawValue)")
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if type == .keyDown, keyCode == 0, flags.contains(.maskCommand) {
            Task { @MainActor in
                self.scheduleUserSelectedTextRead()
            }
            return Unmanaged.passUnretained(event)
        }

        let downArrowKeyCode: Int64 = 125
        if type == .keyDown, keyCode == downArrowKeyCode {
            let shouldConsume = runOnMainActorSynchronously {
                self.consumeDownArrowIfPossible()
            }
            return shouldConsume ? nil : Unmanaged.passUnretained(event)
        }

        if type == .keyDown, shouldScheduleAutomaticRead(for: keyCode, flags: flags) {
            Task { @MainActor in
                self.scheduleAutomaticTextRead()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func scheduleUserSelectedTextRead() {
        automaticReadTask?.cancel()
        automaticReadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else {
                return
            }

            await readUserSelectedText()
        }
    }

    private func readUserSelectedText() async {
        accessibility.refreshFrontmostApplicationObserver()
        let axText = accessibility.currentText().trimmingCharacters(in: .whitespacesAndNewlines)
        if !axText.isEmpty {
            guard canTranslateManualText(axText, source: "user selection AX") else {
                return
            }

            model.enable()
            overlayController?.show(near: accessibility.focusedElementFrame())
            model.forceTranslation(for: axText)
            DiagnosticLog.write("user selection AX text length=\(axText.count), element=\(accessibility.focusedElementDebugSummary())")
            return
        }

        if let copiedText = await accessibility.readTextByCopyingCurrentField(collapseSelection: false) {
            guard canTranslateManualText(copiedText, source: "user selection copy") else {
                return
            }

            model.enable()
            overlayController?.show(near: accessibility.focusedElementFrame())
            model.forceTranslation(for: copiedText)
            DiagnosticLog.write("user selection copy text length=\(copiedText.count), app=\(accessibility.focusedApplicationBundleIdentifier() ?? "unknown")")
        }
    }

    private func canTranslateManualText(_ text: String, source: String) -> Bool {
        guard !shouldIgnoreCapturedText(text) else {
            DiagnosticLog.write("\(source) ignored UI text, length=\(text.count), app=\(accessibility.focusedApplicationBundleIdentifier() ?? "unknown")")
            return false
        }

        guard text.count <= Self.maximumManualTextLength else {
            model.enable()
            model.translatedText = ""
            model.statusText = "文本过长"
            overlayController?.show(near: accessibility.focusedElementFrame())
            DiagnosticLog.write("\(source) ignored too long, length=\(text.count)")
            return false
        }

        return true
    }

    private func shouldIgnoreCapturedText(_ text: String) -> Bool {
        Self.ignoredCapturedTexts.contains(normalizedCapturedText(text))
    }

    private func normalizedCapturedText(_ text: String) -> String {
        text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    private nonisolated func shouldScheduleAutomaticRead(for keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard !flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else {
            return false
        }

        let ignoredKeyCodes: Set<Int64> = [
            48, // Tab
            53, // Escape
            115, 116, 117, 119, 121, // Home/Page/Delete cluster
            123, 124, 125, 126 // Arrow keys
        ]

        return !ignoredKeyCodes.contains(keyCode)
    }

    private nonisolated func runOnMainActorSynchronously<T>(_ action: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(action)
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(action)
        }
    }

    private func consumeDownArrowIfPossible() -> Bool {
        guard model.isEnabled, model.canApplyTranslation else {
            DiagnosticLog.write("down arrow ignored, enabled=\(model.isEnabled), canApply=\(model.canApplyTranslation), status=\(model.statusText), translatedLength=\(model.translatedText.count)")
            return false
        }

        _ = accessibility.refreshFocusedEditableElement()
        accessibility.observeCurrentFocusedElement()
        DiagnosticLog.write("down arrow applying translation, element=\(accessibility.focusedElementDebugSummary())")
        overlayController?.applyTranslation()
        return true
    }
}
