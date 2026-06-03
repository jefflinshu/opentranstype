import AppKit
import ApplicationServices

@MainActor
final class AccessibilityTextController {
    private static let maximumAutomaticTextLength = 2_000

    private var focusedElement: AXUIElement?
    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedTextElement: AXUIElement?
    private var observedPID: pid_t = 0
    private var textChangeTask: Task<Void, Never>?
    private var onTextChange: ((String) -> Void)?
    private var lastPublishedText = ""
    private var lastDiagnosticsAt = Date.distantPast

    var hasFocusedElement: Bool {
        focusedElement != nil
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func startObservingTextChanges(onTextChange: @escaping (String) -> Void) {
        self.onTextChange = onTextChange
        DiagnosticLog.write("AX start observing")
        refreshFrontmostApplicationObserver()
    }

    func stopObservingTextChanges() {
        textChangeTask?.cancel()
        textChangeTask = nil
        onTextChange = nil
        observedApplication = nil
        observedTextElement = nil
        observedPID = 0

        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
    }

    func refreshFrontmostApplicationObserver() {
        guard isTrusted else {
            DiagnosticLog.write("AX observer skipped, trusted=false")
            return
        }

        guard let app = currentUserFacingApplication() ?? focusedElementHostApplication() else {
            DiagnosticLog.write("AX observer host unresolved, frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
            return
        }

        DiagnosticLog.write("AX frontmost app=\(app.bundleIdentifier ?? "unknown"), pid=\(app.processIdentifier)")
        installObserver(for: app)
        _ = refreshFocusedEditableElement()
        if let focusedElement {
            observeTextElement(focusedElement)
            publishTextChange(from: focusedElement, debounce: .milliseconds(80))
        } else {
            logFocusedElementDiagnostics(reason: "frontmost refresh miss")
        }
    }

    @discardableResult
    func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func refreshFocusedEditableElement() -> Bool {
        guard isTrusted else {
            return false
        }

        let systemElement = AXUIElementCreateSystemWide()
        if let textElement = focusedTextElement(from: systemElement) {
            focusedElement = textElement
            DiagnosticLog.write("AX focused element from system: \(focusedElementDebugSummary())")
            return true
        }

        if let frontmostApplication = currentUserFacingApplication() {
            let appElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
            if let textElement = focusedTextElement(from: appElement) {
                focusedElement = textElement
                DiagnosticLog.write("AX focused element from app: \(focusedElementDebugSummary())")
                return true
            }
        }

        focusedElement = nil
        logFocusedElementDiagnostics(reason: "focused editable miss")
        return false
    }

    private func focusedTextElement(from container: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(container, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else {
            return nil
        }

        return findTextTargetElement(near: value as! AXUIElement)
    }

    func observeCurrentFocusedElement() {
        guard let focusedElement else {
            return
        }

        observeTextElement(focusedElement)
    }

    func refreshEditableElementAtMouseLocation() -> Bool {
        refreshEditableElement(at: NSEvent.mouseLocation)
    }

    func refreshEditableElement(at appKitPoint: CGPoint) -> Bool {
        guard isTrusted else {
            return false
        }

        let displayHeight = NSScreen.screens.map(\.frame.maxY).max() ?? appKitPoint.y
        let candidatePoints = [
            CGPoint(x: appKitPoint.x, y: displayHeight - appKitPoint.y),
            appKitPoint
        ]

        for point in candidatePoints {
            if let editableElement = editableElementAtAXPoint(point) {
                focusedElement = editableElement
                return true
            }
        }

        return refreshFocusedEditableElement()
    }

    private func editableElementAtAXPoint(_ point: CGPoint) -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var elementAtPoint: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemElement, Float(point.x), Float(point.y), &elementAtPoint) == .success,
           let elementAtPoint,
           let editableElement = findTextTargetElement(near: elementAtPoint) {
            return editableElement
        }

        if let frontmostApplication = currentUserFacingApplication() {
            let appElement = AXUIElementCreateApplication(frontmostApplication.processIdentifier)
            if AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &elementAtPoint) == .success,
               let elementAtPoint,
               let editableElement = findTextTargetElement(near: elementAtPoint) {
                return editableElement
            }
        }

        return nil
    }

