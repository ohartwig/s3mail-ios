// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// One message.
///
/// HTML is shown, under the same four measures the desktop uses - see
/// HTMLBody, where each of them is named. It waited this long on purpose: half
/// of that arrangement would be worse than none, because a mail client that
/// loads remote images by default hands every sender a read receipt.
///
/// Text is preferred when a mail carries both. It is the part the sender wrote
/// for reading rather than for looking at, and it costs nothing to display.
struct MessageView: View {
    let model: MailboxModel
    let message: Mailbox.Message

    @State private var full: Mailbox.Full?
    @State private var failure: String?
    @State private var writing: Draft?
    /// Off for every message, and reset for every message: a decision to fetch
    /// this sender's images is not a decision about the next one.
    @State private var showImages = false
    @State private var htmlHeight: CGFloat = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let full {
                    header(full)
                    Divider()
                    switch MessageBody.choose(text: full.text, html: full.html) {
                    case .html(let html):
                        HTMLBody(html: html, showImages: showImages) { h in
                            htmlHeight = h
                        }
                        .frame(height: htmlHeight)
                        imageToggle
                    case .text(let text):
                        Text(text).textSelection(.enabled)
                    case .empty:
                        Text(t("message.noText"))
                            .foregroundStyle(.secondary)
                    }
                    if !full.attachments.isEmpty { attachments(full) }
                } else if let failure {
                    ContentUnavailableView(t("message.unreadable"), systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
                } else {
                    ProgressView()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Only once the message is read: replying needs its Reply-To and its
        // recipients, and a button that is there before them would answer to
        // the wrong people.
        .toolbar {
            if let full, model.mailbox.canSend {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(t("compose.reply"), systemImage: "arrowshape.turn.up.left") {
                            writing = .replying(to: full, key: message.key)
                        }
                        Button(t("compose.replyAll"), systemImage: "arrowshape.turn.up.left.2") {
                            writing = .replying(to: full, key: message.key, all: true)
                        }
                        Button(t("compose.forward"), systemImage: "arrowshape.turn.up.right") {
                            writing = .forwarding(message.key)
                        }
                    } label: {
                        Label(t("compose.reply"), systemImage: "arrowshape.turn.up.left")
                    }
                }
            }
        }
        .sheet(item: $writing) { draft in
            ComposeView(mailbox: model.mailbox, draft: draft)
        }
        .task(id: message.key) {
            full = nil; failure = nil; showImages = false; htmlHeight = 1
            do { full = try await model.read(message) }
            catch { failure = error.localizedDescription }
        }
    }

    /// Fetching remote images is the reader's decision, taken per message.
    /// The request alone tells the sender that the address is read, when, and
    /// roughly from where - which is what a tracking pixel is for.
    @ViewBuilder private var imageToggle: some View {
        Button(t(showImages ? "message.blockImages" : "message.loadImages"),
               systemImage: showImages ? "eye.slash" : "photo") {
            showImages.toggle()
        }
        .font(.footnote)
        .buttonStyle(.bordered)
    }

    @ViewBuilder private func header(_ full: Mailbox.Full) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(full.subject).font(.title3).bold()
            Text(full.from).font(.subheadline)
            Text(full.to).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                // The parsed date when it parses, the raw header when it does
                // not. A mail with a broken Date: line should lose the nice
                // formatting, not the line.
                if let when = full.when {
                    Text(when, format: .dateTime.day().month(.wide).year()
                        .hour().minute())
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !full.date.isEmpty {
                    Text(full.date).font(.footnote).foregroundStyle(.secondary)
                }
                if full.spam { Tag(text: t("message.spam"), bad: true) }
                if message.authFailed { Tag(text: t("message.authFailed"), bad: true) }
            }
        }
    }

    @ViewBuilder private func attachments(_ full: Mailbox.Full) -> some View {
        Divider()
        // Names and sizes only. The bytes stay where they are until somebody
        // asks - pulling a ten-megabyte attachment into memory because a message
        // was opened is how a mail app gets killed on a phone.
        ForEach(full.attachments) { a in
            Label {
                HStack {
                    Text(a.filename).lineLimit(1)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(a.size),
                                                   countStyle: .file))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
            } icon: {
                Image(systemName: "paperclip")
            }
        }
    }
}
