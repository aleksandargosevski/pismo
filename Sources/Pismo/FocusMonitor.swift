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
///
/// Overlay apps (launchers such as Raycast) show a focused panel without becoming the frontmost
/// app, so no activation is reported for them. They are observed separately: while one of them has
/// a focused window it takes precedence, and once it closes the frontmost app's layout is restored.
final class FocusMonitor {
    var onFocusChange: ((FocusContext) -> Void)?

    var overlayBundleIdentifiers: Set<String> = [] {
        didSet { syncOverlayObservers() }
    }

    private var isRunning = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var frontmostApp: ObservedApp?
    private var overlayApps: [pid_t: ObservedApp] = [:]
    private var activeOverlay: ObservedApp?
    private var lastReportedElement: AXUIElement?
    private var pendingEvaluation: DispatchWorkItem?

    /// Chromium builds its accessibility tree lazily after AXManualAccessibility is set.
    private let chromiumTreeDelay: TimeInterval = 0.3
    private let focusSettleDelay: TimeInterval = 0.08
    private let containerRoles: Set<String> = [kAXWindowRole, kAXApplicationRole, "AXWebArea"]
    private let containerSubroles: Set<String> = ["AXWebApplication"]
    private let overlayNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXFocusedUIElementChangedNotification,
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
    ]

    private var reportedApp: ObservedApp? { activeOverlay ?? frontmostApp }

    func start() {
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.observeFrontmost(app)
            },
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.syncOverlayObservers()
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                self?.syncOverlayObservers()
            },
        ]

        syncOverlayObservers()
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            observeFrontmost(frontmost)
        }
    }

    func stop() {
        isRunning = false
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
        frontmostApp = nil
        overlayApps = [:]
        activeOverlay = nil
        lastReportedElement = nil
    }

    /// Re-reports the current focus, e.g. after the config changed.
    func refresh() {
        guard let app = reportedApp else { return }
        report(app, element: focusedElement(of: app), force: true)
    }

    private func observeFrontmost(_ app: NSRunningApplication) {
        pendingEvaluation?.cancel()
        activeOverlay = nil
        lastReportedElement = nil

        let observed = ObservedApp(app, notifications: [kAXFocusedUIElementChangedNotification]) { [weak self] in
            self?.handleFocusNotification()
        }
        enableChromiumAccessibility(observed.element)
        frontmostApp = observed

        // Switching apps always applies a layout, even when no field is focused yet.
        report(observed, element: focusedElement(of: observed), force: true)
        scheduleEvaluation(after: chromiumTreeDelay)
    }

    private func syncOverlayObservers() {
        guard isRunning else { return }
        let running = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map(overlayBundleIdentifiers.contains) ?? false
        }
        let runningPids = Set(running.map(\.processIdentifier))

        overlayApps = overlayApps.filter { runningPids.contains($0.key) }
        for app in running where overlayApps[app.processIdentifier] == nil {
            overlayApps[app.processIdentifier] = ObservedApp(app, notifications: overlayNotifications) { [weak self] in
                self?.handleFocusNotification()
            }
        }

        if let activeOverlay, overlayApps[activeOverlay.pid] == nil {
            scheduleEvaluation(after: 0)
        }
    }

    private func handleFocusNotification() {
        scheduleEvaluation(after: focusSettleDelay)
    }

    private func scheduleEvaluation(after delay: TimeInterval) {
        pendingEvaluation?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluateFocus() }
        pendingEvaluation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func evaluateFocus() {
        let overlay = visibleOverlay()
        if overlay !== activeOverlay {
            activeOverlay = overlay
            // Like an app switch: opening an overlay applies its layout, closing it restores the app's.
            if let app = reportedApp {
                report(app, element: focusedElement(of: app), force: true)
            }
            return
        }

        guard let app = reportedApp,
              let element = focusedElement(of: app),
              !isContainer(element) else { return }
        report(app, element: element, force: false)
    }

    /// An overlay counts as open while it has a focused window. An overlay that is itself the
    /// frontmost app (e.g. its settings window) is handled as a regular app.
    private func visibleOverlay() -> ObservedApp? {
        overlayApps.values.first { overlay in
            overlay.pid != frontmostApp?.pid && AX.element(overlay.element, kAXFocusedWindowAttribute) != nil
        }
    }

    private func isContainer(_ element: AXUIElement) -> Bool {
        if let role = AX.string(element, kAXRoleAttribute), containerRoles.contains(role) { return true }
        if let subrole = AX.string(element, kAXSubroleAttribute), containerSubroles.contains(subrole) { return true }
        return false
    }

    /// Electron/Chromium apps (Slack, VS Code, ...) only expose their UI tree when asked explicitly.
    private func enableChromiumAccessibility(_ appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func focusedElement(of app: ObservedApp) -> AXUIElement? {
        AX.element(app.element, kAXFocusedUIElementAttribute)
    }

    private func report(_ observed: ObservedApp, element: AXUIElement?, force: Bool) {
        if !force, isSameElement(element, lastReportedElement) { return }
        lastReportedElement = element

        let context = FocusContext(
            appName: observed.name,
            bundleIdentifier: observed.app.bundleIdentifier,
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

/// An app's accessibility element with an observer for the given notifications. Observation stops
/// when the instance is released.
private final class ObservedApp {
    let app: NSRunningApplication
    let element: AXUIElement
    let onNotification: () -> Void
    private var observer: AXObserver?

    private static let messagingTimeout: Float = 0.5

    var pid: pid_t { app.processIdentifier }
    var name: String { app.localizedName ?? "pid \(app.processIdentifier)" }

    init(_ app: NSRunningApplication, notifications: [String], onNotification: @escaping () -> Void) {
        self.app = app
        self.element = AXUIElementCreateApplication(app.processIdentifier)
        self.onNotification = onNotification
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        observer = makeObserver(notifications: notifications)
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    private func makeObserver(notifications: [String]) -> AXObserver? {
        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, notificationCallback, &observer)
        guard createResult == .success, let observer else {
            NSLog("Pismo: cannot observe \(name) (AX error \(createResult.rawValue)); only its app rule applies")
            return nil
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in notifications {
            let result = AXObserverAddNotification(observer, element, notification as CFString, refcon)
            if result != .success {
                NSLog("Pismo: \(name) does not report \(notification) (AX error \(result.rawValue))")
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        return observer
    }
}

private func notificationCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    Unmanaged<ObservedApp>.fromOpaque(refcon).takeUnretainedValue().onNotification()
}
