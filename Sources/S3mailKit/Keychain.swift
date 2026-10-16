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
///     hand somebody the credential; they would have to take the phone and
///     unlock it, and at that point the keychain is not what is protecting
///     anything. The mail cache has its own key below, so the same holds for
///     the mail: a backup carries ciphertext.
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

    /// The account the cache key is filed under. Not a mailbox id: those carry
    /// a bucket name and a slash, this does not, so the two cannot collide.
    private static let cacheKeyAccount = "s3mail.cache-key"

    /// The key the on-device cache is encrypted with: the index, the state copy
    /// and the message bodies under Application Support. Minted on first use,
    /// 32 random bytes, and kept here rather than next to the files - a backup
    /// of the sandbox then carries ciphertext and no key, which is the same
    /// arrangement the desktop has with its system keychain (AUD-008-F01).
    ///
    /// `AfterFirstUnlockThisDeviceOnly`, not `WhenUnlocked`: a background
    /// refresh runs with the phone locked in a pocket and has to open the
    /// cache. This-device-only still holds, so the key is never restored onto
    /// a second device - and a restored cache without it is noise the core
    /// throws away and rebuilds.
    ///
    /// Returned base64-encoded, because that is what crosses the bridge.
    public static func cacheKey() throws -> String {
        var attrs = query(cacheKeyAccount)
        attrs[kSecReturnData as String] = true
        attrs[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attrs as CFDictionary, &item)
        if status == errSecSuccess, let blob = item as? Data, blob.count == 32 {
            return blob.base64EncodedString()
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
        // Nothing usable there: mint one. A short or missing item is replaced
        // rather than trusted - a key that is not 32 bytes is not a key.
        var fresh = [UInt8](repeating: 0, count: 32)
        let drawn = SecRandomCopyBytes(kSecRandomDefault, fresh.count, &fresh)
        guard drawn == errSecSuccess else { throw Failure.status(drawn) }
        let blob = Data(fresh)
        var add = query(cacheKeyAccount)
        SecItemDelete(add as CFDictionary)
        add[kSecValueData as String] = blob
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw Failure.status(added) }
        return blob.base64EncodedString()
    }

    /// Throws the cache key away. The next `cacheKey()` mints a new one and the
    /// core discards every cache file it cannot open - which is the intended
    /// outcome when the last mailbox leaves the phone, and what the tests need
    /// to start from nothing.
    public static func forgetCacheKey() throws {
        let status = SecItemDelete(query(cacheKeyAccount) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.status(status)
        }
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
