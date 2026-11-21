import AppKit
import MeasurementCore
import Testing
@testable import Schnaps

extension OverlayStartupTests {
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func repeatedFindDimensionsToAreaCopyKeepsRulersWithTheirTool(freeze: Bool) async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousFreeze = defaults.object(forKey: PreferenceKey.freezeScreen)
        defaults.set(freeze, forKey: PreferenceKey.freezeScreen)
        defer { defaults.set(previousFreeze, forKey: PreferenceKey.freezeScreen) }

        let screen = try #require(NSScreen.screens.first)
        let displayID = DesignTools.displayID(screen)
        let snapshot = try testSnapshot()
        let captures = AsyncStream<Void>.makeStream()
        var captured = captures.stream.makeAsyncIterator()
        let exports = AsyncStream<CGRect>.makeStream()
        var exported = exports.stream.makeAsyncIterator()
        let controller = OverlayController(captureScreens: {
            captures.continuation.yield(())
            return [displayID: snapshot]
        }, canCapture: { true }, exportScreenshot: { _, region, copy, _ in
            #expect(copy)
            exports.continuation.yield(region)
        })
        defer { controller.stop() }

        let span = DimensionSpan(start: CGPoint(x: 80, y: 30), end: CGPoint(x: 80, y: 160))
        let region = CGRect(x: 30, y: 30, width: 80, height: 90)
        for iteration in 0..<16 {
            controller.toggle(mode: .findDimensions)
            _ = await captured.next()
            let dimensionsWindow = try #require(controller.windows.first { $0.displayID == displayID })
            let dimensions = dimensionsWindow.measurementView
            if iteration == 0 { dimensions.pinnedDistances = [span] }
            #expect(dimensions.pinnedDistances == [span])
            try drawArea(region, in: dimensionsWindow) // Unpinned selection must die with this tool.
            dimensionsWindow.displayIfNeeded()

            if iteration.isMultiple(of: 2) {
                try sendKey("s", code: 1, to: dimensionsWindow)
            } else {
                controller.toggle(mode: .area)
                _ = await captured.next()
                #expect(dimensionsWindow.contentView == nil)
            }
            let areaWindow = try #require(controller.windows.first { $0.displayID == displayID })
            #expect(areaWindow.measurementView.mode == .area)
            #expect(areaWindow.measurementView.labelControls().isEmpty)
            try drawArea(region, in: areaWindow)
            try sendKey("c", code: 8, to: areaWindow)
            try sendKey("c", code: 8, to: areaWindow)
            #expect(await exported.next() == region)
            if !freeze { _ = await captured.next() }
            #expect(!controller.isActive)
            #expect(!areaWindow.isVisible && areaWindow.contentView == nil)
            #expect(areaWindow.measurementView.captureSnapshot == nil)
            #expect(areaWindow.measurementView.labelControls().isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func outOfOrderExportCompletionsCannotAffectNewToolsOrCopies() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousFreeze = defaults.object(forKey: PreferenceKey.freezeScreen)
        defaults.set(false, forKey: PreferenceKey.freezeScreen)
        defer { defaults.set(previousFreeze, forKey: PreferenceKey.freezeScreen) }
        struct CaptureFailure: Error {}
        let id = DesignTools.displayID(try #require(NSScreen.screens.first))
        let snapshot = try testSnapshot()
        let captures = AsyncStream<Int>.makeStream()
        var captured = captures.stream.makeAsyncIterator()
        let completions = AsyncStream<Int>.makeStream()
        var completed = completions.stream.makeAsyncIterator()
        var gates: [CheckedContinuation<Bool, Never>] = []
        var exportCount = 0
        let controller = OverlayController(captureScreens: {
            let index = gates.count
            let success = await withCheckedContinuation { continuation in
                gates.append(continuation)
                captures.continuation.yield(index)
            }
            completions.continuation.yield(index)
            guard success else { throw CaptureFailure() }
            return [id: snapshot]
        }, canCapture: { true }, exportScreenshot: { _, _, _, _ in exportCount += 1 })
        defer { controller.stop() }
        let region = CGRect(x: 30, y: 30, width: 80, height: 90)

        for iteration in 0..<8 {
            let initial = gates.count
            controller.toggle(mode: .area)
            #expect(await captured.next() == initial)
            gates[initial].resume(returning: true)
            #expect(await completed.next() == initial)
            let first = try #require(controller.windows.first { $0.displayID == id })
            try drawArea(region, in: first)
            try sendKey("c", code: 8, to: first)
            #expect(await captured.next() == initial + 1)
            #expect(first.measurementView.isPresentationSuppressed)

            let next: OverlayWindow
            let freshExport: Int
            if iteration.isMultiple(of: 2) {
                try sendKey("s", code: 1, to: first)
                #expect(!first.measurementView.isPresentationSuppressed)
                try sendKey("s", code: 1, to: first)
                next = first
                freshExport = initial + 2
            } else {
                try sendKey("\u{1b}", code: 53, to: first)
                #expect(first.contentView == nil)
                controller.toggle(mode: .area)
                #expect(await captured.next() == initial + 2)
                gates[initial + 2].resume(returning: true)
                #expect(await completed.next() == initial + 2)
                next = try #require(controller.windows.first { $0.displayID == id })
                freshExport = initial + 3
            }
            try drawArea(region, in: next)
            try sendKey("c", code: 8, to: next)
            #expect(await captured.next() == freshExport)

            // Alternate late successes and errors, during a new copy and after dismissal.
            if iteration.isMultiple(of: 3) {
                gates[initial + 1].resume(returning: true)
                #expect(await completed.next() == initial + 1)
                #expect(next.measurementView.isPresentationSuppressed)
                #expect(exportCount == iteration)
            }
            gates[freshExport].resume(returning: true)
            #expect(await completed.next() == freshExport)
            if !iteration.isMultiple(of: 3) {
                gates[initial + 1].resume(returning: false)
                #expect(await completed.next() == initial + 1)
            }
            #expect(exportCount == iteration + 1)
            #expect(!controller.isActive)
            #expect(!next.isVisible && next.contentView == nil)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aLiveFrameInFlightCannotReplaceTheNewToolsSample() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let previousFreeze = defaults.object(forKey: PreferenceKey.freezeScreen)
        defaults.set(false, forKey: PreferenceKey.freezeScreen)
        defer { defaults.set(previousFreeze, forKey: PreferenceKey.freezeScreen) }
        let id = DesignTools.displayID(try #require(NSScreen.screens.first))
        let initial = try testSnapshot()
        let outdated = try testSnapshot(scale: 2)
        let first = AsyncStream<Void>.makeStream()
        var startup = first.stream.makeAsyncIterator()
        let live = AsyncStream<Void>.makeStream()
        var sampling = live.stream.makeAsyncIterator()
        let returned = AsyncStream<Void>.makeStream()
        var sampled = returned.stream.makeAsyncIterator()
        var requestedInitial = false
        var inFlight: CheckedContinuation<Void, Never>?
        let controller = OverlayController(captureScreens: {
            if !requestedInitial {
                requestedInitial = true
                first.continuation.yield(())
                return [id: initial]
            }
            await withCheckedContinuation { continuation in
                inFlight = continuation
                live.continuation.yield(())
            }
            returned.continuation.yield(())
            return [id: outdated]
        }, canCapture: { true })
        defer { controller.stop() }
        controller.toggle(mode: .findDimensions)
        _ = await startup.next()
        let window = try #require(controller.windows.first { $0.displayID == id })
        let view = window.measurementView
        let move = try #require(NSEvent.mouseEvent(with: .mouseMoved,
            location: view.convert(CGPoint(x: 100, y: 100), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseMoved(with: move)
        _ = await sampling.next()
        try sendKey("s", code: 1, to: window)
        inFlight?.resume()
        _ = await sampled.next()
        #expect(view.mode == .area)
        #expect(view.captureSnapshot?.scaleX == initial.scaleX)
        #expect(view.labelControls().isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHNAPS_TEST_WINDOW_SERVER"] == "1"),
          .timeLimit(.minutes(1)))
    func windowServerCopyStressKeepsOldRulerPixelsOffTheDisplayAndOutOfTheExport() async throws {
        _ = NSApplication.shared
        try #require(CGPreflightScreenCaptureAccess())
        let defaults = UserDefaults.standard
        let previousFreeze = defaults.object(forKey: PreferenceKey.freezeScreen)
        defer { defaults.set(previousFreeze, forKey: PreferenceKey.freezeScreen) }

        let screen = try #require(NSScreen.screens.first)
        let displayID = DesignTools.displayID(screen)
        let sample = CGRect(x: 60, y: 70, width: 180, height: 145)
        let backdrop = NSPanel(contentRect: CGRect(x: screen.frame.minX + 40, y: screen.frame.maxY - 240,
            width: 220, height: 190), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.level = .floating
        backdrop.backgroundColor = .green
        backdrop.hasShadow = false
        backdrop.orderFrontRegardless()
        defer { backdrop.close() }

        let captures = AsyncStream<Void>.makeStream()
        var captured = captures.stream.makeAsyncIterator()
        let exports = AsyncStream<Bool>.makeStream()
        var exported = exports.stream.makeAsyncIterator()
        func sceneIsClean(_ snapshot: ScreenSnapshot, region: CGRect) throws -> Bool {
            let image = try ScreenshotExport.image(snapshot: snapshot, region: region, togglePadding: false,
                                                    padding: 0, scaleTo1x: false)
            let pixels = try #require(PixelBuffer(image: image))
            let center = (pixels.height / 2 * pixels.width + pixels.width / 2) * 4
            let green = Int(pixels.bytes[center + 1])
            return green > Int(pixels.bytes[center]) + 100
                && green > Int(pixels.bytes[center + 2]) + 100
                && pixels.objectBounds(in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height),
                                       tolerance: 12) == nil
        }
        let controller = OverlayController(captureScreens: {
            defer { captures.continuation.yield(()) }
            return try await ScreenSnapshot.capture()
        }, canCapture: { true }, exportScreenshot: { snapshot, region, copy, _ in
            try exports.continuation.yield(copy && sceneIsClean(snapshot, region: region))
        })
        defer { controller.stop() }

        for iteration in 0..<8 {
            let freeze = iteration.isMultiple(of: 2)
            defaults.set(freeze, forKey: PreferenceKey.freezeScreen)
            controller.toggle(mode: .findDimensions)
            _ = await captured.next()
            let old = try #require(controller.windows.first { $0.displayID == displayID })
            try #require(old.measurementView.captureSnapshot != nil)
            old.measurementView.pinnedDistances = [
                DimensionSpan(start: CGPoint(x: 150, y: 85), end: CGPoint(x: 150, y: 200))
            ]
            old.displayIfNeeded()
            let oldID = old.windowNumber
            if iteration == 0 {
                let visible = try await ScreenSnapshot.capture()
                let marked = try #require(visible[displayID])
                #expect(try !sceneIsClean(marked, region: sample))
            }

            controller.toggle(mode: .area)
            _ = await captured.next()
            let area = try #require(controller.windows.first { $0.displayID == displayID })
            try #require(area.measurementView.captureSnapshot != nil)
            try drawArea(sample, in: area)
            area.displayIfNeeded()
            let areaID = area.windowNumber
            try sendKey("c", code: 8, to: area)
            #expect(await exported.next() == true)
            if !freeze { _ = await captured.next() }

            let onscreen = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
            let visibleIDs = try #require(onscreen).compactMap { $0[kCGWindowNumber as String] as? Int }
            #expect(!visibleIDs.contains(oldID) && !visibleIDs.contains(areaID))
            let desktop = try await ScreenSnapshot.capture()
            let dismissed = try #require(desktop[displayID])
            #expect(try sceneIsClean(dismissed, region: sample))
        }
    }

    private func drawArea(_ rect: CGRect, in window: OverlayWindow) throws {
        let view = window.measurementView
        for (type, point) in [(NSEvent.EventType.leftMouseDown, rect.origin),
                              (.leftMouseDragged, CGPoint(x: rect.maxX, y: rect.maxY)),
                              (.leftMouseUp, CGPoint(x: rect.maxX, y: rect.maxY))] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                modifierFlags: [.option], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseDragged: view.mouseDragged(with: event)
            default: view.mouseUp(with: event)
            }
        }
    }

    private func sendKey(_ key: String, code: UInt16, to window: OverlayWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: key,
            charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
        window.measurementView.keyDown(with: event)
    }
}
