// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The mailbox on screen: folders, a list, one message.
///
/// Deliberately plain. Everything that decides anything sits in MailboxModel or
/// below it in Go; what is here is arrangement. That is not modesty - it is the
/// property that keeps the phone and the desktop showing the same mailbox.
public struct MailboxView: View {
    @State private var model: MailboxModel
    @State private var selected: Mailbox.Message?
    @State private var writing: Draft?

    public init(mailbox: Mailbox) {
        _model = State(initialValue: MailboxModel(mailbox: mailbox))
    }

    public var body: some View {
        NavigationSplitView {
            List(model.folders, selection: Binding(
                get: { model.folder },
                set: { model.folder = $0 ?? "" })) { folder in
                    Label {
                        HStack {
                            Text(folder.title)
                            Spacer()
                            if folder.unread > 0 {
                                Text("\(folder.unread)").monospacedDigit().bold()
                            }
                            Text("\(folder.count)").monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Text(folder.icon)
                    }
                    .tag(folder.name)
                }
                .navigationTitle(model.folders.isEmpty ? "s3mail" : t("mailbox.title"))
        } content: {
            list
        } detail: {
            if let selected {
                MessageView(model: model, message: selected)
            } else {
                ContentUnavailableView(t("mailbox.noSelection"), systemImage: "envelope")
            }
        }
        .task { await model.refresh() }
        // Only where a device may actually send. A phone handed a read-only key
        // gets no button rather than a button that fails when tapped.
        .toolbar {
            if model.mailbox.canSend {
                ToolbarItem(placement: .primaryAction) {
                    Button(t("mailbox.compose"), systemImage: "square.and.pencil") {
                        writing = Draft()
                    }
                }
            }
        }
        .sheet(item: $writing) { draft in
            ComposeView(mailbox: model.mailbox, draft: draft)
        }
        .askingAboutUnfinishedSends(model.mailbox)
    }

    @ViewBuilder private var list: some View {
        switch model.state {
        case .idle, .loading where model.messages.isEmpty:
            ProgressView()
        case .failed(let text) where model.messages.isEmpty:
            // Only when there is nothing to show. With mail on screen the
            // failure is a banner, not a wall - see MailboxModel.refresh.
            ContentUnavailableView(t("mailbox.noAccess"), systemImage: "exclamationmark.triangle",
                                   description: Text(text))
        default:
            List(model.messages, selection: $selected) { message in
                MessageRow(message: message).tag(message)
            }
            .searchable(text: Binding(get: { model.query },
                                      set: { model.query = $0; model.reload() }),
                        prompt: t("mailbox.searchPrompt"))
            .refreshable { await model.refresh() }
            .overlay(alignment: .top) {
                if case .failed(let text) = model.state, !model.messages.isEmpty {
                    Text(text).font(.footnote).padding(8)
                        .background(.thinMaterial, in: .rect(cornerRadius: 8))
                        .padding(.horizontal)
                }
            }
        }
    }
}

struct MessageRow: View {
    let message: Mailbox.Message

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(message.from).fontWeight(message.read ? .regular : .semibold)
                    .lineLimit(1)
                Spacer()
                if message.star { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                if message.hasAttachment { Image(systemName: "paperclip") }
            }
            HStack(spacing: 6) {
                Text(message.subject).lineLimit(1)
                if message.spam { Tag(text: t("message.spam"), bad: true) }
                // Only the failure is loud. A tick on every message is a tick
                // nobody reads after a week - the same reasoning as on the desk.
                if message.authFailed { Tag(text: t("message.authFailed"), bad: true) }
            }
            Text(message.snippet).font(.footnote).foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

struct Tag: View {
    let text: String
    var bad = false

    var body: some View {
        Text(text).font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(bad ? Color.red.opacity(0.15) : Color.secondary.opacity(0.15),
                        in: .rect(cornerRadius: 4))
            .foregroundStyle(bad ? .red : .secondary)
    }
}
