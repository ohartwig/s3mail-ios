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
	"time"

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
