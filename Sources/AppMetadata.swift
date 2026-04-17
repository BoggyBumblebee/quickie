import Foundation

struct AppMetadata: Equatable {
    let appName: String
    let shortVersion: String
    let build: String

    static let current = AppMetadata(bundle: .main)

    init(bundle: Bundle) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        let displayName = infoDictionary["CFBundleDisplayName"] as? String
        let bundleName = infoDictionary["CFBundleName"] as? String
        appName = displayName ?? bundleName ?? "Quickie"
        shortVersion = infoDictionary["CFBundleShortVersionString"] as? String ?? "1.0"
        build = infoDictionary["CFBundleVersion"] as? String ?? "1"
    }

    var docsVersionString: String {
        "\(appName) \(shortVersion) (\(build))"
    }

    var aboutPanelVersionString: String {
        shortVersion
    }
}
