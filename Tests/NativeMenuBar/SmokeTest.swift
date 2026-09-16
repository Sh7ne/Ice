import AppKit

@main
struct NativeMenuBarSmokeTest {
    @MainActor
    static func main() async {
        let target = "com.sh7ne.Ice.NativeTestFixture"
        let reader = NativeMenuBarSnapshot()
        let snapshot = await reader.read()
        print("Native API: \(IceNativeMenuBarAvailable()); AX: \(AXIsProcessTrusted()); items: \(snapshot?.items.map(\.id) ?? []); unsupported: \(snapshot?.unsupportedSystemItems ?? [])")
        guard IceNativeMenuBarAvailable(), let baseline = snapshot,
              baseline.items.contains(where: { $0.id == target }) else {
            print("NATIVE_SMOKE_TEST_FAIL: fixture, Accessibility permission or supported system items unavailable")
            exit(1)
        }
        let before = Set(baseline.items.map(\.id))
        let allowed = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            .union(before).subtracting([target]).sorted()
        var assertion: AnyObject?
        defer { IceInvalidateMenuBarAssertion(assertion) }
        for cycle in 1...3 {
            var activationCompleted = false
            var activationError: Error?
            assertion = IceActivateMenuBarAssertion(allowed) { error in
                Task { @MainActor in
                    activationError = error
                    activationCompleted = true
                }
            } as AnyObject?
            try? await Task.sleep(for: .seconds(2))
            guard assertion != nil, activationCompleted, activationError == nil,
                  let concealed = await reader.read(),
                  !concealed.items.contains(where: { $0.id == target }),
                  Set(concealed.items.map(\.id)).isSuperset(of: before.subtracting([target])),
                  concealed.systemItemIDs.isSuperset(of: baseline.systemItemIDs.subtracting(baseline.unsupportedSystemItems)) else {
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
        print("NATIVE_SMOKE_TEST_PASS: fixture concealed/restored; other apps and supported system items preserved; all baseline items restored")
    }
}
