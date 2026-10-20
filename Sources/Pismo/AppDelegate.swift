import AppKit
import PismoCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let focusMonitor = FocusMonitor()
    private let configStore = ConfigStore()
    private let inspectorLog = InspectorLog()
    private var statusItem: NSStatusItem?
    private var trustPollTimer: Timer?
    private var isPaused = false

    private var lastContext: FocusContext?
    private var lastDecision: LayoutDecision?
    private var lastReport: String?

    private let decisionMenuItem = NSMenuItem(title: "No focused field yet", action: nil, keyEquivalent: "")
    private let lastFieldMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let configMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let accessibilityMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var fieldRuleMenuItem = makeMenuItem("", action: #selector(addFieldRule), key: "f")
    private lazy var appRuleMenuItem = makeMenuItem("", action: #selector(setAppRule), key: "a")
    private lazy var removeRuleMenuItem = makeMenuItem("", action: #selector(removeFieldRule))
    private lazy var pauseMenuItem = makeMenuItem("Pause", action: #selector(togglePause), key: "p")
    private lazy var launchAtLoginMenuItem = makeMenuItem("Launch at Login", action: #selector(toggleLaunchAtLogin))

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        inspectorLog.write(InspectorReport.describeLayouts(InputSources.selectableKeyboardLayouts()))

        configStore.onChange = { [weak self] state in self?.handleConfigChange(state) }
        configStore.start()

        if Accessibility.isTrusted(prompt: true) {
            startMonitoring()
        } else {
            waitForAccessibilityPermission()
        }
    }

    private func startMonitoring() {
        accessibilityMenuItem.title = "Accessibility: granted"
        focusMonitor.onFocusChange = { [weak self] context in
            self?.handleFocusChange(context)
        }
        focusMonitor.start()
    }

    private func waitForAccessibilityPermission() {
        accessibilityMenuItem.title = "Accessibility: waiting for permission…"
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard Accessibility.isTrusted(prompt: false) else { return }
            timer.invalidate()
            self?.startMonitoring()
        }
    }

    private func handleFocusChange(_ context: FocusContext) {
        let decision = configStore.config.map {
            RuleEngine.decide(config: $0, bundleIdentifier: context.bundleIdentifier, element: context.element)
        }
        lastContext = context
        lastDecision = decision

        let report = InspectorReport.describe(context, decision: decision)
        lastReport = report
        lastFieldMenuItem.title = InspectorReport.summarize(context)
        inspectorLog.write(report)

        guard let decision else {
            decisionMenuItem.title = "No valid config"
            return
        }
        decisionMenuItem.title = "\(decision.layout) · \(InspectorReport.describe(decision.reason))"

        guard !isPaused else { return }
        do {
            try InputSources.select(decision.layout)
        } catch {
            decisionMenuItem.title = "⚠️ \(error.localizedDescription)"
            inspectorLog.write("Error: \(error.localizedDescription)")
        }
    }

    private func handleConfigChange(_ state: ConfigStore.State) {
        configMenuItem.toolTip = nil
        switch state {
        case .loaded(let config):
            let available = InputSources.selectableKeyboardLayouts()
            let missing = config.referencedLayouts.filter { reference in !available.contains { $0.matches(reference) } }
            if missing.isEmpty {
                configMenuItem.title = "Config: OK"
            } else {
                configMenuItem.title = "⚠️ Unknown layouts: \(missing.sorted().joined(separator: ", "))"
                inspectorLog.write("Config warning: unknown layouts \(missing.sorted()); enabled: \(available.map(\.name))")
            }
        case .failed(let error, let lastValid):
            let suffix = lastValid == nil ? "" : " (using previous config)"
            configMenuItem.title = "⚠️ Config error\(suffix)"
            configMenuItem.toolTip = error.localizedDescription
            inspectorLog.write("Config error: \(error.localizedDescription)")
        }
        focusMonitor.refresh()
    }

    // MARK: - Menu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(decisionMenuItem)
        menu.addItem(lastFieldMenuItem)
        menu.addItem(.separator())
        menu.addItem(fieldRuleMenuItem)
        menu.addItem(appRuleMenuItem)
        menu.addItem(removeRuleMenuItem)
        menu.addItem(.separator())
        menu.addItem(pauseMenuItem)
        menu.addItem(.separator())
        menu.addItem(configMenuItem)
        menu.addItem(makeMenuItem("Open Config", action: #selector(openConfig), key: ","))
        menu.addItem(makeMenuItem("Reload Config", action: #selector(reloadConfig), key: "r"))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem("Copy Last Field Info", action: #selector(copyLastFieldInfo), key: "c"))
        menu.addItem(makeMenuItem("Open Inspector Log", action: #selector(openInspectorLog), key: "l"))
        menu.addItem(.separator())
        if !LaunchAtLogin.isManagedByHomebrew {
            menu.addItem(launchAtLoginMenuItem)
        }
        menu.addItem(accessibilityMenuItem)
        menu.addItem(makeMenuItem("Open Accessibility Settings", action: #selector(openAccessibilitySettings)))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Pismo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        [decisionMenuItem, lastFieldMenuItem, configMenuItem, accessibilityMenuItem].forEach { $0.isEnabled = false }
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateRuleMenuItems()
        updateLaunchAtLoginMenuItem()
    }

    private func updateRuleMenuItems() {
        let layout = InputSources.current()?.name ?? "?"
        let appName = lastContext?.appName ?? "App"
        let canEdit = lastContext?.bundleIdentifier != nil && configStore.isValid

        fieldRuleMenuItem.title = "Use \"\(layout)\" for This Field in \(appName)"
        fieldRuleMenuItem.isEnabled = canEdit && lastContext?.element != nil

        if layout == configStore.config?.defaultLayout {
            appRuleMenuItem.title = "Use Default (\"\(layout)\") for \(appName)"
        } else {
            appRuleMenuItem.title = "Use \"\(layout)\" for \(appName)"
        }
        appRuleMenuItem.isEnabled = canEdit

        if case .field(let name) = lastDecision?.reason {
            removeRuleMenuItem.title = "Remove Rule \"\(name)\""
            removeRuleMenuItem.isHidden = false
            removeRuleMenuItem.isEnabled = canEdit
        } else {
            removeRuleMenuItem.isHidden = true
        }
    }

    private func updateLaunchAtLoginMenuItem() {
        switch LaunchAtLogin.status {
        case .enabled:
            launchAtLoginMenuItem.title = "Launch at Login"
            launchAtLoginMenuItem.state = .on
        case .requiresApproval:
            launchAtLoginMenuItem.title = "Launch at Login (approve in System Settings)"
            launchAtLoginMenuItem.state = .mixed
        default:
            launchAtLoginMenuItem.title = "Launch at Login"
            launchAtLoginMenuItem.state = .off
        }
    }

    private func makeMenuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func addFieldRule() {
        guard let bundleIdentifier = lastContext?.bundleIdentifier,
              let element = lastContext?.element,
              let layout = InputSources.current()?.name else { return }

        let rule = RuleSuggestion.fieldRule(for: element, layout: layout)
        editConfig { $0.addFieldRule(rule, for: bundleIdentifier) }
    }

    @objc private func setAppRule() {
        guard let bundleIdentifier = lastContext?.bundleIdentifier,
              let layout = InputSources.current()?.name else { return }
        editConfig { $0.setAppLayout(layout, for: bundleIdentifier) }
    }

    @objc private func removeFieldRule() {
        guard let bundleIdentifier = lastContext?.bundleIdentifier,
              case .field(let name) = lastDecision?.reason else { return }
        editConfig { document in
            guard document.removeFieldRule(named: name, for: bundleIdentifier) else {
                throw ConfigError.invalidRule(path: "apps.\(bundleIdentifier)", reason: "no rule named \"\(name)\"")
            }
        }
    }

    private func editConfig(_ edit: (inout ConfigDocument) throws -> Void) {
        do {
            try configStore.update(edit)
        } catch {
            showError("Cannot update config", error)
        }
    }

    @objc private func togglePause() {
        isPaused.toggle()
        pauseMenuItem.state = isPaused ? .on : .off
        statusItem?.button?.appearsDisabled = isPaused
        if !isPaused { focusMonitor.refresh() }
    }

    @objc private func toggleLaunchAtLogin() {
        switch LaunchAtLogin.status {
        case .requiresApproval:
            LaunchAtLogin.openLoginItemsSettings()
        case .enabled:
            setLaunchAtLogin(false)
        default:
            setLaunchAtLogin(true)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            showError("Cannot \(enabled ? "enable" : "disable") Launch at Login", error)
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configStore.fileURL)
    }

    @objc private func reloadConfig() {
        configStore.reload(force: true)
    }

    @objc private func copyLastFieldInfo() {
        guard let lastReport else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastReport, forType: .string)
    }

    @objc private func openInspectorLog() {
        NSWorkspace.shared.open(inspectorLog.fileURL)
    }

    @objc private func openAccessibilitySettings() {
        Accessibility.openSettings()
    }

    private func showError(_ title: String, _ error: Error) {
        inspectorLog.write("Error: \(title): \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
