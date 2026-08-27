// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation

/// What the screens read, and the only place that decides what "loading",
/// "empty" and "broken" mean.
///
/// A view that works these out for itself ends up with three views that
/// disagree - one shows a spinner forever, one an empty list, one an error the
/// user cannot act on. Here they are one thing, and the views render it.
@Observable
public final class MailboxModel {

    public enum State: Equatable {
        case idle
        case loading
        /// Loaded, possibly empty. Empty is not an error: a new mailbox is
        /// empty, and so is a folder nobody has filed anything into.
        case loaded
        /// Something failed. The text is what the core said, and the core says
        /// it in plain language - see awsx.PlainText.
        case failed(String)
    }

    public private(set) var state: State = .idle
    public private(set) var messages: [Mailbox.Message] = []
    public private(set) var folders: [Mailbox.Folder] = []
    public var folder: String = "" { didSet { if folder != oldValue { reload() } } }
    public var query: String = ""

    /// Readable from the view, because writing a mail and asking about an
    /// unfinished send both go straight to the mailbox - putting a second copy
    /// of those calls in here would only be a longer way to the same place.
    let mailbox: Mailbox

    public init(mailbox: Mailbox) {
        self.mailbox = mailbox
    }

    /// Reads what is already indexed. Fast, offline, and the right thing when a
    /// screen appears: showing the mail from the cache beats showing a spinner
    /// while the network decides.
    public func reload() {
        do {
            messages = try mailbox.search(query, folder: folder)
            folders = try mailbox.folders()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Goes to the bucket. Separate from reload on purpose: pulling to refresh
    /// is a decision, and opening a folder is not.
    public func refresh() async {
        state = .loading
        do {
            _ = try await Task.detached { [mailbox] in try mailbox.refresh() }.value
            reload()
        } catch {
            state = .failed(error.localizedDescription)
            // The list stays: what was on screen a moment ago is still true,
            // and replacing it with an error would hide mail somebody can read.
        }
    }

    /// Moves a message and takes it out of the list at once.
    ///
    /// Optimistic on purpose: a swipe that leaves the row sitting there for a
    /// second feels broken, and the row is coming back on the next refresh if
    /// the move failed. What must not happen is the reverse - a row that
    /// vanishes from a move that did not happen - so a failure puts it back.
    public func move(_ message: Mailbox.Message, to folder: String) {
        let before = messages
        messages.removeAll { $0.id == message.id }
        Task.detached { [mailbox] in
            do {
                _ = try mailbox.move([message.key], to: folder)
            } catch {
                await MainActor.run { self.messages = before }
            }
        }
    }

    /// Flips the star, in the list and in the bucket.
    public func toggleStar(_ message: Mailbox.Message) {
        let wanted = !message.star
        Task.detached { [mailbox] in
            try? mailbox.setStar([message.key], on: wanted)
            await self.refresh()
        }
    }

    /// Marks read or unread.
    public func setRead(_ message: Mailbox.Message, _ on: Bool) {
        Task.detached { [mailbox] in
            try? mailbox.setRead([message.key], on: on)
            await self.refresh()
        }
    }

    public func read(_ message: Mailbox.Message) async throws -> Mailbox.Full {
        try await Task.detached { [mailbox] in try mailbox.read(key: message.key) }.value
    }
}
