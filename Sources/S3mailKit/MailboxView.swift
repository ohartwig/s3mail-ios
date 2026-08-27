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
                            // Unread as a badge and read as plain text: the
                            // number that means "there is something for you"
                            // should not look like the one that means "this is
                            // how much is in here".
                            if folder.unread > 0 {
                                Text("\(folder.unread)")
                                    .font(.caption).monospacedDigit().bold()
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(.tint, in: .capsule)
                                    .foregroundStyle(.white)
                            } else if folder.count > 0 {
                                Text("\(folder.count)").monospacedDigit()
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: folder.symbol)
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
        // The `where` twice, and that is not a typo: in a `case` with two
        // patterns it applies only to the second. `.idle` would have matched
        // unconditionally - harmless today, because nothing is loaded while
        // idle, and a bug the moment somebody resets the state on a folder
        // change: a spinner would then sit over mail already on screen.
        case .idle where model.messages.isEmpty,
             .loading where model.messages.isEmpty:
            ProgressView()
        case .failed(let text) where model.messages.isEmpty:
            // Only when there is nothing to show. With mail on screen the
            // failure is a banner, not a wall - see MailboxModel.refresh.
            ContentUnavailableView(t("mailbox.noAccess"), systemImage: "exclamationmark.triangle",
                                   description: Text(text))
        default:
            List(model.messages, selection: $selected) { message in
                MessageRow(message: message).tag(message)
                    // Right to left: what one does most often, and the
                    // destructive one furthest out, where the thumb has to
                    // travel. That order is not decoration - it is why nobody
                    // deletes a mail they meant to archive.
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.move(message, to: "trash")
                        } label: {
                            Label(t("action.trash"), systemImage: "trash")
                        }
                        Button {
                            model.move(message, to: "archiv")
                        } label: {
                            Label(t("action.archive"), systemImage: "archivebox")
                        }
                        .tint(.indigo)
                    }
                    // Left to right: the two that change nothing but a flag,
                    // and both are their own undo - swipe again and it is back.
                    .swipeActions(edge: .leading) {
                        Button {
                            model.setRead(message, !message.read)
                        } label: {
                            Label(message.read ? t("action.unread") : t("action.read"),
                                  systemImage: message.read ? "envelope.badge" : "envelope.open")
                        }
                        .tint(.blue)
                        Button {
                            model.toggleStar(message)
                        } label: {
                            Label(t("action.star"), systemImage: message.star ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
            }
            .listStyle(.plain)
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
        HStack(alignment: .top, spacing: 8) {
            // The unread dot, where every mail app on this platform puts it.
            // A bold sender says the same thing, but only once the eye is
            // already on that line; the dot is findable while scrolling.
            Circle()
                .fill(message.read ? .clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(message.from).fontWeight(message.read ? .regular : .semibold)
                    .lineLimit(1)
                Spacer()
                if message.star {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                        .font(.footnote)
                }
                if message.hasAttachment {
                    Image(systemName: "paperclip").foregroundStyle(.secondary)
                        .font(.footnote)
                }
                if let when = message.when {
                    Text(when, format: .relative(presentation: .numeric))
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
