// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// One message.
///
/// The HTML part is deliberately **not** rendered yet. On the desktop it goes
/// into a sandboxed iframe with a CSP and external images blocked, and that
/// arrangement is what makes showing a stranger's HTML defensible. A WKWebView
/// needs the same care, and half of it is worse than none: a mail client that
/// loads remote images by default hands every sender a read receipt.
///
/// So for now the text part, and a note when there is HTML the reader is not
/// seeing. Honest and boring beats clever and leaky.
struct MessageView: View {
    let model: MailboxModel
    let message: Mailbox.Message

    @State private var full: Mailbox.Full?
    @State private var failure: String?
    @State private var writing: Draft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let full {
                    header(full)
                    Divider()
                    if full.text.isEmpty && !full.html.isEmpty {
                        Label(t("message.htmlOnly"),
                              systemImage: "doc.richtext")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text(full.text).textSelection(.enabled)
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
            full = nil; failure = nil
            do { full = try await model.read(message) }
            catch { failure = error.localizedDescription }
        }
    }

    @ViewBuilder private func header(_ full: Mailbox.Full) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(full.subject).font(.title3).bold()
            Text(full.from).font(.subheadline)
            Text(full.to).font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(full.date).font(.footnote).foregroundStyle(.secondary)
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
