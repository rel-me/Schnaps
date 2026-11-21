import AppKit
import MeasurementCore
import QuartzCore

@MainActor
final class OverlayController: NSObject {
    private struct Pins {
        var areas: [CGRect]
        var distances: [DimensionSpan]
    }

    @MainActor
    private final class Session {
        var mode: MeasurementMode
        let freeze: Bool
        let previousApp: NSRunningApplication?
        let windows: [OverlayWindow]
        var initialCapture: Task<Void, Never>?
        var liveCapture: Task<Void, Never>?
        var export: Task<Void, Never>?

        init(mode: MeasurementMode, freeze: Bool, previousApp: NSRunningApplication?, windows: [OverlayWindow]) {
            self.mode = mode
            self.freeze = freeze
            self.previousApp = previousApp
            self.windows = windows
        }

        func setPresentationSuppressed(_ suppressed: Bool) {
            for window in windows {
                window.measurementView.isPresentationSuppressed = suppressed
                window.displayIfNeeded()
            }
        }
    }

    private var session: Session?
    private var pins: [MeasurementMode: [CGDirectDisplayID: Pins]] = [:]
    private let captureScreens: @MainActor () async throws -> [CGDirectDisplayID: ScreenSnapshot]
    private let canCapture: @MainActor () -> Bool
    private let exportScreenshot: @MainActor (ScreenSnapshot, CGRect, Bool, Bool) throws -> Void
    var onActivationChanged: ((Bool) -> Void)?
    var onStateChanged: ((MeasurementMode?) -> Void)?
    var windows: [OverlayWindow] { session?.windows ?? [] }
    var isActive: Bool { session != nil }

