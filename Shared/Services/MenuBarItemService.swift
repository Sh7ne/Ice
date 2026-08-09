//
//  MenuBarItemService.swift
//  Shared
//

import Foundation
import LightweightCodeRequirements
import MachO.dyld.utils
import Security
import XPC

enum MenuBarItemService {
    static let name = "com.jordanbaird.Ice.MenuBarItemService"
    static let appIdentifier = "com.jordanbaird.Ice"

    private static var fullValidationFlags: SecCSFlags {
        SecCSFlags(
            rawValue: UInt32(
                kSecCSCheckAllArchitectures
                    | kSecCSCheckNestedCode
                    | kSecCSStrictValidate
            )
        )
    }

    private enum CodeValidationError: LocalizedError {
        case currentProcessDoesNotMatchBundle(URL)

        var errorDescription: String? {
            switch self {
            case .currentProcessDoesNotMatchBundle(let bundleURL):
                "The running process does not match the signed bundle at \(bundleURL.path)"
            }
        }
    }

    static func validateBundle(at bundleURL: URL) throws {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(createStatus))
        }
        guard let staticCode else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let validityStatus = SecStaticCodeCheckValidity(staticCode, fullValidationFlags, nil)
        guard validityStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(validityStatus))
        }
    }

    static func validateCurrentProcess(inBundleAt bundleURL: URL) throws {
        let currentCode = try validatedCurrentCode()
        let currentHash = try currentProcessCodeDirectoryHash(for: currentCode)
        let bundleHashes = try codeDirectoryHashes(forBundleAt: bundleURL)
        guard bundleHashes.contains(currentHash) else {
            throw CodeValidationError.currentProcessDoesNotMatchBundle(bundleURL)
        }
    }

    @available(macOS 26.0, *)
    static func peerRequirement(
        forBundleAt bundleURL: URL,
        signingIdentifier: String
    ) throws -> XPCPeerRequirement {
        // Preserve the platform's team-bound policy for normally signed builds.
        // Exact hashes are only needed when an ad-hoc signature has no Team ID.
        if try currentProcessTeamIdentifier() != nil {
            return .isFromSameTeam(andMatchesSigningIdentifier: signingIdentifier)
        }

        let codeDirectoryHashes = try codeDirectoryHashes(forBundleAt: bundleURL)
        let requirement = try ProcessCodeRequirement.allOf {
            CodeDirectoryHash.in(codeDirectoryHashes)
            SigningIdentifier(signingIdentifier)
            ProcessCodeSigningFlags.isSuperset(of: [.isSigned])
        }
        return .codeRequirement(requirement)
    }

    private static func codeDirectoryHashes(forBundleAt bundleURL: URL) throws -> [Data] {
        guard let executableURL = Bundle(url: bundleURL)?.executableURL else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var architectures = [String]()
        var containsUnknownArchitecture = false
        let enumerationStatus = executableURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                return EINVAL
            }
            return macho_for_each_slice(path) { header, _, _, _ in
                guard
                    let name = macho_arch_name_for_cpu_type(
                        header.pointee.cputype,
                        header.pointee.cpusubtype
                    )
                else {
                    containsUnknownArchitecture = true
                    return
                }
                architectures.append(String(cString: name))
            }
        }
        guard enumerationStatus == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: enumerationStatus) ?? .EIO)
        }
        guard !containsUnknownArchitecture, !architectures.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var codeDirectoryHashes = [Data]()
        for architecture in architectures {
            let attributes = [
                kSecCodeAttributeArchitecture as String: architecture,
            ] as CFDictionary
            var staticCode: SecStaticCode?
            let createStatus = SecStaticCodeCreateWithPathAndAttributes(
                bundleURL as CFURL,
                [],
                attributes,
                &staticCode
            )
            guard createStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(createStatus))
            }
            guard let staticCode else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let validityStatus = SecStaticCodeCheckValidity(staticCode, fullValidationFlags, nil)
            guard validityStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(validityStatus))
            }

            let codeDirectoryHash = try codeDirectoryHash(for: staticCode)
            if !codeDirectoryHashes.contains(codeDirectoryHash) {
                codeDirectoryHashes.append(codeDirectoryHash)
            }
        }

        return codeDirectoryHashes
    }

    private static func currentProcessTeamIdentifier() throws -> String? {
        let currentCode = try validatedCurrentCode()
        let signingCode = unsafeBitCast(currentCode, to: SecStaticCode.self)
        let info = try signingInformation(for: signingCode)
        guard
            let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String,
            !teamIdentifier.isEmpty
        else {
            return nil
        }
        return teamIdentifier
    }

    private static func validatedCurrentCode() throws -> SecCode {
        var currentCode: SecCode?
        let copyStatus = SecCodeCopySelf([], &currentCode)
        guard copyStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(copyStatus))
        }
        guard let currentCode else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let validityStatus = SecCodeCheckValidity(currentCode, [], nil)
        guard validityStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(validityStatus))
        }
        return currentCode
    }

    private static func currentProcessCodeDirectoryHash(for code: SecCode) throws -> Data {
        // Security documents signing-information queries as accepting a dynamic
        // SecCodeRef, but Swift imports the parameter as SecStaticCode. Converting
        // with SecCodeCopyStaticCode would reopen the image from disk and lose the
        // runtime identity this check is intended to establish.
        let signingCode = unsafeBitCast(code, to: SecStaticCode.self)
        return try codeDirectoryHash(for: signingCode)
    }

    private static func codeDirectoryHash(for code: SecStaticCode) throws -> Data {
        let info = try signingInformation(for: code)
        guard let codeDirectoryHash = info[kSecCodeInfoUnique as String] as? Data else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return codeDirectoryHash
    }

    private static func signingInformation(for code: SecStaticCode) throws -> [String: Any] {
        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &signingInfo
        )
        guard infoStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(infoStatus))
        }
        guard
            let info = signingInfo as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return info
    }
}

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}
