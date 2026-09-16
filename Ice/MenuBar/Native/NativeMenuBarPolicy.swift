//
//  NativeMenuBarPolicy.swift
//  Ice
//

import Foundation

enum NativeMenuBarPolicy {
    static func excludedBundles(
        sections: [String: Int], hidden: Bool, alwaysHidden: Bool, ownBundle: String
    ) -> Set<String> {
        Set(sections.compactMap { bundle, section in
            guard bundle != ownBundle, !bundle.hasPrefix("com.apple.") else { return nil }
            return (section == 1 && hidden || section == 2 && alwaysHidden) ? bundle : nil
        })
    }
}
