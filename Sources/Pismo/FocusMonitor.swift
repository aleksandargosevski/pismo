import AppKit
import ApplicationServices
import PismoCore

struct FocusContext {
    let appName: String
    let bundleIdentifier: String?
    let element: ElementSnapshot?
}

/// Reports the focused UI element whenever the frontmost app or its focused element changes.
///
/// Within an app, focus notifications are debounced and the app is then asked which element is
/// really focused: Chromium apps such as Slack emit bursts like text area → window right after a
/// field gains focus. Containers (windows, web areas) are ignored since nothing is typed into them,
/// and repeated reports for the same element are dropped, so a layout picked by hand stays until
/// focus actually moves to another field.
final class FocusMonitor {
    var onFocusChange: ((FocusContext) -> Void)?

    private var workspaceObserver: NSObjectProtocol?
    private var axObserver: AXObserver?
    private var observedApp: NSRunningApplication?
    private var observedAppElement: AXUIElement?
    private var lastReportedElement: AXUIElement?
    private var pendingEvaluation: DispatchWorkItem?

    /// Chromium builds its accessibility tree lazily after AXManualAccessibility is set.
    private let chromiumTreeDelay: TimeInterval = 0.3
    private let focusSettleDelay: TimeInterval = 0.08
    private let messagingTimeout: Float = 0.5
    private let containerRoles: Set<String> = [kAXWindowRole, kAXApplicationRole, "AXWebArea"]
    private let containerSubroles: Set<String> = ["AXWebApplication"]

    func start() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.observe(app)
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            observe(frontmost)
        }
    }

    func stop() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
        stopObservingCurrentApp()
    }

    /// Re-reports the current focus, e.g. after the config changed.
    func refresh() {
        guard let appElement = observedAppElement else { return }
        report(focusedElement(of: appElement), force: true)
    }

    fileprivate func handleFocusedElementChanged() {
        scheduleEvaluation(after: focusSettleDelay)
    }

    private func scheduleEvaluation(after delay: TimeInterval) {
        pendingEvaluation?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluateFocusedElement() }
        pendingEvaluation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluateFocusedElement() {
        guard let appElement = observedAppElement,
              let element = focusedElement(of: appElement),
              !isContainer(element) else { return }
        report(element, force: false)
    }

    private func isContainer(_ element: AXUIElement) -> Bool {
        if let role = AX.string(element, kAXRoleAttribute), containerRoles.contains(role) { return true }
        if let subrole = AX.string(element, kAXSubroleAttribute), containerSubroles.contains(subrole) { return true }
        return false
    }

    private func observe(_ app: NSRunningApplication) {
        stopObservingCurrentApp()
        observedApp = app

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        enableChromiumAccessibility(appElement)
        observedAppElement = appElement

        if let observer = makeFocusObserver(for: appElement, app: app) {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            axObserver = observer
        }

        // Switching apps always applies a layout, even when no field is focused yet.
        report(focusedElement(of: appElement), force: true)
        scheduleEvaluation(after: chromiumTreeDelay)
    }

    private func makeFocusObserver(for appElement: AXUIElement, app: NSRunningApplication) -> AXObserver? {
        let appName = app.localizedName ?? "pid \(app.processIdentifier)"

        var observer: AXObserver?
        let createResult = AXObserverCreate(app.processIdentifier, focusChangedCallback, &observer)
        guard createResult == .success, let observer else {
            NSLog("Pismo: cannot observe \(appName) (AX error \(createResult.rawValue)); only its app rule applies")
            return nil
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let addResult = AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)
        guard addResult == .success else {
            NSLog("Pismo: \(appName) does not report focus changes (AX error \(addResult.rawValue)); only its app rule applies")
            return nil
        }
        return observer
    }

    private func stopObservingCurrentApp() {
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        axObserver = nil
        observedApp = nil
        observedAppElement = nil
        lastReportedElement = nil
    }

    /// Electron/Chromium apps (Slack, VS Code, ...) only expose their UI tree when asked explicitly.
    private func enableChromiumAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func focusedElement(of appElement: AXUIElement) -> AXUIElement? {
        AX.element(appElement, kAXFocusedUIElementAttribute)
    }

    private func report(_ element: AXUIElement?, force: Bool) {
        guard let app = observedApp else { return }
        if !force, isSameElement(element, lastReportedElement) { return }
        lastReportedElement = element

        let context = FocusContext(
            appName: app.localizedName ?? "Unknown",
            bundleIdentifier: app.bundleIdentifier,
            element: element.map(ElementSnapshot.init)
        )
        onFocusChange?(context)
    }

    private func isSameElement(_ lhs: AXUIElement?, _ rhs: AXUIElement?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): CFEqual(lhs, rhs)
        default: false
        }
    }
}

private func focusChangedCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<FocusMonitor>.fromOpaque(refcon).takeUnretainedValue()
    monitor.handleFocusedElementChanged()
}
