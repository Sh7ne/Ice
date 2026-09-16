//
//  NativeMenuBarSnapshot.swift
//  Ice
//

import AppKit
import ApplicationServices

/// macOS 27 hosts status items in MenuBarAgent, not individual CGWindows.
/// Tree structure reference: fif7y/Pelmet ItemEnumerator.swift (GPL-3.0).
actor NativeMenuBarSnapshot {
    struct Item: Identifiable, Sendable {
        var id: String
        var name: String
        var frame: CGRect
    }

    struct Snapshot: Sendable {
        var items: [Item]
        var systemItemIDs: Set<String>
        var unsupportedSystemItems: [String]
    }

    func read() -> Snapshot? {
        guard
            AXIsProcessTrusted(),
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first
        else { return nil }
        let root = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.25)
        guard let windows = attribute(root, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        var items = [String: Item]()
        var unsupported = Set<String>()
        var systemItems = Set<String>()
        let knownSystemIDs: Set<String> = [
            "battery", "bluetooth", "clock", "display", "displays", "textinput",
            "keyboard", "sound", "wifi", "screen-mirroring", "controlcenter",
        ]
        for window in windows where attribute(window, kAXRoleAttribute) as? String == "AXWindow" {
            for group in children(window) {
                guard
                    let frameValue = attribute(group, "AXFrame"),
                    CFGetTypeID(frameValue) == AXValueGetTypeID()
                else { continue }
                var frame = CGRect.zero
                // The CF type ID was checked above; AXValue cannot use a conditional cast.
                // swiftlint:disable:next force_cast
                guard AXValueGetValue(frameValue as! AXValue, .cgRect, &frame) else { continue }
                for child in children(group) {
                    var pid: pid_t = 0
                    AXUIElementGetPid(child, &pid)
                    if
                        pid != agent.processIdentifier,
                        let app = NSRunningApplication(processIdentifier: pid),
                        let bundle = app.bundleIdentifier
                    {
                        let name: String
                        if bundle == NativeMenuBarPolicy.systemHost {
                            name = systemHostName(pid: pid)
                        } else if NativeMenuBarPolicy.systemItemNumber(for: bundle) != nil {
                            name = NativeMenuBarPolicy.fallbackName(for: bundle)
                        } else {
                            name = app.localizedName ?? bundle
                        }
                        let item = Item(id: bundle, name: name, frame: frame)
                        if items[bundle] == nil || (frame.minY >= -5 && frame.minY < 50) {
                            items[bundle] = item
                        }
                    } else {
                        for leaf in children(child) {
                            guard attribute(leaf, kAXRoleAttribute) as? String == "AXMenuBarItem" else { continue }
                            if let identifier = attribute(leaf, kAXIdentifierAttribute) as? String {
                                systemItems.insert(identifier)
                                let id = NativeMenuBarPolicy.systemPrefix + identifier
                                let name = attribute(leaf, kAXDescriptionAttribute) as? String
                                    ?? NativeMenuBarPolicy.fallbackName(for: id)
                                items[id] = Item(id: id, name: name, frame: frame)
                                if !knownSystemIDs.contains(identifier.replacingOccurrences(of: "com.apple.menuextra.", with: "")) {
                                    unsupported.insert(identifier)
                                }
                            }
                        }
                    }
                }
            }
        }
        return Snapshot(items: Array(items.values), systemItemIDs: systemItems, unsupportedSystemItems: unsupported.sorted())
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func systemHostName(pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard
            let value = attribute(app, kAXExtrasMenuBarAttribute),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return NativeMenuBarPolicy.fallbackName(for: NativeMenuBarPolicy.systemHost)
        }
        // swiftlint:disable:next force_cast
        let bar = value as! AXUIElement
        let names = children(bar).compactMap { element -> String? in
            let title = attribute(element, kAXTitleAttribute) as? String
            let description = attribute(element, kAXDescriptionAttribute) as? String
            return [title, description].compactMap { $0 }.first { !$0.isEmpty }
        }
        return names.isEmpty ? NativeMenuBarPolicy.fallbackName(for: NativeMenuBarPolicy.systemHost)
            : Array(Set(names)).sorted().joined(separator: ", ").replacingOccurrences(of: "TimeMachine", with: "Time Machine")
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }
}
