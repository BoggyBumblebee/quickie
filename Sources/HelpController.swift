import AppKit
import Foundation

enum HelpSection {
    case home
    case quickStart
    case troubleshooting

    var anchor: String? {
        switch self {
        case .home:
            nil
        case .quickStart:
            "quick-start"
        case .troubleshooting:
            "troubleshooting"
        }
    }
}

struct HelpURLResolver {
    var resourceURL: (_ resource: String, _ extensionName: String?, _ subdirectory: String?) -> URL?

    init(bundle: Bundle = .main) {
        resourceURL = { resource, extensionName, subdirectory in
            bundle.url(forResource: resource, withExtension: extensionName, subdirectory: subdirectory)
        }
    }

    init(resourceURL: @escaping (_ resource: String, _ extensionName: String?, _ subdirectory: String?) -> URL?) {
        self.resourceURL = resourceURL
    }

    func url(for section: HelpSection) -> URL? {
        guard let baseURL = resourceURL("index", "html", "Help") ?? resourceURL("index", "html", nil) else {
            return nil
        }

        guard let anchor = section.anchor else {
            return baseURL
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.fragment = anchor
        return components?.url
    }
}

@MainActor
final class HelpController {
    static let shared = HelpController()

    private let resolver: HelpURLResolver
    private let workspace: NSWorkspace

    init(resolver: HelpURLResolver = HelpURLResolver(), workspace: NSWorkspace = .shared) {
        self.resolver = resolver
        self.workspace = workspace
    }

    func open(_ section: HelpSection) {
        guard let url = resolver.url(for: section) else { return }
        workspace.open(url)
    }
}
