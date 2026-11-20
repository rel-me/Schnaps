import AppKit
import MeasurementCore
import Testing
@testable import Schnaps

@MainActor
private func testSnapshot(scale: CGFloat = 1) throws -> ScreenSnapshot {
    let context = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
                                        bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 50, y: 50, width: 100, height: 100))
    let image = try #require(context.makeImage())
    return ScreenSnapshot(image: image, pixels: try #require(PixelBuffer(image: image)), scaleX: scale, scaleY: scale)
}

@MainActor @Suite(.serialized)
struct OverlayStartupTests {
    @Test func overlayAppearsBeforeCaptureAndIgnoresCancelledCapture() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousFreeze = defaults.object(forKey: PreferenceKey.freezeScreen)
        defaults.set(true, forKey: PreferenceKey.freezeScreen)
        defer {
            if let previousFreeze { defaults.set(previousFreeze, forKey: PreferenceKey.freezeScreen) }
            else { defaults.removeObject(forKey: PreferenceKey.freezeScreen) }
        }
        let screen = try #require(NSScreen.screens.first)
        let id = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).uint32Value
        let snapshot = try testSnapshot()
        let started = AsyncStream<Int>.makeStream()
        let finished = AsyncStream<Int>.makeStream()
        var starts = started.stream.makeAsyncIterator()
        var finishes = finished.stream.makeAsyncIterator()
        var gates: [CheckedContinuation<Void, Never>] = []
        let controller = OverlayController(captureScreens: {
            let index = gates.count
            await withCheckedContinuation { continuation in
                gates.append(continuation)
                started.continuation.yield(index)
            }
            finished.continuation.yield(index)
            return [id: snapshot]
        }, canCapture: { true })
        defer { controller.stop() }
        controller.toggle(mode: .findDimensions)
        #expect(controller.isActive)
        #expect(controller.windows.count == NSScreen.screens.count)
        #expect(controller.windows.allSatisfy { $0.isVisible })
        #expect(controller.windows.allSatisfy { $0.styleMask.contains(.nonactivatingPanel) })
        #expect(controller.windows.allSatisfy { !$0.canBecomeKey && !$0.canBecomeMain })
        #expect(gates.isEmpty) // Presentation is synchronous; capture has not even started.
        #expect(await starts.next() == 0)
        controller.stop()
        controller.toggle(mode: .findDimensions)
        #expect(await starts.next() == 1)
        gates[0].resume()
        #expect(await finishes.next() == 0)
        #expect(controller.windows.allSatisfy { ($0.contentView as? MeasurementView)?.captureSnapshot == nil })
        #expect(controller.windows.allSatisfy { !$0.canBecomeKey })
        let window = try #require(controller.windows.first { $0.screen == screen })
        let view = try #require(window.contentView as? MeasurementView)
        let point = view.convert(CGPoint(x: 100, y: 100), to: nil)
        let moveBeforeCapture = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseMoved(with: moveBeforeCapture)
        gates[1].resume()
        #expect(await finishes.next() == 1)
        #expect(view.captureSnapshot != nil)
        #expect(view.labelControls().isEmpty)
        #expect(controller.windows.allSatisfy { $0.canBecomeKey && $0.canBecomeMain })
    }

    @Test func findDimensionsLabelsUseScreenPointsOnRetinaAndHonorAspectRatioPreference() throws {
        let defaults = UserDefaults.standard
        let keys = [PreferenceKey.aspectDistance, PreferenceKey.aspectStyle, PreferenceKey.aspectArea,
            PreferenceKey.unit, PreferenceKey.showUnits, PreferenceKey.showIndicators]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("px", forKey: PreferenceKey.unit)
        defaults.set(false, forKey: PreferenceKey.showUnits)
        defaults.set(false, forKey: PreferenceKey.showIndicators)
        defaults.set(false, forKey: PreferenceKey.aspectArea)
        defaults.set(false, forKey: PreferenceKey.aspectDistance)
        defaults.set(AspectRatioStyle.commonOnly.rawValue, forKey: PreferenceKey.aspectStyle)
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let view = MeasurementView(frame: bounds, scale: 2, snapshot: try testSnapshot(scale: 2), mode: .findDimensions)
        let panel = NSPanel(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        defer { panel.close() }
        let point = CGPoint(x: 50, y: 50)
        func mouse(_ type: NSEvent.EventType) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }

        view.mouseMoved(with: try mouse(.mouseMoved))
        let baseText = try #require(view.labelControls().first { $0.target == .live }?.text)
        #expect(baseText == "50 × 50")
        let ratioText = baseText + "  1:1"
        defaults.set(true, forKey: PreferenceKey.aspectDistance)
        view.synchronizePreferences()
        #expect(view.labelControls().first { $0.target == .live }?.text == ratioText)

        view.mouseDown(with: try mouse(.leftMouseDown))
        view.mouseUp(with: try mouse(.leftMouseUp))
        #expect(view.labelControls().first { $0.target == .held }?.text == ratioText)
        let held = try #require(view.heldDimensions)
        view.pinnedDistances = [held.horizontal, held.vertical, held.horizontal]
        #expect(view.labelControls().first { $0.target == .distances(0, 2) }?.text == ratioText)
        let single = try #require(view.labelControls().first { $0.target == .distances(2, 1) })
        #expect(single.text == "50")

        view.pinned = [held.rect]
        #expect(view.labelControls().first { $0.target == .area(0) }?.text == "1  ·  50 × 50")
        let areaView = MeasurementView(frame: bounds, scale: 2, snapshot: nil, mode: .area)
        areaView.pinned = [held.rect]
        #expect(areaView.labelControls().first { $0.target == .area(0) }?.text == "1  ·  100 × 100")

        defaults.set(false, forKey: PreferenceKey.aspectDistance)
        view.synchronizePreferences()
        #expect(view.labelControls().first { $0.target == .held }?.text == baseText)
        #expect(view.labelControls().first { $0.target == .distances(0, 2) }?.text == baseText)
    }

    @Test func findDimensionsRefreshClearsMeasurementsOnAllDisplays() async throws {
        _ = NSApplication.shared
        let snapshot = try testSnapshot()
        let captured = AsyncStream<Void>.makeStream()
        var captures = captured.stream.makeAsyncIterator()
        let screen = try #require(NSScreen.screens.first)
        let id = try #require(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).uint32Value
        let controller = OverlayController(captureScreens: {
            captured.continuation.yield(())
            return [id: snapshot]
        }, canCapture: { true })
        defer { controller.stop() }
        controller.toggle(mode: .findDimensions)
        _ = await captures.next()
        let window = try #require(controller.windows.first { $0.screen == screen })
        let view = try #require(window.contentView as? MeasurementView)
        let dimensions = try #require(snapshot.dimensions(at: CGPoint(x: 100, y: 100), tolerance: 0))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: 100, y: view.bounds.height - 100), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) }
            else { view.mouseUp(with: event) }
        }
        try #require(view.heldDimensions != nil)
        for window in controller.windows {
            let view = try #require(window.contentView as? MeasurementView)
            view.pinned = [dimensions.rect]
            view.pinnedDistances = [dimensions.horizontal]
        }

        let refresh = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
        view.keyDown(with: refresh)
        let refreshedViews = controller.windows.compactMap { $0.contentView as? MeasurementView }
        #expect(refreshedViews.count == NSScreen.screens.count)
        for refreshed in refreshedViews {
            #expect(refreshed.mode == .findDimensions)
            #expect(refreshed.captureSnapshot == nil)
            #expect(refreshed.labelControls().isEmpty)
        }

        _ = await captures.next()
        let refreshed = try #require(controller.windows.first { $0.screen == screen }?.contentView as? MeasurementView)
        #expect(refreshed.captureSnapshot != nil)
        #expect(refreshed.heldDimensions == nil)
        #expect(refreshed.pinned.isEmpty)
        #expect(refreshed.pinnedDistances.isEmpty)
    }

    @Test func findDimensionsWaitsForCaptureBeforeDrawingMeasurement() throws {
        let size = 200
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        let view = MeasurementView(frame: frame, scale: 1, snapshot: nil, mode: .findDimensions)
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func alpha(at point: Int) -> UInt8 { pixels[(point * size + point) * 4 + 3] }
        func mouse(at point: Int) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: point, y: size - point),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0))
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        view.mouseMoved(with: try mouse(at: 100))
        view.draw(frame)
        #expect(alpha(at: 100) <= 3)
        #expect(view.labelControls().isEmpty)

        view.mouseMoved(with: try mouse(at: 120))
        view.draw(frame)
        #expect(alpha(at: 100) <= 3)
        #expect(alpha(at: 120) <= 3)

        view.updateSnapshot(try testSnapshot())
        #expect(view.labelControls().contains { $0.target == .live })
    }

    @Test func findDimensionsActivationIgnoresInitialPointerAndUnmatchedClick() throws {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let view = MeasurementView(frame: frame, scale: 2, snapshot: nil, mode: .findDimensions)
        panel.contentView = view
        let start = CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: 120, y: 110)
        func mouse(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
        }

        view.initializePointer(at: panel.convertPoint(toScreen: view.convert(start, to: nil)))
        view.mouseMoved(with: try mouse(.mouseMoved, at: start))
        view.updateSnapshot(try testSnapshot())
        #expect(view.labelControls().isEmpty)
        view.mouseMoved(with: try mouse(.mouseMoved, at: CGPoint(x: start.x + 0.25, y: start.y)))
        #expect(view.labelControls().isEmpty)

        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered,
            location: view.convert(moved, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        view.mouseEntered(with: enter)
        #expect(view.labelControls().isEmpty)

        view.mouseUp(with: try mouse(.leftMouseUp, at: start))
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: moved))
        #expect(view.heldDimensions == nil)
        #expect(view.selection == nil)
        #expect(view.labelControls().isEmpty)

        view.mouseMoved(with: try mouse(.mouseMoved, at: moved))
        #expect(view.labelControls().first?.target == .live)

        // Installing the frozen frame and taking focus resets the hover reading.
        view.initializePointer(at: panel.convertPoint(toScreen: view.convert(moved, to: nil)))
        view.mouseMoved(with: try mouse(.mouseMoved, at: moved))
        #expect(view.labelControls().isEmpty)

        // A deliberate click can still hold the reading at the startup location.
        view.mouseDown(with: try mouse(.leftMouseDown, at: moved))
        view.mouseUp(with: try mouse(.leftMouseUp, at: moved))
        #expect(view.labelControls().first?.target == .held)
    }

    @Test func frozenOverlayRedrawErasesPreviousMeasurement() throws {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let defaults = UserDefaults.standard
        let previousFreeze = defaults.object(forKey: PreferenceKey.freezeScreen)
        defaults.set(true, forKey: PreferenceKey.freezeScreen)
        defer {
            if let previousFreeze { defaults.set(previousFreeze, forKey: PreferenceKey.freezeScreen) }
            else { defaults.removeObject(forKey: PreferenceKey.freezeScreen) }
        }
        let context = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
            bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.fill(frame)
        let image = try #require(context.makeImage())
        let snapshot = ScreenSnapshot(image: image, pixels: try #require(PixelBuffer(image: image)), scaleX: 1, scaleY: 1)
        let view = MeasurementView(frame: frame, scale: 1, snapshot: snapshot, mode: .findDimensions)
        let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 100, y: 100),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.translateBy(x: 0, y: frame.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let pixels = try #require(context.data)
        func renderedPixels() -> Data { Data(bytes: pixels, count: context.bytesPerRow * context.height) }

        view.draw(frame)
        let background = renderedPixels()
        view.mouseMoved(with: event)
        #expect(view.labelControls().first?.target == .live)
        view.draw(frame)
        let drewMeasurement = renderedPixels() != background
        #expect(drewMeasurement)
        view.mouseExited(with: event)
        view.draw(frame)
        let restoredBackground = renderedPixels() == background
        #expect(restoredBackground)
    }

    @Test func measurementLabelDrawsWhiteTextInADarkCapsule() throws {
        let size = 240
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        let view = MeasurementView(frame: frame, scale: 1, snapshot: nil, mode: .area)
        view.pinned = [CGRect(x: 16, y: 92, width: 120, height: 80)]
        let label = try #require(view.labelControls().first?.label)
        let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func offset(_ x: Int, _ y: Int) -> Int { (y * size + x) * 4 }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        view.draw(frame)

        let corner = offset(Int(label.minX) + 1, Int(label.minY) + 1)
        #expect(pixels[corner + 3] < 10)
        let cap = offset(Int(label.minX) + 2, Int(label.midY))
        #expect(pixels[cap + 3] == 255)
        #expect((35...80).contains(pixels[cap]))
        let textPixels = (Int(label.minY)..<Int(label.maxY)).flatMap { y in
            (Int(label.minX)..<Int(label.maxX)).map { x in pixels[offset(x, y)] }
        }
        #expect(textPixels.filter { $0 > 220 }.count > 20)
    }

    @Test(arguments: [true, false])
    func frozenOverlayAcceptsKeyboardWhenCaptureIsUnavailable(permissionGranted: Bool) async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousFreeze = defaults.object(forKey: PreferenceKey.freezeScreen)
        defaults.set(true, forKey: PreferenceKey.freezeScreen)
        defer {
            if let previousFreeze { defaults.set(previousFreeze, forKey: PreferenceKey.freezeScreen) }
            else { defaults.removeObject(forKey: PreferenceKey.freezeScreen) }
        }
        struct CaptureFailure: Error {}
        let attempted = AsyncStream<Void>.makeStream()
        var attempts = attempted.stream.makeAsyncIterator()
        let controller = OverlayController(captureScreens: { throw CaptureFailure() },
                                           canCapture: {
                                               attempted.continuation.yield(())
                                               return permissionGranted
                                           })
        defer { controller.stop() }
        controller.toggle(mode: .area)
        #expect(controller.windows.allSatisfy { !$0.canBecomeKey })
        // The capture task must release focus even on errors or denied permission.
        _ = await attempts.next()
        #expect(!controller.windows.isEmpty)
        #expect(controller.windows.allSatisfy { $0.canBecomeKey && $0.canBecomeMain })
    }

    @Test func measurementsKeepOverlayColorAcrossBackgroundsAndHonorExplicitColorSwitch() throws {
        let defaults = UserDefaults.standard
        let previousContrast = defaults.object(forKey: PreferenceKey.autoContrast)
        defaults.set(true, forKey: PreferenceKey.autoContrast)
        defer {
            if let previousContrast { defaults.set(previousContrast, forKey: PreferenceKey.autoContrast) }
            else { defaults.removeObject(forKey: PreferenceKey.autoContrast) }
        }
        let primary = MeasurementPreferences.color(PreferenceKey.overlayColor)
        let alternative = MeasurementPreferences.color(PreferenceKey.alternativeColor)
        for mode in [MeasurementMode.findDimensions, .area] {
            for background in [primary, NSColor.white, NSColor.black] {
                let context = try #require(CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8,
                                                    bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(background.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
                let image = try #require(context.makeImage())
                let snapshot = ScreenSnapshot(image: image, pixels: try #require(PixelBuffer(image: image)), scaleX: 1, scaleY: 1)
                let view = MeasurementView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), scale: 1,
                                           snapshot: snapshot, mode: mode)
                #expect(view.measurementColor.schnapsHex == primary.schnapsHex)
                let toggle = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                          timestamp: 0, windowNumber: 0, context: nil,
                                                          characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
                view.keyDown(with: toggle)
                #expect(view.measurementColor.schnapsHex == alternative.schnapsHex)
                view.keyDown(with: toggle)
                #expect(view.measurementColor.schnapsHex == primary.schnapsHex)
            }
        }
    }

    @Test func automaticAreaSnapTracksModifiersAndAcceptsFirstFrameDuringDrag() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = MeasurementView(frame: CGRect(x: 0, y: 0, width: 200, height: 200),
                                   scale: 1, snapshot: nil, mode: .findDimensions)
        window.contentView = view
        func event(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: 200 - point.y),
                                           modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let start = CGPoint(x: 20, y: 20), end = CGPoint(x: 180, y: 180)
        #expect(!view.wantsLiveSnapshot)
        view.mouseMoved(with: try event(.mouseMoved, start))
        #expect(view.wantsLiveSnapshot)
        view.mouseDown(with: try event(.leftMouseDown, start))
        view.mouseDragged(with: try event(.leftMouseDragged, end))
        #expect(!view.wantsLiveSnapshot)
        #expect(view.showsSnapIndicator)
        #expect(view.selection != nil)
        #expect(!view.labelControls().contains { $0.target == .selection })
        view.mouseDragged(with: try event(.leftMouseDragged, end, flags: .option))
        #expect(!view.showsSnapIndicator)
        view.mouseDragged(with: try event(.leftMouseDragged, end, flags: .shift))
        #expect(!view.showsSnapIndicator)
        view.mouseDragged(with: try event(.leftMouseDragged, end))
        #expect(view.showsSnapIndicator)
        view.updateSnapshot(try testSnapshot())
        #expect(view.captureSnapshot != nil)
        view.mouseUp(with: try event(.leftMouseUp, end))
        #expect(view.showsSnapIndicator)
        #expect(view.labelControls().contains { $0.target == .selection })
        view.rightMouseDown(with: try event(.rightMouseDown, start))
        view.rightMouseDragged(with: try event(.rightMouseDragged, end))
        #expect(!view.showsSnapIndicator)
        #expect(!view.labelControls().contains { $0.target == .selection })
        view.rightMouseUp(with: try event(.rightMouseUp, end))
        #expect(!view.showsSnapIndicator)
        #expect(view.labelControls().contains { $0.target == .selection })
        view.rightMouseDown(with: try event(.rightMouseDown, end))
        view.rightMouseUp(with: try event(.rightMouseUp, end))
        #expect(view.wantsLiveSnapshot)
        view.mouseExited(with: try event(.mouseMoved, end))
        #expect(!view.wantsLiveSnapshot)

        // Completing an area before the first capture must still snap once it arrives.
        let pending = MeasurementView(frame: view.frame, scale: 1, snapshot: nil, mode: .findDimensions)
        window.contentView = pending
        pending.mouseDown(with: try event(.leftMouseDown, start))
        pending.mouseDragged(with: try event(.leftMouseDragged, end))
        pending.mouseUp(with: try event(.leftMouseUp, end))
        #expect(pending.showsSnapIndicator)
        pending.updateSnapshot(try testSnapshot())
        let captured = AsyncStream<CGRect>.makeStream()
        var capturedRegions = captured.stream.makeAsyncIterator()
        pending.onCapture = { region, _, _ in captured.continuation.yield(region) }
        let capture = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                   timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                   characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        pending.keyDown(with: capture)
        #expect(await capturedRegions.next() == CGRect(x: 50, y: 50, width: 100, height: 100))

        let area = MeasurementView(frame: view.frame, scale: 1, snapshot: try testSnapshot(), mode: .area)
        window.contentView = area
        area.mouseDown(with: try event(.leftMouseDown, start))
        area.mouseDragged(with: try event(.leftMouseDragged, end))
        #expect(!area.showsSnapIndicator)
        #expect(area.labelControls().contains { $0.target == .selection })
    }
}
