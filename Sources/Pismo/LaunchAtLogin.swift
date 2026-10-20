import ServiceManagement

enum LaunchAtLogin {
    /// Homebrew moves the app to a new Cellar path on every upgrade, which would break a login item
    /// registered for the old path, so Homebrew installs start at login via `brew services` instead.
    static var isManagedByHomebrew: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path.contains("/Cellar/")
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
