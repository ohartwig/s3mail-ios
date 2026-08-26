// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Which of Apple's two worlds this build belongs to.
///
/// Read from the build's own provisioning profile, never guessed from the build
/// configuration. The tempting `#if DEBUG` gets one case wrong and it is not an
/// unusual one:
///
///   | build                   | configuration | APNs        |
///   |-------------------------|---------------|-------------|
///   | Xcode onto a device     | Debug         | sandbox     |
///   | Ad Hoc, for a customer  | Release       | **sandbox** |
///   | TestFlight / App Store  | Release       | production  |
///
/// The Ad Hoc row is the one that breaks. And the symptom is the worst kind:
/// the endpoint is created, the subscription exists, nothing reports an error,
/// and no notification ever arrives.
public enum PushEnvironment: String {
    case production
    case development

    /// Reads `aps-environment` out of the embedded provisioning profile.
    ///
    /// The profile is a CMS-signed plist; the payload is plain XML inside it,
    /// so the value can be found without verifying the signature - which would
    /// be pointless here anyway, since iOS has already verified it or the app
    /// would not be running.
    ///
    /// Nil when there is no profile: the simulator has none, and it cannot do
    /// push at all. Better an honest nil than a guess that registers a
    /// simulator against production.
    public static func current(bundle: Bundle = .main) -> PushEnvironment? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // Latin-1 rather than UTF-8: the file is binary around the XML,
              // and UTF-8 decoding of arbitrary bytes fails outright. Latin-1
              // maps every byte to a character, so the plain-text part stays
              // findable.
              let text = String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        guard let key = text.range(of: "<key>aps-environment</key>") else { return nil }
        let rest = text[key.upperBound...]
        guard let open = rest.range(of: "<string>"),
              let close = rest.range(of: "</string>") else { return nil }
        let value = rest[open.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return PushEnvironment(rawValue: value)
    }
}

/// What the device remembers about its push registration.
///
/// Only the endpoint ARN, and it is not a secret: it names a resource, and what
/// may be done with it is decided by the IAM policy of the device's key. So
/// UserDefaults, not the keychain - the same split the mailbox identity makes.
///
/// It is remembered at all only to save a call: without it every launch would
/// create an endpoint, SNS would refuse the second one, and the ARN would have
/// to be dug out of an error message. That path works and is the fallback; this
/// is the short way.
enum PushStore {
    private static func key(_ mailbox: String) -> String { "push.endpoint.\(mailbox)" }

    static func endpoint(for mailbox: String) -> String {
        UserDefaults.standard.string(forKey: key(mailbox)) ?? ""
    }

    static func remember(_ arn: String, for mailbox: String) {
        UserDefaults.standard.set(arn, forKey: key(mailbox))
    }

    static func forget(mailbox: String) {
        UserDefaults.standard.removeObject(forKey: key(mailbox))
    }
}

public extension Mailbox {

    /// Whether this mailbox and this build can do push at all.
    ///
    /// False for a mailbox set up before push existed - its code carries no
    /// ARNs - and false on the simulator, which has no provisioning profile and
    /// cannot receive a notification anyway.
    var canPush: Bool {
        guard let env = PushEnvironment.current() else { return false }
        return inner.canPush(env.rawValue)
    }

    /// Registers the device token with SNS and subscribes to the mailbox topic.
    ///
    /// Call it every time iOS hands over a token, which is every launch. It is
    /// idempotent, and it has to be: a token changes on reinstall and on
    /// restore, and APNs switches an endpoint off whenever it decides a token
    /// is stale - without telling anybody, and without SNS ever switching it
    /// back on.
    @discardableResult
    func registerForPush(token: Data) throws -> String {
        guard let env = PushEnvironment.current() else {
            throw PushError.noEnvironment
        }
        // APNs tokens are handed over as bytes and wanted by SNS as lowercase
        // hex. `description` on Data used to produce exactly that and no longer
        // does - it prints "32 bytes" now. A device registered with that string
        // never receives anything.
        let hex = token.map { String(format: "%02x", $0) }.joined()

        var err: NSError?
        // `register(forPush:...)` and not `registerForPush(...)`: Swift
        // renames Objective-C methods whose first argument label repeats the
        // verb. gomobile generates the latter; the compiler insists on the
        // former.
        let arn = inner.register(forPush: hex, environment: env.rawValue,
                                 storedEndpoint: PushStore.endpoint(for: setup.id),
                                 error: &err)
        if let err, arn.isEmpty { throw PushError.from(err) }
        PushStore.remember(arn, for: setup.id)
        // An error with an endpoint in hand is the subscription having failed.
        // The endpoint is worth keeping - the next launch retries, and
        // registering again would only make a second one.
        if let err { throw PushError.from(err) }
        return arn
    }

    /// Forgets the local note of the endpoint. The endpoint itself stays in SNS
    /// until APNs disables it: a device that is gone cannot delete anything,
    /// and this is the same device deciding to stop, not proof it went away.
    func forgetPushRegistration() {
        PushStore.forget(mailbox: setup.id)
    }
}

public enum PushError: String, Error, LocalizedError {
    /// No provisioning profile - the simulator, in practice.
    case noEnvironment = "push_no_environment"
    /// The mailbox was set up without push, or without one for this build's
    /// environment.
    case notConfigured = "push_not_configured"
    case refused = "push_refused"

    public var errorDescription: String? {
        NSLocalizedString("compose.\(rawValue)", bundle: .module,
                          comment: "why push could not be set up")
    }

    static func from(_ error: Error) -> PushError {
        PushError(rawValue: (error as NSError).localizedDescription) ?? .refused
    }
}