    init(
        captureScreens: @escaping @MainActor () async throws -> [CGDirectDisplayID: ScreenSnapshot] = ScreenSnapshot.capture,
        canCapture: @escaping @MainActor () -> Bool = {
            ScreenRecordingPermission.shared.refresh()
            return ScreenRecordingPermission.shared.granted
        },
        exportScreenshot: @escaping @MainActor (ScreenSnapshot, CGRect, Bool, Bool) throws -> Void = { snapshot, region, copy, togglePadding in
            _ = try ScreenshotExport.export(snapshot: snapshot, region: region, copy: copy, togglePadding: togglePadding)
        }
    ) {
        self.captureScreens = captureScreens
        self.canCapture = canCapture
        self.exportScreenshot = exportScreenshot
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func preferencesChanged() {
        for window in windows { window.measurementView.synchronizePreferences() }
    }

    func toggle(mode: MeasurementMode = .area) {
        if session?.mode == mode {
            stop()
            return
        }
        restart(mode: mode)
    }

    private func restart(mode: MeasurementMode, clearPins: Bool = false) {
        let previousApp = session?.previousApp ?? NSWorkspace.shared.frontmostApplication
        stop(restoreFocus: false)
        if clearPins { pins[mode] = nil }
        let freeze = UserDefaults.standard.bool(forKey: PreferenceKey.freezeScreen)
        let windows = NSScreen.screens.map { OverlayWindow(screen: $0, mode: mode, freeze: freeze) }
        guard !windows.isEmpty else { return }
        let session = Session(mode: mode, freeze: freeze, previousApp: previousApp, windows: windows)
        self.session = session
        restorePins(in: session)

        let pointer = NSEvent.mouseLocation
        for window in windows {
            let view = window.measurementView
            view.isPresentationSuppressed = true
            view.onModeChanged = { [weak self, weak session] mode in
                guard let self, let session, self.session === session else { return }
                self.switchMode(to: mode, in: session)
            }
            view.onClear = { [weak self, weak session] in
                guard let self, let session, self.session === session else { return }
                self.pins.removeAll()
                for window in session.windows { window.measurementView.clearMeasurements() }
            }
            view.onClose = { [weak self, weak session] in
                guard let self, let session, self.session === session else { return }
                self.stop()
            }
            view.onRefresh = { [weak self, weak session] in
                guard let self, let session, self.session === session else { return }
                self.restart(mode: session.mode, clearPins: session.mode == .findDimensions)
            }
            view.onCapture = { [weak self, weak session, weak window] region, copy, togglePadding in
                guard let self, let session, let window, self.session === session else { return }
                self.capture(in: session, window: window, region: region, copy: copy, togglePadding: togglePadding)
            }
            view.initializePointer(at: pointer)
            window.makeFirstResponder(view)
            window.orderFrontRegardless()
        }
        onActivationChanged?(true)
        onStateChanged?(mode)
        if !freeze { focusWindows(in: session, activate: false) }
        startInitialCapture(in: session)
    }

    private func startInitialCapture(in session: Session) {
        session.initialCapture = Task { [weak self, weak session, captureScreens, canCapture] in
            let frames: [CGDirectDisplayID: ScreenSnapshot]
            let failed: Bool
            do {
                if canCapture() { frames = try await captureScreens() }
                else { frames = [:] }
                failed = false
            } catch {
                frames = [:]
                failed = true
                if !Task.isCancelled { NSLog("Schnaps capture: %@", error.localizedDescription) }
            }
            guard let self, let session, self.session === session, !Task.isCancelled else { return }
            session.initialCapture = nil
            let pointer = NSEvent.mouseLocation
            for window in session.windows {
                let view = window.measurementView
                if session.freeze, session.mode == .findDimensions { view.initializePointer(at: pointer) }
                view.updateSnapshot(frames[window.displayID])
                if failed, session.mode == .findDimensions { view.reportCaptureFailure() }
            }
            session.setPresentationSuppressed(false)
            // Focus only after taking the frozen screenshot so other apps keep dropdowns open.
            if session.freeze { self.focusWindows(in: session, activate: true) }
            self.startLiveCapture(in: session)
        }
    }

    private func focusWindows(in session: Session, activate: Bool) {
        for window in session.windows { window.acceptsMeasurementFocus = true }
        if activate { NSApp.activate(ignoringOtherApps: true) }
        let target = session.windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? session.windows.first
        target?.makeKeyAndOrderFront(nil)
    }

    func stop() { stop(restoreFocus: true) }

    private func stop(restoreFocus: Bool) {
        guard let session else { return }
        self.session = nil
        session.initialCapture?.cancel()
        session.liveCapture?.cancel()
        session.export?.cancel()
        savePins(from: session)
        for window in session.windows {
            window.alphaValue = 0
            window.orderOut(nil)
            window.measurementView.retire()
            window.contentView = nil
            window.close()
        }
        onActivationChanged?(false)
        onStateChanged?(nil)
        if restoreFocus, let previousApp = session.previousApp,
           previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
    }

    private func switchMode(to mode: MeasurementMode, in session: Session) {
        session.export?.cancel()
        session.export = nil
        session.liveCapture?.cancel()
        session.liveCapture = nil
        savePins(from: session)
        session.mode = mode
        for window in session.windows { window.measurementView.setMode(mode) }
        restorePins(in: session)
        if session.initialCapture == nil {
            session.setPresentationSuppressed(false)
            startLiveCapture(in: session)
        }
        onStateChanged?(mode)
    }

    private func savePins(from session: Session) {
        for window in session.windows {
            let view = window.measurementView
            pins[session.mode, default: [:]][window.displayID] = Pins(areas: view.pinned, distances: view.pinnedDistances)
        }
    }

    private func restorePins(in session: Session) {
        for window in session.windows {
            let view = window.measurementView
            let saved = pins[session.mode]?[window.displayID]
            view.pinned = (saved?.areas ?? []).map { $0.intersection(view.bounds) }.filter { !$0.isNull && !$0.isEmpty }
            view.pinnedDistances = saved?.distances ?? []
        }
    }

    private func startLiveCapture(in session: Session) {
        guard !session.freeze, session.mode == .findDimensions, session.export == nil, canCapture() else { return }
        session.liveCapture = Task { [weak self, weak session, captureScreens] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    guard session != nil, self?.session === session else { return }
                    guard session?.windows.contains(where: { $0.measurementView.wantsLiveSnapshot }) == true else { continue }
                    let frames = try await captureScreens()
                    guard let session, self?.session === session, !Task.isCancelled else { return }
                    for window in session.windows {
                        if let frame = frames[window.displayID] { window.measurementView.updateSnapshot(frame) }
                    }
                } catch {
                    // Keep the previous sample after a transient capture failure.
                }
            }
        }
    }

    private func capture(in session: Session, window: OverlayWindow, region: CGRect, copy: Bool, togglePadding: Bool) {
        guard session.export == nil else { return }
        session.liveCapture?.cancel()
        session.liveCapture = nil
        let startup = session.initialCapture
        session.export = Task { [weak self, weak session, weak window, captureScreens] in
            await startup?.value
            guard session != nil, self?.session === session, !Task.isCancelled else { return }
            let snapshot: ScreenSnapshot
            do {
                if session?.freeze == true, let frozen = window?.measurementView.captureSnapshot {
                    snapshot = frozen
                } else {
                    guard self?.canCapture() == true, let displayID = window?.displayID else {
                        throw ScreenshotExport.ExportError.noCapture
                    }
                    session?.setPresentationSuppressed(true)
                    CATransaction.flush()
                    let frames = try await captureScreens()
                    guard let frame = frames[displayID] else { throw ScreenshotExport.ExportError.noCapture }
                    snapshot = frame
                }
            } catch {
                guard let self, let session, self.session === session, !Task.isCancelled else { return }
                session.export = nil
                window?.measurementView.reportScreenshotError(error.localizedDescription)
                session.setPresentationSuppressed(false)
                self.startLiveCapture(in: session)
                return
            }

            guard let self, let session, self.session === session, !Task.isCancelled else { return }
            session.export = nil
            self.stop()
            do {
                try self.exportScreenshot(snapshot, region, copy, togglePadding)
            } catch {
                let alert = NSAlert()
                alert.messageText = L("Screenshot failed")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

final class OverlayWindow: NSPanel {
    let displayID: CGDirectDisplayID
    let measurementView: MeasurementView
    var acceptsMeasurementFocus: Bool

    init(screen: NSScreen, mode: MeasurementMode, freeze: Bool) {
        displayID = DesignTools.displayID(screen)
        measurementView = MeasurementView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                          scale: screen.backingScaleFactor, snapshot: nil, mode: mode, freeze: freeze)
        acceptsMeasurementFocus = !freeze
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: true)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Animating a full-display screenshot looks like the desktop itself zooms.
        animationBehavior = .none
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        acceptsMouseMovedEvents = true
        isRestorable = false
        hidesOnDeactivate = false
        contentView = measurementView
    }
    override var canBecomeKey: Bool { acceptsMeasurementFocus }
    override var canBecomeMain: Bool { acceptsMeasurementFocus }
}
