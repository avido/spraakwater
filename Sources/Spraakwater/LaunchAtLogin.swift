import ServiceManagement

/// Starts Spraakwater when you log in, through the system's login items.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The user still has to approve the item in System Settings.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
