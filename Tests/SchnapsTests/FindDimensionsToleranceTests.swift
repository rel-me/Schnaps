import AppKit
import MeasurementCore
import Testing
@testable import Schnaps

extension OverlayStartupTests {
    @Test @MainActor func findDimensionsLabelShowsToleranceAndScrollAndKeyboardAdjustIt() throws {
        let defaults = UserDefaults.standard
        let keys = [PreferenceKey.selectedTolerance, PreferenceKey.tolerance,
            PreferenceKey.toleranceMedium, PreferenceKey.toleranceHigh, PreferenceKey.scrollTolerance]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(27, forKey: PreferenceKey.toleranceMedium)
        defaults.set(61, forKey: PreferenceKey.toleranceHigh)
        defaults.set(true, forKey: PreferenceKey.scrollTolerance)
        MeasurementPreferences.selectTolerance(.medium)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let context = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8,
            bytesPerRow: 3200, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 100, y: 100, width: 400, height: 400))
        let image = try #require(context.makeImage())
        let snapshot = ScreenSnapshot(image: image, pixels: try #require(PixelBuffer(image: image)), scaleX: 1, scaleY: 1)
        let view = MeasurementView(frame: bounds, scale: 1, snapshot: snapshot, mode: .findDimensions)
        let panel = NSPanel(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        defer { panel.close() }
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }
        func key(_ backward: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: backward ? [.shift] : [], timestamp: 0, windowNumber: panel.windowNumber,
                context: nil, characters: backward ? "T" : "t", charactersIgnoringModifiers: "t", isARepeat: false, keyCode: 17))
        }
        func scroll(_ delta: Int32, units: CGScrollEventUnit = .line, phase: CGScrollPhase? = nil,
                    momentum: CGMomentumScrollPhase? = nil) throws {
            let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: units,
                wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0))
            if let phase { cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue)) }
            if let momentum { cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue)) }
            view.scrollWheel(with: try #require(NSEvent(cgEvent: cgEvent)))
        }
        for point in [CGPoint(x: 2, y: 2), CGPoint(x: 798, y: 2),
                      CGPoint(x: 2, y: 598), CGPoint(x: 798, y: 598)] {
            view.mouseMoved(with: try mouse(.mouseMoved, at: point))
            let control = try #require(view.labelControls().first { $0.target == .live })
            let group = control.label
            #expect(control.close == nil)
            #expect(control.group == group)
            #expect(bounds.contains(group))
            #expect(group.maxX <= point.x - 8 || group.minX >= point.x + 8)
            #expect(group.maxY <= point.y - 8 || group.minY >= point.y + 8)
        }
        view.mouseMoved(with: try mouse(.mouseMoved, at: CGPoint(x: 200, y: 200)))
        let live = try #require(view.labelControls().first { $0.target == .live })
        #expect(live.detail == L("Med"))
        #expect(live.label.height == 28)
        #expect(bounds.contains(live.label))
        try scroll(-1, units: .pixel)
        #expect(MeasurementPreferences.selectedTolerance == .low)
        #expect(view.labelControls().first { $0.target == .live }?.detail == L("Low"))
        try scroll(8)
        #expect(MeasurementPreferences.selectedTolerance == .medium)
        try scroll(8)
        #expect(MeasurementPreferences.selectedTolerance == .high)
        #expect(view.labelControls().first { $0.target == .live }?.detail == L("High"))
        try scroll(-8)
        #expect(MeasurementPreferences.selectedTolerance == .medium)

        try scroll(-1, units: .pixel, phase: .began)
        #expect(MeasurementPreferences.selectedTolerance == .low)
        try scroll(-20, units: .pixel, phase: .changed)
        #expect(MeasurementPreferences.selectedTolerance == .low)
        try scroll(-25, units: .pixel, phase: .changed)
        #expect(MeasurementPreferences.selectedTolerance == .zero)
        try scroll(0, units: .pixel, phase: .ended)
        try scroll(80, units: .pixel, momentum: .begin)
        #expect(MeasurementPreferences.selectedTolerance == .zero)
        try scroll(1, units: .pixel, phase: .began)
        #expect(MeasurementPreferences.selectedTolerance == .low)
        try scroll(0, units: .pixel, phase: .ended)
        try scroll(1)
        #expect(MeasurementPreferences.selectedTolerance == .medium)
        view.keyDown(with: try key())
        #expect(MeasurementPreferences.selectedTolerance == .high)
        view.keyDown(with: try key(true))
        #expect(MeasurementPreferences.selectedTolerance == .medium)

        // The held measurement follows its axes after its label is dragged, not the drag start.
        let point = CGPoint(x: 200, y: 200)
        view.mouseDown(with: try mouse(.leftMouseDown, at: point))
        view.mouseUp(with: try mouse(.leftMouseUp, at: point))
        let held = try #require(view.labelControls().first { $0.target == .held })
        #expect(held.text == live.text)
        #expect(held.detail == nil)
        let start = CGPoint(x: held.label.midX, y: held.label.midY)
        let end = CGPoint(x: start.x + 10, y: start.y + 20)
        view.mouseDown(with: try mouse(.leftMouseDown, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: end))
        view.mouseUp(with: try mouse(.leftMouseUp, at: end))
        let heldY = try #require(view.heldDimensions?.horizontal.start.y)
        view.keyDown(with: try key())
        #expect(view.heldDimensions?.horizontal.start.y == heldY)
        let updatedHeld = try #require(view.labelControls().first { $0.target == .held })
        #expect(updatedHeld.detail == nil)
        defaults.set(false, forKey: PreferenceKey.scrollTolerance)
        view.synchronizePreferences()
        try scroll(-1)
        #expect(MeasurementPreferences.selectedTolerance == .high)
        // Keyboard controls remain available when scroll adjustment is disabled.
        view.keyDown(with: try key(true))
        #expect(MeasurementPreferences.selectedTolerance == .medium)

        view.rightMouseDown(with: try mouse(.rightMouseDown, at: point))
        view.rightMouseUp(with: try mouse(.rightMouseUp, at: point))
        #expect(view.labelControls().first { $0.target == .live }?.detail == L("Med"))
    }

    @Test @MainActor func areaMeasurementsOmitToleranceDetail() throws {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        for mode in [MeasurementMode.area, .findDimensions] {
            let view = MeasurementView(frame: bounds, scale: 1, snapshot: nil, mode: mode)
            view.pinned = [CGRect(x: 30, y: 30, width: 100, height: 100)]
            func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(with: type, location: point,
                    modifierFlags: [.option], timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            }
            view.mouseDown(with: try mouse(.leftMouseDown, at: CGPoint(x: 300, y: 300)))
            view.mouseDragged(with: try mouse(.leftMouseDragged, at: CGPoint(x: 450, y: 400)))
            view.mouseUp(with: try mouse(.leftMouseUp, at: CGPoint(x: 450, y: 400)))
            let active = try #require(view.labelControls().first { $0.target == .selection })
            #expect(active.detail == nil)
            #expect(bounds.contains(active.group))
            #expect(view.labelControls().first { $0.target == .area(0) }?.detail == nil)
        }
    }
}
