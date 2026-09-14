// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

package mobile

import (
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/ohartwig/s3mail/awsx"
	"github.com/ohartwig/s3mail/core"
	"github.com/ohartwig/s3mail/mailer"
	"github.com/ohartwig/s3mail/mimeparse"
	"github.com/ohartwig/s3mail/store"
)

// Writing and sending, from the phone.
//
// The order of operations here is not this file's invention - it is the one
// web/send.go arrived at, and it is copied deliberately rather than improved
// upon. Two rules make it what it is:
//
//   - Write down what is about to happen before it happens. The marker in
//     store/sending.go survives a process that dies mid-send, which on a phone
//     is not an edge case: iOS kills apps that go to the background at the
//     wrong moment, and it does so without asking.
//   - Once SES has taken the message, nothing afterwards may turn the answer
//     into a failure. A copy that did not reach sent/ is a warning. Reported as
//     an error it reads as "not sent", and the next thing that happens is the
//     same mail going out twice.
//
// The phone makes the first rule matter more and the second one no less.

// Errors here are codes, not sentences. Every user-visible string on this
// platform lives in Swift, where the system's own language settings decide -
// a Go library inside an app has no business holding German text. So the
// bridge names the case and Swift says it out loud.
var (
	errNoRecipient = errors.New("no_recipient")
	errNoSender    = errors.New("no_sender")
	errTooLarge    = errors.New("too_large")
	errNotAllowed  = errors.New("send_not_permitted")
	errRefused     = errors.New("send_refused")
)

// sender is built on demand, not in Open.
//
// A device may hold a key that is allowed to read the bucket and nothing else -
// that is the default the wizard hands out, and for a phone that only reads it
// is the right one. Building an SES client for such a device on every start
// would cost a round trip to discover what the policy already says: nothing.
func (m *Mailbox) ses() *awsx.SES {
	if m.sender == nil {
		m.sender = awsx.NewSES(m.cfg, "")
	}
	return m.sender
}

// SaveDraft stores what somebody has written, without sending it.
//
// The draft is a real message in drafts/ - not a record in some app-local
// store. That is what makes it visible from the desk five minutes later, and it
// is why the phone needs no synchronisation of its own for the one thing people
// most expect to follow them between devices.
func (m *Mailbox) SaveDraft(draftJSON string) (string, error) {
	e, err := m.draft(draftJSON)
	if err != nil {
		return "", err
	}
	n, err := mailer.BuildDraft(e, m.setup.From, mailer.Original{}, time.Now())
	if err != nil {
		return "", code(err)
	}
	// The name comes from the Message-ID, so saving twice replaces rather than
	// piles up - which on a phone happens on every autosave.
	key, err := m.inner.Put(ctx(), core.Drafts, n.ID, n.Raw)
	if err != nil {
		return "", err
	}
	// The old draft only goes once the new one is safely stored. A draft the
	// core renamed is still the same draft; deleting first would lose it if the
	// write below failed.
	if e.DraftKey != "" && e.DraftKey != key {
		_ = m.inner.DropDraft(ctx(), e.DraftKey)
	}
	return asJSON(map[string]any{"key": key, "message_id": n.ID})
}

// DropDraft throws a draft away. Deliberately its own call and not a flag on
// SaveDraft: discarding is a decision, and it should read like one.
func (m *Mailbox) DropDraft(key string) error {
	return m.inner.DropDraft(ctx(), key)
}

