import AppKit
import MeasurementCore
import Testing
@testable import Schnaps

@Test func toolOverlayVisibilityIsOptInAndSurvivesRestarts() throws {
    let suite = "Schnaps.ToolOverlay.Tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ToolOverlayPreferences(defaults: defaults)
    #expect(!preferences.isEnabled)
    preferences.isEnabled = true
    let restored = ToolOverlayPreferences(defaults: try #require(UserDefaults(suiteName: suite)))
    #expect(restored.isEnabled)
    restored.isEnabled = false
    #expect(!ToolOverlayPreferences(defaults: defaults).isEnabled)
}

@Test @MainActor func screensMenuExposesEveryTemplateWithItsDimensions() {
    let target = NSResponder()
    let action = #selector(NSResponder.cancelOperation(_:))
    let menu = ScreenTemplateMenu.make(target: target, action: action)
    let expectedGroups = [ScreenTemplate.phones, ScreenTemplate.tablets, ScreenTemplate.otherDevices]
    #expect(menu.items.count == expectedGroups.count)
    for (group, expectedTemplates) in zip(menu.items, expectedGroups) {
        let entries = group.submenu?.items ?? []
        #expect(entries.count == expectedTemplates.count)
        for (entry, expected) in zip(entries, expectedTemplates) {
            #expect(entry.action == action)
            #expect(entry.target === target)
            #expect((entry.representedObject as? ScreenTemplate)?.id == expected.id)
            #expect(entry.title.contains("\(Int(expected.width)) × \(Int(expected.height))"))
        }
    }
}
