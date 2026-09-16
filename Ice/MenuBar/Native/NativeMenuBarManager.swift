//
//  NativeMenuBarManager.swift
//  Ice
//

import AppKit
import Combine
import OSLog

/// An independent, bundle-based backend; never fabricates legacy window IDs.
@MainActor
final class NativeMenuBarManager: ObservableObject {
    static var isRequired: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }
    static let sectionsKey = "NativeMenuBarSections"

    @Published private(set) var items = [NativeMenuBarSnapshot.Item]()
    @Published private(set) var sections: [String: Int] = UserDefaults.standard.dictionary(forKey: sectionsKey) as? [String: Int] ?? [:]
    @Published private(set) var error: String?
    @Published private(set) var isRefreshing = false
    @Published var experimentalHidingEnabled = UserDefaults.standard.bool(forKey: "NativeMenuBarExperimentalHiding") {
        didSet {
            UserDefaults.standard.set(experimentalHidingEnabled, forKey: "NativeMenuBarExperimentalHiding")
            applyVisibility()
        }
    }

    private weak var appState: AppState?
    private let reader = NativeMenuBarSnapshot()
    private let logger = Logger(category: "NativeMenuBarManager")
    private var cancellables = Set<AnyCancellable>()
    private var assertion: AnyObject?
    private var revision = 0
    private var lastAllowed: Set<String>?
    private var lastAllowedSystemItems: Set<Int>?
    private var ready = false

    func performSetup(with appState: AppState) {
        self.appState = appState
        Publishers.MergeMany(appState.menuBarManager.sections.map { $0.controlItem.$state })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)
        appState.settings.advanced.$enableAlwaysHiddenSection
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak appState] _ in
                if let section = appState?.menuBarManager.section(withName: .alwaysHidden) {
                    if section.isEnabled { section.hotkey?.enable() } else { section.hotkey?.disable() }
                }
                self?.applyVisibility()
            }
            .store(in: &cancellables)
        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.Merge3(
            workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification),
            workspace.publisher(for: NSWorkspace.didWakeNotification)
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.restore()
            Task { await self?.refresh() }
        }
        .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.restore() }
            .store(in: &cancellables)
        Task { await refresh() }
    }

    func setSection(_ section: Int, for bundle: String) {
        guard NativeMenuBarPolicy.isManageable(bundle, ownBundle: Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice") else { return }
        if section == 0 {
            sections.removeValue(forKey: bundle)
        } else if section == 1 || section == 2 {
            sections[bundle] = section
        }
        UserDefaults.standard.set(sections, forKey: Self.sectionsKey)
        applyVisibility()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let snapshot = await reader.read() else {
            ready = false
            failOpen("Menu bar access is unavailable. Check Accessibility permission.")
            return
        }
        // The old divider windows no longer exist. Only infer the ordinary
        // hidden group when the saved layout and main-display Ice icon agree.
        if UserDefaults.standard.object(forKey: Self.sectionsKey) == nil,
           UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position Ice.ControlItem.Hidden") != nil,
           let ownItem = snapshot.items.first(where: { $0.id == Bundle.main.bundleIdentifier }),
           ownItem.frame.minY >= -5, ownItem.frame.minY < 50 {
            sections = Dictionary(uniqueKeysWithValues: snapshot.items.compactMap { item in
                guard !NativeMenuBarPolicy.isSystem(item.id), item.id != ownItem.id,
                      abs(item.frame.minY - ownItem.frame.minY) < 5,
                      item.frame.maxX <= ownItem.frame.minX else { return nil }
                return (item.id, 1)
            })
            UserDefaults.standard.set(sections, forKey: Self.sectionsKey)
        }
        var known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for item in snapshot.items { known[item.id] = item }
        // Retain hidden apps across snapshots and restarts, including apps not running.
        for bundle in sections.keys where known[bundle] == nil {
            let name = NativeMenuBarPolicy.isSystem(bundle) ? NativeMenuBarPolicy.fallbackName(for: bundle)
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                    .map { $0.deletingPathExtension().lastPathComponent } ?? bundle
            known[bundle] = .init(id: bundle, name: name, frame: .zero)
        }
        items = known.values.filter { $0.id != Bundle.main.bundleIdentifier }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        ready = true
        applyVisibility()
    }

    private func applyVisibility() {
        guard ready, let appState else { return }
        guard experimentalHidingEnabled else {
            restore()
            error = nil
            return
        }
        let hidden = appState.menuBarManager.section(withName: .hidden)?.isHidden ?? false
        let alwaysHidden = appState.settings.advanced.enableAlwaysHiddenSection &&
            (appState.menuBarManager.section(withName: .alwaysHidden)?.isHidden ?? false)
        let excluded = NativeMenuBarPolicy.excludedBundles(
            sections: sections,
            hidden: hidden,
            alwaysHidden: alwaysHidden,
            ownBundle: Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice"
        )
        let excludedSystemItems = NativeMenuBarPolicy.excludedSystemItems(
            sections: sections, hidden: hidden, alwaysHidden: alwaysHidden
        )
        let allowedSystemItems = NativeMenuBarPolicy.allSystemItems.subtracting(excludedSystemItems)
        guard !excluded.isEmpty || !excludedSystemItems.isEmpty else {
            restore()
            error = nil
            return
        }
        guard IceNativeMenuBarAvailable() else {
            failOpen("This macOS build does not support native menu bar hiding.")
            return
        }
        let bundles = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            .union(items.map(\.id).filter { !$0.hasPrefix(NativeMenuBarPolicy.systemPrefix) })
            .union([Bundle.main.bundleIdentifier ?? "com.jordanbaird.Ice"])
        let allowed = bundles.subtracting(excluded)
        guard allowed != lastAllowed || allowedSystemItems != lastAllowedSystemItems else { return }
        restore()
        let currentRevision = revision
        lastAllowed = allowed
        lastAllowedSystemItems = allowedSystemItems
        assertion = IceActivateMenuBarAssertion(allowed.sorted(), allowedSystemItems.sorted().map { NSNumber(value: $0) }) { [weak self] failure in
            Task { @MainActor in
                guard let self, self.revision == currentRevision else { return }
                if let failure {
                    self.failOpen(failure.localizedDescription)
                } else {
                    self.error = nil
                    self.logger.info("Native hiding active for \(excluded.count) app(s), \(excludedSystemItems.count) system control(s)")
                }
            }
        } as AnyObject?
        if assertion == nil { failOpen("Unable to activate native menu bar hiding.") }
    }

    private func failOpen(_ message: String) {
        restore()
        error = message
        logger.error("\(message, privacy: .public)")
    }

    private func restore() {
        revision += 1
        IceInvalidateMenuBarAssertion(assertion)
        assertion = nil
        lastAllowed = nil
        lastAllowedSystemItems = nil
    }
}
