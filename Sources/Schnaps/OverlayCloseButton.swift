import AppKit

@MainActor
enum OverlayCloseButton {
    static let spacing: CGFloat = 3

    static func frame(beside label: CGRect) -> CGRect {
        CGRect(x: label.maxX + spacing, y: label.minY, width: label.height, height: label.height)
    }

    static func draw(in frame: CGRect) {
        let crossColor = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.17, alpha: 1)
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [crossColor, OverlayLabelStyle.foreground]))
        guard let icon = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L("Close"))?
            .withSymbolConfiguration(configuration) else { return }
        let rect = CGRect(origin: CGPoint(x: frame.midX - icon.size.width / 2,
                                          y: frame.midY - icon.size.height / 2), size: icon.size)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
