import AppKit

@MainActor
enum OverlayLabelStyle {
    static let height: CGFloat = 28
    static let horizontalPadding: CGFloat = 11
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
    static let foreground = NSColor.white
    static let secondaryForeground = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1)

    private static let background = NSColor(srgbRed: 0.23, green: 0.23, blue: 0.23, alpha: 1)

    static func drawBackground(in frame: CGRect) {
        let radius = min(frame.width, frame.height) / 2
        background.setFill()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
    }
}
