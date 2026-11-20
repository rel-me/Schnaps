import AppKit

@MainActor
enum OverlayCloseButton {
    static let spacing: CGFloat = 3

    static func frame(beside label: CGRect) -> CGRect {
        CGRect(x: label.maxX + spacing, y: label.minY, width: label.height, height: label.height)
    }

    static func draw(in frame: CGRect) {
        OverlayLabelStyle.drawBackground(in: frame)

        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [OverlayLabelStyle.foreground]))
        guard let icon = NSImage(systemSymbolName: "xmark", accessibilityDescription: L("Close"))?
            .withSymbolConfiguration(configuration) else { return }
        let rect = CGRect(origin: CGPoint(x: frame.midX - icon.size.width / 2,
                                          y: frame.midY - icon.size.height / 2), size: icon.size)
        icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
