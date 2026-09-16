//
//  NativeMenuBarPolicy.swift
//  Ice
//

import Foundation

enum NativeMenuBarPolicy {
    static let systemPrefix = "system:"
    static let systemHost = "com.apple.systemuiserver"
    static let allSystemItems = Set(0...8)

    static func systemItemNumber(for id: String) -> Int? {
        if id == "com.apple.TextInputMenuAgent" { return 4 }
        guard id.hasPrefix(systemPrefix) else { return nil }
        switch String(id.dropFirst(systemPrefix.count)) {
        case "com.apple.menuextra.battery": return 0
        case "com.apple.menuextra.bluetooth": return 1
        case "com.apple.menuextra.clock": return 2
        case "com.apple.menuextra.display", "com.apple.menuextra.displays": return 3
        case "com.apple.menuextra.textinput", "com.apple.menuextra.keyboard": return 4
        case "com.apple.menuextra.sound": return 5
        case "com.apple.menuextra.wifi": return 6
        case "com.apple.menuextra.screen-mirroring": return 7
        case "com.apple.menuextra.controlcenter": return 8
        default: return nil
        }
    }

    static func isSystem(_ id: String) -> Bool {
        id.hasPrefix(systemPrefix) || id.hasPrefix("com.apple.")
    }

    static func isManageable(_ id: String, ownBundle: String) -> Bool {
        guard id != ownBundle else { return false }
        if let number = systemItemNumber(for: id) { return number != 2 && number != 8 }
        if id == systemHost || id == "com.apple.KerberosMenuExtra" { return true }
        return !isSystem(id)
    }

    static func fallbackName(for id: String) -> String {
        if id == systemHost { return "Time Machine / Siri" }
        if id == "com.apple.KerberosMenuExtra" { return "Kerberos" }
        switch systemItemNumber(for: id) {
        case 0: return "Battery"
        case 1: return "Bluetooth"
        case 2: return "Clock"
        case 3: return "Displays"
        case 4: return "Input Menu"
        case 5: return "Sound"
        case 6: return "Wi-Fi"
        case 7: return "Screen Mirroring"
        case 8: return "Control Center"
        default: return id
        }
    }

    static func excludedBundles(
        sections: [String: Int], hidden: Bool, alwaysHidden: Bool, ownBundle: String
    ) -> Set<String> {
        Set(sections.compactMap { bundle, section in
            guard isManageable(bundle, ownBundle: ownBundle), systemItemNumber(for: bundle) == nil else { return nil }
            return (section == 1 && hidden || section == 2 && alwaysHidden) ? bundle : nil
        })
    }

    static func excludedSystemItems(sections: [String: Int], hidden: Bool, alwaysHidden: Bool) -> Set<Int> {
        Set(sections.compactMap { id, section in
            guard let number = systemItemNumber(for: id), number != 2, number != 8 else { return nil }
            return (section == 1 && hidden || section == 2 && alwaysHidden) ? number : nil
        })
    }
}
