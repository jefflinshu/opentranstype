import AppKit
import SwiftUI

enum DiagnosticLog {
    static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/OpenTransType/diagnostics.log")

    static func reset() {
        try? FileManager.default.removeItem(at: url)
    }

    static func write(_ message: String) {
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

        NSLog("OpenTransType: \(message)")
    }
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let model = TranslatorModel()
    private let accessibility = AccessibilityTextController()
    private var overlayController: OverlayWindowController?
    private var rightMouseMonitor: Any?
    private var activeApplicationObserver: NSObjectProtocol?
    private var keyEventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var automaticReadTask: Task<Void, Never>?
    private var frontmostMonitor: Timer?
    private var lastFrontmostPID: pid_t = 0
    private var frontmostMonitorTick = 0
    private var lastAXMissLogAt = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.reset()
        DiagnosticLog.write("app launched, trusted=\(accessibility.isTrusted), log=\(DiagnosticLog.url.path)")
        NSApp.setActivationPolicy(.accessory)
        overlayController = OverlayWindowController(
            model: model,
            accessibility: accessibility,
            onRefresh: { [weak self] in
                Task { @MainActor in
                    await self?.refreshCurrentText(showFailure: true)
                }
            }
        )
        accessibility.requestPermission()
        installActiveApplicationObserver()
        startFrontmostApplicationMonitor()
        accessibility.startObservingTextChanges { [weak self] text in
            self?.handleObservedText(text)
        }
        installRightClickMonitor()
        installKeyEventTap()
        model.enable()
        model.statusText = "正在监听输入"
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
        guard !trimmedText.isEmpty else {
            DiagnosticLog.write("observed text empty")
            return
        }

        model.enable()
        overlayController?.show(near: accessibility.focusedElementFrame())
        model.updateSourceText(trimmedText)
        DiagnosticLog.write("observed text accepted, length=\(trimmedText.count), element=\(accessibility.focusedElementDebugSummary())")
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
            accessibility.observeCurrentFocusedElement()
            DiagnosticLog.write("refresh AX text length=\(axText.count), element=\(accessibility.focusedElementDebugSummary())")
            model.forceTranslation(for: axText)
            return
        }

        if let copiedText = await readCurrentTextWithTimeout() {
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
        if !axText.isEmpty {
            accessibility.observeCurrentFocusedElement()
            model.enable()
            overlayController?.show(near: accessibility.focusedElementFrame())
            model.updateSourceText(axText)
            DiagnosticLog.write("keystroke AX text length=\(axText.count), element=\(accessibility.focusedElementDebugSummary())")
            return
        }

        if Date().timeIntervalSince(lastAXMissLogAt) > 5 {
            lastAXMissLogAt = Date()
            DiagnosticLog.write("keystroke AX miss, element=\(accessibility.focusedElementDebugSummary())")
            accessibility.logFocusedElementDiagnostics(reason: "keystroke miss")
        }
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
            model.enable()
            overlayController?.show(near: accessibility.focusedElementFrame())
            model.forceTranslation(for: axText)
            DiagnosticLog.write("user selection AX text length=\(axText.count), element=\(accessibility.focusedElementDebugSummary())")
            return
        }

        if let copiedText = await accessibility.readTextByCopyingCurrentField(collapseSelection: false) {
            model.enable()
            overlayController?.show(near: accessibility.focusedElementFrame())
            model.forceTranslation(for: copiedText)
            DiagnosticLog.write("user selection copy text length=\(copiedText.count), app=\(accessibility.focusedApplicationBundleIdentifier() ?? "unknown")")
        }
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
            return false
        }

        overlayController?.applyTranslation()
        return true
    }
}
