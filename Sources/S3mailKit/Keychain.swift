// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

/// Where the device's credentials live.
///
/// In the keychain, and with two attributes that carry the whole argument:
///
///   - `WhenUnlockedThisDeviceOnly` - not readable while the phone is locked,
///     and never restored onto a second device. A backup of the phone does not
///     hand somebody the mailbox; they would have to take the phone and unlock
///     it, and at that point the keychain is not what is protecting anything.
///   - `kSecUseDataProtectionKeychain` - the modern keychain rather than the
///     file-based one. Without it the same code behaves differently on the
///     simulator than on a device, which is the worst kind of difference.
public enum Keychain {

    public enum Failure: LocalizedError {
        case status(OSStatus)

        public var errorDescription: String? {
            switch self {
            case .status(let code):
                if let text = SecCopyErrorMessageString(code, nil) as String? {
                    return "Keychain: \(text)"
                }
                return "Keychain error \(code)"
            }
        }
    }

    private static let service = "eu.ole-hartwig.s3mail.mailbox"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    /// Stores a mailbox under its own id, replacing what was there.
    public static func save(_ setup: Setup) throws {
        let blob = try JSONEncoder().encode(setup)
        var attrs = query(setup.id)
        SecItemDelete(attrs as CFDictionary)
        attrs[kSecValueData as String] = blob
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    /// Reads one mailbox back. Returns nil when there is none - that is not an
    /// error, it is a phone nobody has set up yet.
    public static func load(id: String) throws -> Setup? {
        var attrs = query(id)
        attrs[kSecReturnData as String] = true
        attrs[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attrs as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let blob = item as? Data else {
            throw Failure.status(status)
        }
        return try JSONDecoder().decode(Setup.self, from: blob)
    }

    /// Forgets a mailbox. Used when somebody removes it - and it is the only
    /// thing the phone can do about a lost credential. Revoking it is a click
    /// in the IAM console, which is why every device gets its own.
    public static func forget(id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
    }
}
