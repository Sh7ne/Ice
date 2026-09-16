import AppKit

@main
struct NativeMenuBarSmokeTest {
    @MainActor
    static func main() async {
        let target = ProcessInfo.processInfo.environment["ICE_NATIVE_SMOKE_TARGET"] ?? "com.sh7ne.Ice.NativeTestFixture"
        let targetSystemItem = NativeMenuBarPolicy.systemItemNumber(for: target)
        let allowedSystemItems = (0...8).filter { $0 != targetSystemItem }.map { NSNumber(value: $0) }
        let reader = NativeMenuBarSnapshot()
        let snapshot = await reader.read()
        print("Native API: \(IceNativeMenuBarAvailable()); AX: \(AXIsProcessTrusted()); items: \(snapshot?.items.map(\.id) ?? []); unsupported: \(snapshot?.unsupportedSystemItems ?? [])")
        guard NativeMenuBarPolicy.isManageable(target, ownBundle: "com.jordanbaird.Ice"),
              IceNativeMenuBarAvailable(), let baseline = snapshot,
              baseline.items.contains(where: { $0.id == target }) else {
            print("NATIVE_SMOKE_TEST_FAIL: fixture, Accessibility permission or supported system items unavailable")
            exit(1)
        }
        let before = Set(baseline.items.map(\.id).filter { !$0.hasPrefix(NativeMenuBarPolicy.systemPrefix) })
        let allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            .union(before).subtracting([target]).sorted()
        var assertion: AnyObject?
        defer { IceInvalidateMenuBarAssertion(assertion) }
        for cycle in 1...3 {
            var activationCompleted = false
            var activationError: Error?
            assertion = IceActivateMenuBarAssertion(allowed, allowedSystemItems) { error in
                Task { @MainActor in
                    activationError = error
                    activationCompleted = true
                }
            } as AnyObject?
            try? await Task.sleep(for: .seconds(2))
            let currentSnapshot = await reader.read()
            print("Concealed snapshot: \(currentSnapshot?.items.map(\.id).sorted() ?? [])")
            guard assertion != nil, activationCompleted, activationError == nil,
                  let concealed = currentSnapshot,
                  !concealed.items.contains(where: { $0.id == target }),
                  Set(concealed.items.map(\.id)).isSuperset(of: before.subtracting([target])),
                  concealed.systemItemIDs.isSuperset(of: baseline.systemItemIDs.subtracting(baseline.unsupportedSystemItems)
                    .filter { NativeMenuBarPolicy.systemPrefix + $0 != target }) else {
                IceInvalidateMenuBarAssertion(assertion)
                print("NATIVE_SMOKE_TEST_FAIL: conceal or preservation check (cycle \(cycle)), \(String(describing: activationError))")
                exit(1)
            }
            print("System extras temporarily concealed: \(baseline.systemItemIDs.subtracting(concealed.systemItemIDs).sorted())")
            IceInvalidateMenuBarAssertion(assertion)
            assertion = nil
            try? await Task.sleep(for: .seconds(1))
            guard let restored = await reader.read(),
                  Set(restored.items.map(\.id)).isSuperset(of: before),
                  restored.systemItemIDs.isSuperset(of: baseline.systemItemIDs) else {
                print("NATIVE_SMOKE_TEST_FAIL: restore check (cycle \(cycle))")
                exit(1)
            }
            print("NATIVE_SMOKE_TEST_CYCLE_PASS \(cycle)")
        }
        print("NATIVE_SMOKE_TEST_PASS: \(target) concealed/restored; unrelated apps and supported controls preserved; all baseline items restored")
    }
}
