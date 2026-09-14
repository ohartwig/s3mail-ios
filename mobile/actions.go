// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

package mobile

import (
	"github.com/ohartwig/s3mail/core"
)

// Doing something to a message: move it, star it, mark it read.
//
// These are what a swipe on a phone triggers, and they were the reason a swipe
// was not possible: the bridge could read a mailbox and write a mail, and
// nothing in between. All three go through the same op log the desktop uses -
// there is no second state model, and there must not be one, or the two clients
// would start disagreeing about what is read.

// Move puts messages in a folder. Copy and delete underneath, keeping
// encryption and storage class - see store.Move.
//
// The empty folder name is the inbox, as everywhere here. Answers with the
// number that actually moved: a bulk move survives one message that will not
// go, and saying "12" when 11 moved would be the wrong kind of tidy.
func (m *Mailbox) Move(keysJSON, folder string) (int, error) {
	keys, err := stringList(keysJSON)
	if err != nil {
		return 0, err
	}
	clean := folder
	if folder != "" {
		clean, err = core.ValidFolder(folder)
		if err != nil {
			return 0, err
		}
	}
	results, err := m.inner.Move(ctx(), keys, clean)
	if err != nil {
		return 0, err
	}
	moved := 0
	for _, r := range results {
		if r.Err == "" {
			moved++
		}
	}
	return moved, nil
}

// SetStar and SetRead write a flag op.
//
// Idempotent by construction: the op says what the flag should be, not that it
// should flip. Two phones setting the same star produce the same state, which
// is the property the whole op log is built on.
func (m *Mailbox) SetStar(keysJSON string, on bool) error {
	return m.flags(keysJSON, nil, &on)
}

func (m *Mailbox) SetRead(keysJSON string, on bool) error {
	return m.flags(keysJSON, &on, nil)
}

func (m *Mailbox) flags(keysJSON string, read, star *bool) error {
	keys, err := stringList(keysJSON)
	if err != nil {
		return err
	}
	// The op names message IDs, not keys - that is what makes a flag survive a
	// move between folders, because the ID is the basename and the key is not.
	mids := make([]string, 0, len(keys))
	for _, k := range keys {
		if id := m.inner.Mid(k); id != "" {
			mids = append(mids, id)
		}
	}
	if len(mids) == 0 {
		return nil
	}
	return m.inner.State.Mutate(ctx(), core.Op{T: "flags", Mids: mids, Read: read, Star: star})
}
