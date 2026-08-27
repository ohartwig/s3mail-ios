// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation
import S3mailCore

/// The mailbox, as Swift holds it.
///
/// Thin on purpose. Everything here forwards to the same `store.Mailbox` the
/// desktop program uses; what this file adds is types Swift can work with and a
/// place where the JSON of the bridge stops. If a method here grows logic, it
/// is in the wrong file - the logic belongs in the core, where the desktop gets
/// it too.
public final class Mailbox: @unchecked Sendable {
    // @unchecked, because Swift cannot verify the promise here - but it holds,
    // one level down: store.Mailbox in the core keeps a sync.RWMutex and takes
    // it in every method that touches the index. The desktop has relied on
    // exactly that since v0.1, where several HTTP requests work on the same
    // mailbox at once.
    //
    // The alternative would be to bind the mailbox to the main actor and route
    // every S3 call through it. That would not be safer, only slower, and it
    // would hide a truth that already holds.

    public struct Message: Decodable, Identifiable, Hashable {
        public let key: String
        public let from: String
        public let subject: String
        public let date: String
        public let snippet: String
        public let read: Bool
        public let star: Bool
        public let hasAttachment: Bool
        public let spam: Bool
        public let authFailed: Bool

        public var id: String { key }

        /// The arrival time as a date.
        ///
        /// `date` is RFC 3339 in UTC and stays a string in the core, because
        /// that form sorts as text and the index relies on it. A list wants
        /// "2 hrs ago", so the conversion happens here and not there.
        ///
        /// Two formatters, and that is not belt and braces: in
        /// ISO8601DateFormatter, `.withFractionalSeconds` **requires** them
        /// rather than allowing them. One formatter with the flag rejects every
        /// date the core writes - it uses Go's time.RFC3339, which has none -
        /// and one without it rejects anything that does. Either way the list
        /// would silently show no date at all.
        ///
        /// Static, because building a formatter per row costs more than
        /// everything else in drawing that row put together.
        public var when: Date? {
            Self.plain.date(from: date) ?? Self.fractional.date(from: date)
        }

        private static let plain: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        private static let fractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        enum CodingKeys: String, CodingKey {
            case key, from, subject, date, snippet, read, star, spam
            case hasAttachment = "has_attachment"
            case authFailed = "auth_failed"
        }

