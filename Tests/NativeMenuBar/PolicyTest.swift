import Foundation

@main
struct NativeMenuBarPolicyTest {
    static func main() {
        let assignments = ["visible": 0, "hidden": 1, "always": 2, "invalid": 3, "ice": 1, "com.apple.clock": 1]
        for hidden in [false, true] {
            for alwaysHidden in [false, true] {
                let excluded = NativeMenuBarPolicy.excludedBundles(
                    sections: assignments, hidden: hidden, alwaysHidden: alwaysHidden, ownBundle: "ice"
                )
                var expected = Set<String>()
                if hidden { expected.insert("hidden") }
                if alwaysHidden { expected.insert("always") }
                precondition(excluded == expected, "Invalid section policy: \(excluded)")
            }
        }
        precondition(NativeMenuBarPolicy.excludedBundles(
            sections: [:], hidden: true, alwaysHidden: true, ownBundle: "ice"
        ).isEmpty)
        print("NATIVE_POLICY_TEST_PASS: section states, disabled always-hidden, invalid values, protected bundles")
    }
}
