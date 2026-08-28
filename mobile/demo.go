// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

package mobile

import (
	"time"

	"git.ole-hartwig.eu/development/s3mail/s3mail/demo"
	"git.ole-hartwig.eu/development/s3mail/s3mail/s3fake"
	"git.ole-hartwig.eu/development/s3mail/s3mail/store"
)

// OpenDemo builds the sample mailbox: the same client over a bucket that does
// not exist.
//
// Deliberately a second door and not a flag on Open. A demo that travelled as
// part of Setup would reach the keychain, the pairing code and the push
// registration, and every one of those would need a special case for a mailbox
// that is not real. Here it reaches none of them.
//
// What it shares with the real thing is everything below the bucket:
// store.Mailbox, the index, the folders, the state log, mimeparse. See the demo
// package for why that matters more than it sounds.
// cacheDir is accepted and deliberately ignored - see below.
func OpenDemo(language, cacheDir string) (*Mailbox, error) {
	objects, err := demo.Objects(language, time.Now())
	if err != nil {
		return nil, err
	}
	fake := s3fake.New()
	for key, body := range objects {
		fake.Objs[key] = body
	}

	// allowDelete is false, as it is for a paired phone: what disappears here
	// should be recoverable, and the trash is a folder.
	// No cache directory, and that is not thrift: an empty one makes
	// store.NewMailbox write nothing at all. A sample that leaves an index
	// behind carries it into the next run, and a stale one is a way for the
	// sample to fail to open - which it did, silently, on a simulator that had
	// run it before.
	inner := store.NewMailbox(ctx(), fake, nil, "demo", demo.Root, "", nil, false)
	if _, err := inner.Refresh(ctx()); err != nil {
		return nil, err
	}
	// setup stays empty on purpose. From is what CanSend reads, so the sample
	// offers no compose button - there is nowhere for a sample to send to, and
	// a button that cannot work is worse than no button.
	return &Mailbox{inner: inner, setup: setupPayload{
		Bucket: "demo", Prefix: demo.Root,
	}}, nil
}
