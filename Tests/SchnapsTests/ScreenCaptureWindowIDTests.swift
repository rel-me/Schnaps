import AppKit
import Testing
@testable import Schnaps

@MainActor
private final class CaptureTestWindow: NSWindow {
    var testWindowNumber = 0
    override var windowNumber: Int { testWindowNumber }
}

@MainActor
@Test func screenCaptureUsesOnlyRepresentableWindowIDs() {
    _ = NSApplication.shared
    let window = CaptureTestWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)

    for number in [-1, 0, Int(CGWindowID.max) + 1] {
        window.testWindowNumber = number
        #expect(window.screenCaptureID == nil)
    }

    window.testWindowNumber = 42
    #expect(window.screenCaptureID == 42)
    window.testWindowNumber = Int(CGWindowID.max)
    #expect(window.screenCaptureID == CGWindowID.max)
}
