import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.title = "Ice Test"
application.run()
