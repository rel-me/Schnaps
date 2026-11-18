import AppKit
import Testing
@testable import Schnaps

@MainActor @Test func escapeDismissesNewestAppearanceAndPreservesLayout() throws {
    let suite = "Schnaps.Escape.Tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let tools = DesignTools(defaults: defaults)
    let ruler = DesignMarker(tool: .ruler, display: 0)
    let guide = DesignMarker(tool: .guides, display: 0)
    tools.markers = [ruler]
    tools.visible = true
    tools.editing = true
    tools.loupe = true
    tools.markers.append(guide)
    tools.crosshair = true
    #expect(tools.dismissLastTool())
    #expect(!tools.crosshair && tools.loupe && tools.markers.allSatisfy(\.isVisible))
    #expect(tools.dismissLastTool())
    #expect(!tools.markers[1].isVisible && tools.markers[0].isVisible && tools.loupe)
    #expect(tools.dismissLastTool())
    #expect(!tools.loupe && tools.isActive)
    #expect(tools.dismissLastTool())
    #expect(!tools.isActive && !tools.editing && !tools.visible)
    #expect(!tools.dismissLastTool())
    #expect(tools.markers.count == 2)
    #expect(tools.markers[0].rect == ruler.rect)
    let restored = DesignTools(defaults: defaults)
    #expect(restored.markers.count == 2 && restored.markers.allSatisfy { !$0.isVisible })
}

@MainActor @Test func escapeSkipsDeletedHiddenAndDisabledToolsAndTracksRestoredMarkers() throws {
    let suite = "Schnaps.Escape.Tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let tools = DesignTools(defaults: defaults)
    let a = DesignMarker(tool: .frames, display: 0)
    let b = DesignMarker(tool: .guides, display: 0)
    tools.markers = [a, b]
    tools.visible = true
    tools.loupe = true
    tools.loupe = false
    tools.markers.removeLast()
    tools.crosshair = true
    // A restored marker becomes the most recent appearance, even if it is locked.
    tools.markers[0].isVisible = false
    tools.markers[0].locked = true
    tools.markers[0].isVisible = true
    #expect(tools.dismissLastTool())
    #expect(!tools.hasVisibleMarkers && tools.crosshair)
    #expect(tools.dismissLastTool())
    #expect(!tools.isActive && !tools.dismissLastTool())
    tools.visible = true
    #expect(!tools.isActive) // An all-hidden layout must not intercept mouse input.
}

@MainActor @Test func floatingEscapeWorksWithoutCanvasFocusAndDoesNotRepeat() throws {
    let suite = "Schnaps.Escape.Focus.Tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let tools = DesignTools(defaults: defaults)
    tools.loupe = true
    tools.crosshair = true
    var registrations = 0
    var removals = 0
    let shortcut = FloatingToolEscapeShortcut(registration: .init(register: {
        registrations += 1
        return true
    }, unregister: { removals += 1 })) {
        tools.dismissLastTool()
    }
    shortcut.update(active: tools.crosshair || tools.loupe, blocked: false)
    #expect(shortcut.isRegistered && registrations == 1)
    // Carbon hotkey delivery does not depend on the overlay being a key window.
    shortcut.handle(pressed: true)
    #expect(!tools.crosshair && tools.loupe)
    shortcut.update(active: tools.crosshair || tools.loupe, blocked: false)
    shortcut.handle(pressed: true)
    #expect(tools.loupe) // Holding Escape must not dismiss another tool.
    shortcut.handle(pressed: false)
    shortcut.handle(pressed: true)
    #expect(!tools.isActive)
    shortcut.update(active: false, blocked: false)
    #expect(!shortcut.isRegistered && removals == 1)
    shortcut.handle(pressed: true)
    #expect(registrations == 1)
}

@MainActor @Test func floatingEscapeYieldsToOtherKeyboardContextsAndReleasesRegistration() {
    var registrations = 0
    var removals = 0
    var dismissals = 0
    let shortcut = FloatingToolEscapeShortcut(registration: .init(register: {
        registrations += 1
        return true
    }, unregister: { removals += 1 })) { dismissals += 1 }
    shortcut.update(active: false, blocked: false)
    shortcut.update(active: true, blocked: true)
    #expect(!shortcut.isRegistered && registrations == 0)
    shortcut.update(active: true, blocked: false)
    shortcut.update(active: true, blocked: false)
    #expect(shortcut.isRegistered && registrations == 1)
    shortcut.update(active: true, blocked: true)
    shortcut.handle(pressed: true)
    #expect(!shortcut.isRegistered && removals == 1 && dismissals == 0)
    shortcut.update(active: true, blocked: false)
    shortcut.handle(pressed: true)
    #expect(registrations == 2 && dismissals == 1)
    shortcut.update(active: false, blocked: false)
    #expect(removals == 2)
}

@MainActor @Test(arguments: [DesignTool.crosshair, .loupe])
func floatingEscapeDismissesToolWithoutCanvasFocus(tool: DesignTool) throws {
    let suite = "Schnaps.FloatingEscape.Tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let tools = DesignTools(defaults: defaults)
    let ruler = DesignMarker(tool: .ruler, display: 0)
    tools.markers = [ruler]
    tools.visible = true
    var registrations = 0, unregistrations = 0
    let shortcut = FloatingToolEscapeShortcut(registration: .init(register: {
        registrations += 1
        return true
    }, unregister: { unregistrations += 1 })) { [weak tools] in
        _ = tools?.dismissLastTool()
    }
    tools.redraw = { [weak shortcut, weak tools] in
        guard let tools else { return }
        shortcut?.update(active: tools.crosshair || tools.loupe, blocked: false)
    }
    if tool == .crosshair { tools.crosshair = true } else { tools.loupe = true }
    #expect(!tools.editing && shortcut.isRegistered && registrations == 1)
    // Delivery comes from the temporary global shortcut; no canvas/key window is involved.
    shortcut.handle(pressed: true)
    #expect(!tools.crosshair && !tools.loupe)
    #expect(!shortcut.isRegistered && unregistrations == 1)
    #expect(tools.markers == [ruler] && tools.hasVisibleMarkers)
}
