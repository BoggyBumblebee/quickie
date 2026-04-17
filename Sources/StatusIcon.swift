import AppKit

enum StatusIcon {
    static func image() -> NSImage {
        if let image = NSImage(named: "StatusIcon") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        let fallback = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Quickie") ?? NSImage()
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }
}
