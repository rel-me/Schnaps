import AppKit
import MeasurementCore

@MainActor
enum ScreenTemplateMenu {
    static func make(target: AnyObject, action: Selector, defaultItem: NSMenuItem? = nil) -> NSMenu {
        let menu = NSMenu(title: L("Screens"))
        if let defaultItem {
            menu.addItem(defaultItem)
            menu.addItem(.separator())
        }
        for (title, templates) in [
            ("Phones", ScreenTemplate.phones),
            ("Tablets", ScreenTemplate.tablets),
            ("Other Sizes", ScreenTemplate.otherDevices),
        ] {
            let group = NSMenuItem(title: L(title), action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: group.title)
            for template in templates {
                let size = "\(Int(template.width)) × \(Int(template.height))"
                let item = NSMenuItem(title: "\(template.name) (\(size))", action: action, keyEquivalent: "")
                item.target = target
                item.representedObject = template
                submenu.addItem(item)
            }
            group.submenu = submenu
            menu.addItem(group)
        }
        return menu
    }
}