    func currentText() -> String {
        guard let focusedElement else {
            return ""
        }

        return readableText(from: focusedElement) ?? ""
    }

    func logFocusedElementDiagnostics(reason: String) {
        guard isTrusted else {
            return
        }

        guard Date().timeIntervalSince(lastDiagnosticsAt) > 5 else {
            return
        }
        lastDiagnosticsAt = Date()

        let systemElement = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value else {
            DiagnosticLog.write("AX diagnostics \(reason): no system focused element")
            return
        }

        let rawElement = value as! AXUIElement
        DiagnosticLog.write("AX diagnostics \(reason): focused=\(elementSummary(rawElement))")
        logChildSummaries(of: rawElement, depth: 0, prefix: "focused")
    }

    func focusedElementDebugSummary() -> String {
        guard let focusedElement else {
            return "未绑定输入框"
        }

        let role = stringAttribute(kAXRoleAttribute as String, from: focusedElement) ?? "unknown"
        let subrole = stringAttribute(kAXSubroleAttribute as String, from: focusedElement) ?? "none"
        let editable = boolAttribute(kAXIsEditableAttribute as String, from: focusedElement)
            .map { $0 ? "editable" : "not editable" } ?? "editable?"
        let valueSettable = isSettable(kAXValueAttribute as String, on: focusedElement) ? "value settable" : "value not settable"
        let count = numberAttribute(kAXNumberOfCharactersAttribute as String, from: focusedElement)
            .map { "chars \($0)" } ?? "chars?"

        return "\(role) / \(subrole) / \(editable) / \(valueSettable) / \(count)"
    }

    func focusedElementFrame() -> CGRect? {
        guard let focusedElement else {
            return nil
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(focusedElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    @discardableResult
    func replaceFocusedText(with text: String) -> Bool {
        guard let focusedElement else {
            DiagnosticLog.write("replace fallback paste, reason=no focused element")
            return replaceByPasting(text)
        }

        if replaceByPasting(text) {
            DiagnosticLog.write("replace paste preferred, length=\(text.count), element=\(focusedElementDebugSummary())")
            return true
        }

        let directResult = AXUIElementSetAttributeValue(focusedElement, kAXValueAttribute as CFString, text as CFTypeRef)
        if directResult == .success {
            DiagnosticLog.write("replace AXValue success, length=\(text.count), element=\(focusedElementDebugSummary())")
            return true
        }

        DiagnosticLog.write("replace AXValue failed result=\(directResult.rawValue), fallback paste, element=\(focusedElementDebugSummary())")
        return replaceByPasting(text)
    }

    func focusedApplicationBundleIdentifier() -> String? {
        if let focusedElement {
            var pid: pid_t = 0
            if AXUIElementGetPid(focusedElement, &pid) == .success,
               let app = NSRunningApplication(processIdentifier: pid) {
                return app.bundleIdentifier
            }
        }

        return currentUserFacingApplication()?.bundleIdentifier
    }

    func readTextByCopyingCurrentField(collapseSelection: Bool = false) async -> String? {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        pasteboard.clearContents()
        sendKey(.maskCommand, virtualKey: 8)
        try? await Task.sleep(for: .milliseconds(120))

        var copiedText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var usedSelectAll = false

        if copiedText?.isEmpty != false {
            pasteboard.clearContents()
            sendKey(.maskCommand, virtualKey: 0)
            usedSelectAll = true
            try? await Task.sleep(for: .milliseconds(80))
            sendKey(.maskCommand, virtualKey: 8)
            try? await Task.sleep(for: .milliseconds(140))
            copiedText = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if collapseSelection, usedSelectAll {
            sendKey(CGEventFlags(rawValue: 0), virtualKey: 124)
        }

        if let previousItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(previousItems)
        }

        guard let copiedText, !copiedText.isEmpty else {
            return nil
        }

        return copiedText
    }

    private func isTextTargetElement(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute, from: element)
        let subrole = stringAttribute(kAXSubroleAttribute as String, from: element)
        if subrole == kAXSecureTextFieldSubrole as String {
            return false
        }

        let textRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ]

        if boolAttribute(kAXIsEditableAttribute, from: element) == true {
            return true
        }

        if isSettable(kAXValueAttribute, on: element),
           role.map(textRoles.contains) != false {
            return true
        }

        if isSettable(kAXSelectedTextRangeAttribute, on: element),
           role.map(textRoles.contains) != false {
            return true
        }

        if supportsParameterizedAttribute(kAXStringForRangeParameterizedAttribute as String, on: element),
           numberAttribute(kAXNumberOfCharactersAttribute as String, from: element) != nil,
           role.map(textRoles.contains) == true {
            return true
        }

        guard let role else {
            return false
        }

        return textRoles.contains(role)
    }

    private func installObserver(for app: NSRunningApplication) {
        if observedPID == app.processIdentifier, observer != nil {
            return
        }

        stopActiveObserver()

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var nextObserver: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else {
                return
            }

            let controller = Unmanaged<AccessibilityTextController>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                controller.handleNotification(element: element, notification: notification as String)
            }
        }

