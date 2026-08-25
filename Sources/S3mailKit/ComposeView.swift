// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Writing a mail.
///
/// Plain text only, and that is a decision rather than a stage: s3mail sends
/// what it can show, and the phone does not render HTML yet (MessageView says
/// why). A composer that produced HTML nobody here could display would be a
/// promise the app cannot keep.
public struct ComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ComposeModel

    public init(mailbox: Mailbox, draft: Draft = Draft()) {
        _model = State(initialValue: ComposeModel(mailbox: mailbox, draft: draft))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("compose.to", text: $model.draft.to)
                    if model.showCopies {
                        field("compose.cc", text: $model.draft.cc)
                        field("compose.bcc", text: $model.draft.bcc)
                    }
                    TextField(t("compose.subject"), text: $model.draft.subject)
                }
                Section {
                    TextEditor(text: $model.draft.body)
                        .frame(minHeight: 220)
                        .font(.body)
                }
                if !model.draft.attachments.isEmpty {
                    Section {
                        ForEach(model.draft.attachments) { a in
                            Label(a.filename, systemImage: "paperclip")
                        }
                    }
                }
            }
            .navigationTitle(t("compose.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Leaving keeps the draft rather than dropping it. Somebody
                    // who wants it gone says so - the button below is right
                    // there, and losing what was typed is the worse mistake.
                    Button(t("compose.save")) {
                        Task { await model.save(); dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.busy {
                        ProgressView()
                    } else {
                        Button(t("compose.send")) {
                            Task { if await model.send() { dismiss() } }
                        }
                        .disabled(!model.canSend)
                    }
                }
            }
            .alert(model.problem ?? "", isPresented: $model.hasProblem) {
                Button("OK", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(model.busy)
    }

    private func field(_ key: String, text: Binding<String>) -> some View {
        TextField(t(key), text: text)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
    }
}

/// The state behind the composer. Separate from the view so that sending - the
/// one thing here that must not be got wrong twice - can be tested without one.
@Observable
final class ComposeModel {
    var draft: Draft
    var busy = false
    var problem: String?
    var hasProblem = false
    /// Cc and Bcc stay folded away until there is something in them. Most mail
    /// has neither, and two empty fields on a phone screen cost more than they
    /// give.
    var showCopies: Bool { !draft.cc.isEmpty || !draft.bcc.isEmpty }

    private let mailbox: Mailbox

    init(mailbox: Mailbox, draft: Draft) {
        self.mailbox = mailbox
        self.draft = draft
    }

    var canSend: Bool { !draft.to.isEmpty && !busy && mailbox.canSend }

    /// Stores the draft and remembers its key, so the next save replaces this
    /// one instead of leaving another object in the folder.
    func save() async {
        guard draft.isWorthKeeping else { return }
        do {
            draft.draftKey = try mailbox.save(draft)
        } catch {
            // A draft that would not store is worth saying, but not worth
            // stopping anything: what was typed is still on the screen.
            report(error)
        }
    }

    /// Sends, and treats a warning as what it is: the mail is out.
    ///
    /// Returns whether the composer may close. It closes on success *and* on a
    /// warning - the message left the house either way, and a window that stays
    /// open invites the one thing that must not happen here, which is sending
    /// it again.
    func send() async -> Bool {
        busy = true
        defer { busy = false }
        do {
            let result = try mailbox.send(draft)
            if let warning = result.warning {
                problem = warning.text
                hasProblem = true
            }
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func report(_ error: Error) {
        problem = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        hasProblem = true
    }
}

/// Short for the catalogue lookup. The bundle has to be named explicitly:
/// inside a package, `.main` is the app's bundle and not this one.
func t(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}