        /// Written out rather than left to the compiler, because of one word in
        /// the core: `auth_failed` carries `omitempty`, so the key is absent
        /// whenever it is false - which is nearly every message. A synthesised
        /// decoder demands the key and throws on the ordinary case.
        ///
        /// So every flag is read as "present or false" and every string as
        /// "present or empty". That is not laziness about the schema: this
        /// struct is a view of `core.Message`, which owns the schema and adds
        /// fields as the desktop grows. A phone that refuses to list the
        /// mailbox because a field it does not display appeared - or stopped
        /// being written - is worse than one that shows what it understands.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)  // no key, no message
            from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
            subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
            date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
            snippet = try c.decodeIfPresent(String.self, forKey: .snippet) ?? ""
            read = try c.decodeIfPresent(Bool.self, forKey: .read) ?? false
            star = try c.decodeIfPresent(Bool.self, forKey: .star) ?? false
            spam = try c.decodeIfPresent(Bool.self, forKey: .spam) ?? false
            hasAttachment = try c.decodeIfPresent(Bool.self, forKey: .hasAttachment) ?? false
            authFailed = try c.decodeIfPresent(Bool.self, forKey: .authFailed) ?? false
        }
    }

    public struct Folder: Decodable, Identifiable, Hashable {
        public let name: String
        /// A translation key for the system folders ("folder.sent"), and the
        /// plain name for one somebody made themselves. See `title`.
        public let label: String
        public let icon: String
        public let count: Int
        public let unread: Int

        public var id: String { name }

        /// What to put on the screen.
        ///
        /// `label` is not it. core/folder.go hands out a key rather than a word
        /// on purpose: the folder name is an S3 prefix and must never be
        /// translated, or a client set to another language stops finding the
        /// mail a colleague filed. The desktop looks the key up per request;
        /// this is the same lookup.
        ///
        /// A folder somebody made themselves is not in the catalogue, and
        /// NSLocalizedString answers with the key it was handed - so
        /// "Rechnungen" comes back as "Rechnungen". The fallback is the
        /// feature, not an accident.
        public var title: String {
            NSLocalizedString(label, bundle: .module, comment: "a folder name")
        }

        /// The SF Symbol for this folder.
        ///
        /// `icon` is a name and not a glyph - "inbox", "sent" - for exactly
        /// this: the desktop turns the same word into an SVG from its own
        /// sprite, and here it becomes a symbol the system draws in the weight
        /// and colour of everything around it. An emoji, which is what the core
        /// used to carry, could do neither.
        ///
        /// A folder somebody made themselves is not in the list and gets the
        /// plain folder symbol - the same fallback as its name.
        public var symbol: String {
            switch icon {
            case "inbox": "tray"
            case "drafts": "square.and.pencil"
            case "sent": "paperplane"
            case "archive": "archivebox"
            case "spam": "exclamationmark.triangle"
            case "trash": "trash"
            default: "folder"
            }
        }
    }

    public struct Full: Decodable, Equatable {
        public struct Attachment: Decodable, Equatable, Identifiable {
            public let index: Int
            public let filename: String
            public let size: Int
            public var id: Int { index }
            enum CodingKeys: String, CodingKey { case index, filename, size }
        }
        public let subject: String
        public let from: String
        public let to: String
        public let cc: String
        /// Set by mailing lists and ticket systems. A reply has to obey it, or
        /// the answer lands with whoever pressed send rather than with the list.
        public let replyTo: String
        public let date: String
        public let text: String
        public let html: String
        public let spam: Bool
        public let attachments: [Attachment]

        enum CodingKeys: String, CodingKey {
            case subject, from, to, cc, date, text, html, spam, attachments
            case replyTo = "reply_to"
        }

        /// Lenient for the same reason as Message: a mail with no text part has
        /// no `text`, and one with no attachments may carry no list at all.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
            from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
            to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
            cc = try c.decodeIfPresent(String.self, forKey: .cc) ?? ""
            replyTo = try c.decodeIfPresent(String.self, forKey: .replyTo) ?? ""
            date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            html = try c.decodeIfPresent(String.self, forKey: .html) ?? ""
            spam = try c.decodeIfPresent(Bool.self, forKey: .spam) ?? false
            attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        }
    }

    public struct RefreshResult: Decodable, Equatable {
        public let checked: Int
        public let new: Int
        public let removed: Int
    }

    /// Readable inside the module: Push.swift talks to the same handle, and a
    /// second wrapper around it would only be a longer way to the same call.
    let inner: MobileMailbox
    public let setup: Setup

    /// Opens a mailbox from what the keychain held.
    ///
    /// The cache directory is handed to the core rather than guessed there: a Go
    /// library inside an app has no business deciding where that app keeps its
    /// files. It is **not** encrypted a second time - the app sandbox is already
    /// under the device's own file protection, and a second key to manage would
    /// be more surface than shield. The desktop encrypts because a home
    /// directory travels in backups; a sandbox does not.
    public init(setup: Setup) throws {
        self.setup = setup
        let dir = try Mailbox.cacheDirectory(for: setup)
        var err: NSError?
        guard let inner = MobileOpen(try setup.encode(), dir.path, &err) else {
            throw err ?? CocoaError(.fileNoSuchFile)
        }
        self.inner = inner
    }

    /// Application Support, not Caches: the index is cheap to rebuild but the
    /// state that comes with it is not, and iOS empties Caches when it feels
    /// like it - usually while somebody is on a train with no signal.
    static func cacheDirectory(for setup: Setup) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("mailboxes", isDirectory: true)
            .appendingPathComponent(setup.id.replacingOccurrences(of: "/", with: "_"),
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: nil)
        // The sandbox is protected anyway; this says so out loud and survives a
        // reboot before the first unlock, which a background refresh needs.
        try (dir as NSURL).setResourceValue(
            URLFileProtection.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey)
        return dir
    }

    public func refresh() throws -> RefreshResult {
        try decode(inner.refresh)
    }

    public func folders() throws -> [Folder] {
        try decode(inner.folders)
    }

    /// The same search line the desktop has. An empty folder is the inbox,
    /// "*" is everywhere.
    public func search(_ query: String = "", folder: String = "",
                       limit: Int = 200) throws -> [Message] {
        try decode { err in inner.search(query, folder: folder, limit: limit, error: err) }
    }

    public func read(key: String) throws -> Full {
        try decode { err in inner.read(key, error: err) }
    }

    // MARK: - Doing something to a message

    /// Moves messages into a folder. The empty name is the inbox.
    ///
    /// Answers with how many actually moved: a bulk move survives one message
    /// that will not go, and reporting the number asked for rather than the
    /// number done would be the wrong kind of tidy.
    /// gomobile turns a Go `(int, error)` into an out-parameter plus a BOOL,
    /// not into a return value. Unwrapped here so that everything above this
    /// line reads like Swift.
    @discardableResult
    public func move(_ keys: [String], to folder: String) throws -> Int {
        var moved: Int = 0
        try inner.move(try json(keys), folder: folder, ret0_: &moved)
        return moved
    }

    /// Sets the star. Idempotent by construction - the op says what the flag
    /// should be, not that it should flip - which is what lets two devices set
    /// the same star without arguing about it.
    public func setStar(_ keys: [String], on: Bool) throws {
        try inner.setStar(try json(keys), on: on)
    }

    public func setRead(_ keys: [String], on: Bool) throws {
        try inner.setRead(try json(keys), on: on)
    }

    private func json(_ keys: [String]) throws -> String {
        String(data: try JSONEncoder().encode(keys), encoding: .utf8) ?? "[]"
    }

    // MARK: - Writing and sending

    /// Whether this device was given a sender address. A phone handed a
    /// read-only key has none, and the compose button should not be there at
    /// all rather than fail when tapped.
    public var canSend: Bool { inner.canSend() }

    /// Stores a draft in the bucket and answers with its key. Put that key into
    /// the draft before saving again, or every autosave leaves another
    /// half-written mail in the folder.
    @discardableResult
    public func save(_ draft: Draft) throws -> String {
        struct Saved: Decodable { let key: String }
        let saved: Saved = try decode { err in
            inner.saveDraft(try? encode(draft), error: err)
        }
        return saved.key
    }

    public func dropDraft(key: String) throws {
        try inner.dropDraft(key)
    }

    /// Hands the message to SES.
    ///
    /// A `SendResult` with a warning is still a success - the mail is out. Show
    /// the warning, never the failure: somebody who reads "failed" sends it a
    /// second time, and that is the one mistake this whole path exists to
    /// prevent.
    public func send(_ draft: Draft) throws -> SendResult {
        do {
            return try decode { err in inner.send(try? encode(draft), error: err) }
        } catch {
            throw ComposeError.from(error)
        }
    }

    /// Sends that started and whose end nobody witnessed. Ask on every start;
    /// the app has to put the question to the person, because guessing either
    /// way is wrong in a different direction.
    public func pendingSends() throws -> [PendingSend] {
        try decode(inner.pendingSends)
    }

    /// Records the answer. `sent: true` files the copy and closes the marker,
    /// `false` puts the message back among the drafts.
    public func resolve(pending key: String, sent: Bool) throws {
        try inner.resolveSending(key, sent: sent)
    }

    private func encode(_ draft: Draft) throws -> String {
        String(data: try JSONEncoder().encode(draft), encoding: .utf8) ?? "{}"
    }

    /// Every call across the bridge answers in JSON and reports errors through
    /// an NSError out-parameter. One place to unwrap that, so the rest reads
    /// like ordinary Swift.
    /// `NSErrorPointer` and not `UnsafeMutablePointer<NSError?>?`: gomobile
    /// generates Objective-C, and Swift bridges its error out-parameter to the
    /// autoreleasing form. The two look interchangeable and are not.
    private func decode<T: Decodable>(_ call: (NSErrorPointer) -> String) throws -> T {
        var err: NSError?
        let json = call(&err)
        if let err { throw err }
        guard let blob = json.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode(T.self, from: blob)
    }
}
