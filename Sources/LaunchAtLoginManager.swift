import Foundation
import ServiceManagement

enum LaunchAtLoginSettings {
    static let enabledKey = "LaunchAtLogin.enabled"
    static let defaultEnabled = true

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            enabledKey: defaultEnabled
        ])
    }

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: enabledKey)
    }
}

enum LaunchAtLoginServiceStatus {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
}

struct LaunchAtLoginState {
    let isEnabled: Bool
    let statusMessage: String?
    let errorMessage: String?
}

protocol LaunchAtLoginServicing {
    var launchAtLoginStatus: LaunchAtLoginServiceStatus { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LaunchAtLoginServicing {
    var launchAtLoginStatus: LaunchAtLoginServiceStatus {
        switch status {
        case .enabled:
            .enabled
        case .notRegistered:
            .notRegistered
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }
}

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let service: LaunchAtLoginServicing
    private let defaults: UserDefaults

    init(
        service: LaunchAtLoginServicing = SMAppService.mainApp,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
    }

    func synchronize() -> LaunchAtLoginState {
        apply(desiredEnabled: LaunchAtLoginSettings.isEnabled(defaults))
    }

    func currentState() -> LaunchAtLoginState {
        let desiredEnabled = LaunchAtLoginSettings.isEnabled(defaults)
        return makeState(desiredEnabled: desiredEnabled, errorMessage: nil)
    }

    func setEnabled(_ isEnabled: Bool) -> LaunchAtLoginState {
        apply(desiredEnabled: isEnabled)
    }

    private func apply(desiredEnabled: Bool) -> LaunchAtLoginState {
        do {
            switch (desiredEnabled, service.launchAtLoginStatus) {
            case (true, .enabled), (false, .notRegistered):
                break
            case (true, _):
                try service.register()
            case (false, _):
                try service.unregister()
            }

            LaunchAtLoginSettings.setEnabled(desiredEnabled, defaults: defaults)
            return makeState(desiredEnabled: desiredEnabled, errorMessage: nil)
        } catch {
            let revertedEnabled = serviceIndicatesEnabled
            LaunchAtLoginSettings.setEnabled(revertedEnabled, defaults: defaults)
            return makeState(
                desiredEnabled: revertedEnabled,
                errorMessage: "Quickie could not update Launch at Login. \(error.localizedDescription)"
            )
        }
    }

    private var serviceIndicatesEnabled: Bool {
        switch service.launchAtLoginStatus {
        case .enabled, .requiresApproval:
            true
        case .notRegistered, .notFound:
            false
        }
    }

    private func makeState(desiredEnabled: Bool, errorMessage: String?) -> LaunchAtLoginState {
        let statusMessage: String?

        if desiredEnabled {
            switch service.launchAtLoginStatus {
            case .enabled:
                statusMessage = "Quickie will open automatically after you sign in."
            case .requiresApproval:
                statusMessage = "macOS still needs approval to finish enabling Quickie at login. Check System Settings > General > Login Items."
            case .notFound:
                statusMessage = "Quickie could not find its login item registration."
            case .notRegistered:
                statusMessage = nil
            }
        } else {
            statusMessage = nil
        }

        return LaunchAtLoginState(
            isEnabled: desiredEnabled,
            statusMessage: statusMessage,
            errorMessage: errorMessage
        )
    }
}
