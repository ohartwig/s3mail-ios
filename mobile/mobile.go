// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

// Package mobile is the whole surface Swift sees.
//
// gomobile can only carry a narrow set of types across the bridge: strings,
// numbers, byte slices, errors, and structs of those. No maps, no slices of
// structs, no generics. Rather than bending the Go API into that shape, this
// package answers in JSON and keeps the bridge to a handful of functions.
//
// That is not a workaround, it is the seam. Everything above it is Swift and
// may be rewritten; everything below it is the same code the desktop program
// runs, and must not be.
package mobile

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"git.ole-hartwig.eu/development/s3mail/s3mail/awsx"
	"git.ole-hartwig.eu/development/s3mail/s3mail/core"
	"git.ole-hartwig.eu/development/s3mail/s3mail/mimeparse"
)

// Version says which core is inside. The first thing the spike proves: Swift
// calls Go, Go answers.
func Version() string { return "s3mail-core/spike" }

// ParseMessage runs a raw message through the same parser the desktop uses and
// returns the summary as JSON. The hardest part of a mail client, and the one
// that must never exist twice - see IOS.md.
func ParseMessage(raw []byte) (string, error) {
	s := mimeparse.Summarize(raw, time.Unix(0, 0).UTC())
	blob, err := json.Marshal(s)
	return string(blob), err
}

// SearchQuery parses a search line the way the mailbox does, so the app can
// show what it understood before it asks anybody for data.
func SearchQuery(query string) (string, error) {
	msgs := []core.Message{}
	out := core.Search(msgs, core.NewData(), query, core.SearchOpts{})
	blob, err := json.Marshal(map[string]any{"query": query, "matches": len(out)})
	return string(blob), err
}

// ctx is a placeholder until the real calls arrive; gomobile cannot carry a
// context across the bridge, so every call that needs one makes its own.
func ctx() context.Context { return context.Background() }

// ListKeys is the second question the spike has to answer: does a real AWS call
// go through from a phone?
//
// That the SDK compiles for iOS says nothing about whether it can reach S3 from
// there - TLS, DNS, the sandbox and the SDK's own credential machinery all have
// to agree. So this makes the smallest possible call and returns what it saw.
//
// Credentials are passed in rather than looked up: there is no ~/.aws on a
// phone, and the app will hand over what it keeps in the keychain. The shape of
// that - one IAM user per device - is IOS.md's business, not this function's.
func ListKeys(accessKey, secret, region, bucket, prefix string, limit int) (string, error) {
	c, err := awsx.Static(ctx(), accessKey, secret, region)
	if err != nil {
		return "", err
	}
	objs, err := awsx.NewS3(c, "").List(ctx(), bucket, prefix)
	if err != nil {
		return "", err
	}
	if limit > 0 && len(objs) > limit {
		objs = objs[:limit]
	}
	keys := make([]string, 0, len(objs))
	for _, o := range objs {
		keys = append(keys, o.Key)
	}
	blob, err := json.Marshal(map[string]any{"count": len(objs), "keys": keys})
	return string(blob), err
}

// UnsealSecret opens the secret access key that a setup code carries, with the
// PIN the desktop showed beside it.
//
// The unsealing lives in the Go core and not in Swift, and that is the point:
// one implementation of PBKDF2 and AES-GCM, tested in one place. Two would
// drift, and the day they drifted the symptom would be a code that pairs on one
// build and not on another.
//
// Answers with the secret, or an error whose text is a code Swift turns into a
// sentence - "wrong_pin" for the one a person can fix by typing again.
func UnsealSecret(sealed, salt, pin string) (string, error) {
	secret, err := core.OpenSecret(sealed, salt, pin)
	if err != nil {
		if errors.Is(err, core.ErrWrongPIN) {
			return "", errors.New("wrong_pin")
		}
		return "", err
	}
	return secret, nil
}

// stringList reads a JSON array of strings. gomobile cannot carry a []string
// across, so lists travel as JSON - the same way everything else here does.
func stringList(raw string) ([]string, error) {
	var out []string
	if err := json.Unmarshal([]byte(raw), &out); err != nil {
		return nil, errors.New("that is not a list of keys")
	}
	return out, nil
}