        guard AXObserverCreate(app.processIdentifier, callback, &nextObserver) == .success,
              let nextObserver else {
            return
        }

        observer = nextObserver
        observedApplication = appElement
        observedPID = app.processIdentifier
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(nextObserver), .commonModes)
        addNotification(kAXFocusedUIElementChangedNotification as String, to: appElement)
        addNotification(kAXFocusedWindowChangedNotification as String, to: appElement)
        DiagnosticLog.write("AX observer installed pid=\(app.processIdentifier)")
    }

    private func stopActiveObserver() {
        textChangeTask?.cancel()
        textChangeTask = nil
        observedApplication = nil
        observedTextElement = nil
        observedPID = 0

        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
    }

    private func observeTextElement(_ element: AXUIElement) {
        guard observer != nil else {
            return
        }

        if let observedTextElement,
           CFEqual(observedTextElement, element) {
            return
        }

        observedTextElement = element
        addNotification(kAXValueChangedNotification as String, to: element)
        addNotification(kAXSelectedTextChangedNotification as String, to: element)
    }

    private func addNotification(_ notification: String, to element: AXUIElement) {
        guard let observer else {
            return
        }

        let result = AXObserverAddNotification(
            observer,
            element,
            notification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        if result != .success, result.rawValue != -25209 {
            DiagnosticLog.write("AX add notification failed \(notification), result=\(result.rawValue)")
        }
    }

    private func handleNotification(element: AXUIElement, notification: String) {
        if notification == kAXFocusedUIElementChangedNotification
            || notification == kAXFocusedWindowChangedNotification {
            if let textElement = findTextTargetElement(near: element) {
                focusedElement = textElement
                observeTextElement(textElement)
                publishTextChange(from: textElement, debounce: .milliseconds(60))
            } else if refreshFocusedEditableElement() {
                observeCurrentFocusedElement()
                if let focusedElement {
                    publishTextChange(from: focusedElement, debounce: .milliseconds(60))
                }
            }

        } else if notification == kAXValueChangedNotification
                    || notification == kAXSelectedTextChangedNotification {
            if let textElement = findTextTargetElement(near: element) {
                focusedElement = textElement
                publishTextChange(from: textElement, debounce: .milliseconds(90))
            } else if let focusedElement {
                publishTextChange(from: focusedElement, debounce: .milliseconds(90))
            }
        }
    }

    private func publishTextChange(from element: AXUIElement, debounce: Duration) {
        textChangeTask?.cancel()
        textChangeTask = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled,
                  let text = readableText(from: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return
            }

            guard text != self.lastPublishedText else {
                return
            }

            guard text.count <= Self.maximumAutomaticTextLength else {
                DiagnosticLog.write("AX publish ignored too long, length=\(text.count), element=\(self.focusedElementDebugSummary())")
                self.lastPublishedText = text
                return
            }

            self.lastPublishedText = text
            DiagnosticLog.write("AX publish text length=\(text.count)")
            onTextChange?(text)
        }
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

    private func focusedElementHostApplication() -> NSRunningApplication? {
        guard refreshFocusedEditableElement(),
              let focusedElement else {
            return nil
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &pid) == .success,
              pid != getpid(),
              let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }

        DiagnosticLog.write("AX host from focused element app=\(app.bundleIdentifier ?? "unknown"), pid=\(pid)")
        return app
    }

    private func findTextTargetElement(near element: AXUIElement) -> AXUIElement? {
        if isTextTargetElement(element) {
            return element
        }

        if let descendant = textTargetDescendant(of: element, depth: 0) {
            return descendant
        }

        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let parent = parentElement(of: current) else {
                break
            }

            if isTextTargetElement(parent) {
                return parent
            }

            if let siblingDescendant = textTargetDescendant(of: parent, depth: 0) {
                return siblingDescendant
            }

            current = parent
        }

        return nil
    }

    private func textTargetDescendant(of element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 8 else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return nil
        }

        for child in children.prefix(160) {
            if isTextTargetElement(child) {
                return child
            }

            if let descendant = textTargetDescendant(of: child, depth: depth + 1) {
                return descendant
            }
        }

        return nil
    }

    private func logChildSummaries(of element: AXUIElement, depth: Int, prefix: String) {
        guard depth < 2 else {
            return
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement],
              !children.isEmpty else {
            return
        }

        for (index, child) in children.prefix(12).enumerated() {
            DiagnosticLog.write("AX diagnostics \(prefix).\(index): \(elementSummary(child))")
            logChildSummaries(of: child, depth: depth + 1, prefix: "\(prefix).\(index)")
        }
    }

    private func elementSummary(_ element: AXUIElement) -> String {
        let role = stringAttribute(kAXRoleAttribute as String, from: element) ?? "unknown"
        let subrole = stringAttribute(kAXSubroleAttribute as String, from: element) ?? "none"
        let editable = boolAttribute(kAXIsEditableAttribute as String, from: element)
            .map { $0 ? "editable" : "not editable" } ?? "editable?"
        let valueLength = stringAttribute(kAXValueAttribute as String, from: element)
            .map { "value \($0.count)" } ?? "value?"
        let selectedLength = stringAttribute(kAXSelectedTextAttribute as String, from: element)
            .map { "selected \($0.count)" } ?? "selected?"
        let charCount = numberAttribute(kAXNumberOfCharactersAttribute as String, from: element)
            .map { "chars \($0)" } ?? "chars?"

        return "\(role) / \(subrole) / \(editable) / \(valueLength) / \(selectedLength) / \(charCount)"
    }

    private func parentElement(of element: AXUIElement?) -> AXUIElement? {
        guard let element else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        if let text = value as? String {
            return text
        }

        if let attributedText = value as? NSAttributedString {
            return attributedText.string
        }

        return nil
    }

    private func readableText(from element: AXUIElement) -> String? {
        for attribute in [
            kAXValueAttribute as String,
            kAXSelectedTextAttribute as String
        ] {
            if let text = stringAttribute(attribute, from: element),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }

        if let text = fullTextFromParameterizedRange(element),
           !text.isEmpty {
            return text
        }

        return nil
    }

    private func fullTextFromParameterizedRange(_ element: AXUIElement) -> String? {
        guard supportsParameterizedAttribute(kAXStringForRangeParameterizedAttribute as String, on: element),
              let characterCount = numberAttribute(kAXNumberOfCharactersAttribute as String, from: element),
              characterCount > 0 else {
            return nil
        }

        var range = CFRange(location: 0, length: min(characterCount, 20_000))
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else {
            return nil
        }

        return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func boolAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    private func numberAttribute(_ attribute: String, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return (value as? NSNumber)?.intValue
    }

    private func supportsParameterizedAttribute(_ attribute: String, on element: AXUIElement) -> Bool {
        var value: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &value) == .success,
              let attributes = value as? [String] else {
            return false
        }

        return attributes.contains(attribute)
    }

    private func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return false
        }

        return settable.boolValue
    }

    @discardableResult
    private func replaceByPasting(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previousItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            DiagnosticLog.write("replace paste failed, pasteboard rejected string")
            return false
        }

        sendKey(.maskCommand, virtualKey: 0)
        Thread.sleep(forTimeInterval: 0.04)
        sendKey(.maskCommand, virtualKey: 9)
        DiagnosticLog.write("replace paste issued, length=\(text.count)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let previousItems {
                pasteboard.clearContents()
                pasteboard.writeObjects(previousItems)
            }
        }

        return true
    }

    private func sendKey(_ modifier: CGEventFlags, virtualKey: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else {
            return
        }

        down.flags = modifier
        up.flags = modifier
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
