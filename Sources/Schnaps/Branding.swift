import AppKit

@MainActor
enum AppBranding {
    static func icon(dark: Bool) -> NSImage? {
        let name = dark ? "Schnaps-Mark-Dark" : "Schnaps-Mark"
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }

    private static var appearanceObservation: NSKeyValueObservation?

    static func installIcon() {
        updateApplicationIcon()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor in updateApplicationIcon() }
        }
    }

    private static func updateApplicationIcon() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard let mark = icon(dark: dark) else { return }
        NSApp.applicationIconImage = mark
        registerApplicationImage(mark)
    }

    static func registerApplicationImage(_ image: NSImage) {
        // Sparkle 2.10's dialogs resolve the named application image in this process.
        if let cached = NSImage(named: NSImage.applicationIconName) {
            guard cached !== image else { return }
            _ = cached.setName(nil)
        }
        _ = image.setName(NSImage.applicationIconName)
    }
}