// Send builds the message, records the attempt, hands it to SES, and files the
// copy. The sequence is web/send.go's; see the comment at the top of this file
// for why it may not be rearranged.
func (m *Mailbox) Send(draftJSON string) (string, error) {
	e, err := m.draft(draftJSON)
	if err != nil {
		return "", err
	}
	if m.setup.From == "" {
		return "", errNoSender
	}

	var o mailer.Original
	if e.Key != "" {
		// A reply needs the original's Message-ID and References or the thread
		// falls apart in everybody else's client; a forward needs the whole
		// message, because that is what gets attached.
		if raw, err := m.inner.Fetch(ctx(), e.Key, 0); err == nil {
			full := mimeparse.Read(raw, time.Unix(0, 0).UTC())
			o = mailer.Original{MessageID: full.MessageID,
				References: full.References, Subject: full.Subject}
			if e.Mode == "forward" {
				o.Raw = raw
			}
		}
	}

	n, err := mailer.Build(e, m.setup.From, o, time.Now())
	if err != nil {
		return "", code(err)
	}

	// A marker that cannot be written does not stop the send: it is a safety
	// net against a crash, not a permission to send. Refusing here would turn a
	// bucket problem into "you cannot send mail", which is the bigger failure.
	marker, markerErr := m.inner.BeginSend(ctx(), store.Sending{
		To: strings.Join(n.To, ", "), Subject: e.Subject, DraftKey: e.DraftKey,
		MessageID: n.ID, Raw: n.Raw})

	id, err := m.ses().Send(ctx(), n)
	if err != nil {
		// Nothing left the house, so the marker would only raise a question
		// with no content behind it.
		if markerErr == nil {
			_ = m.inner.AbandonSend(ctx(), marker)
		}
		if awsx.IsAuthProblem(err) {
			// Almost always the device policy: a key handed out for reading has
			// no ses:SendRawEmail, and this is where that first shows.
			return "", errNotAllowed
		}
		return "", errRefused
	}

	// From here the message is out of the house. Everything below reports
	// through "warning" and never through an error.
	out := map[string]any{"message_id": id}
	if markerErr != nil {
		out["warning"] = "send_not_recorded"
	} else if err := m.inner.MarkSent(ctx(), marker, id); err != nil {
		out["warning"] = "sent_not_stored"
	}
	if _, err := m.inner.Put(ctx(), core.Sent, n.ID, n.Raw); err != nil {
		out["warning"] = "sent_not_stored"
	}
	if e.DraftKey != "" {
		if err := m.inner.DropDraft(ctx(), e.DraftKey); err != nil {
			out["warning"] = "draft_not_removed"
		}
	}
	if markerErr == nil {
		_ = m.inner.AbandonSend(ctx(), marker)
	}
	return asJSON(out)
}

// PendingSends is what the app asks on every start: did anything not finish?
//
// store.RecoverSends closes what it can decide by itself - a message that made
// it to sent/ clearly went out. What comes back is only what nobody but the
// person can answer, and the app has to ask rather than guess. Guessing "sent"
// loses a mail; guessing "not sent" sends it twice.
func (m *Mailbox) PendingSends() (string, error) {
	open, err := m.inner.RecoverSends(ctx())
	if err != nil {
		return "", err
	}
	list := make([]map[string]any, 0, len(open))
	for _, s := range open {
		list = append(list, map[string]any{
			"key": s.Key, "to": s.To, "subject": s.Subject, "started": s.Started})
	}
	return asJSON(list)
}

// ResolveSending records the answer. sent=true files the copy and closes the
// marker; sent=false puts the message back among the drafts.
func (m *Mailbox) ResolveSending(key string, sent bool) error {
	return m.inner.ResolveSending(ctx(), key, sent)
}

// CanSend says whether this device was given a sender address at all. It does
// not ask AWS: the policy is only proven by an actual send, and a check that
// costs a round trip to return a maybe is worth less than the round trip.
func (m *Mailbox) CanSend() bool { return m.setup.From != "" }

// draft parses what Swift sent. Attachment bytes arrive base64-encoded, which
// is what encoding/json does with []byte in both directions - so the two sides
// agree without either of them having to say so.
func (m *Mailbox) draft(draftJSON string) (mailer.Draft, error) {
	var e mailer.Draft
	if err := json.Unmarshal([]byte(draftJSON), &e); err != nil {
		return e, errors.New("bad_draft")
	}
	return e, nil
}

// code turns the mailer's sentinels into the names Swift knows. Anything else
// passes through unchanged: an unknown error said plainly is more use than a
// familiar one said wrongly.
func code(err error) error {
	switch {
	case errors.Is(err, mailer.ErrNoRecipient):
		return errNoRecipient
	case errors.Is(err, mailer.ErrNoSender):
		return errNoSender
	case errors.Is(err, mailer.ErrTooLarge):
		return errTooLarge
	}
	return err
}
