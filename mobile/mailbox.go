// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

package mobile

import (
	"encoding/json"
	"errors"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"

	"git.ole-hartwig.eu/development/s3mail/s3mail/go/awsx"
	"git.ole-hartwig.eu/development/s3mail/s3mail/go/core"
	"git.ole-hartwig.eu/development/s3mail/s3mail/go/mimeparse"
	"git.ole-hartwig.eu/development/s3mail/s3mail/go/store"
)

// A mailbox on the phone, and it is the same mailbox.
//
// Not a copy of the logic, not a second interpretation of the bucket: this is
// store.Mailbox, the type the desktop program uses, reached through a handle
// Swift can hold. Refresh, folders, search and read all end up in the same code
// that has been reading this bucket since v0.1.
//
// What differs is only what a phone is: no ~/.aws to read credentials from -
// they arrive from the keychain through Setup - and no ~/.cache. The cache
// directory is handed in from Swift, because only the app knows where its
// sandbox is.
type Mailbox struct {
	inner *store.Mailbox
	setup setupPayload
	// cfg is kept so the SES client can be built later, if it is ever needed.
	// See compose.go: a device that only reads never builds one.
	cfg    aws.Config
	sender *awsx.SES
}

type setupPayload struct {
	Bucket    string `json:"bucket"`
	Prefix    string `json:"prefix"`
	Region    string `json:"region"`
	From      string `json:"from"`
	Label     string `json:"label"`
	AccessKey string `json:"accessKey"`
	Secret    string `json:"secret"`

	// PushApps maps Apple's environment name - "production" or "development" -
	// to the SNS platform application for it. Both travel because the device
	// cannot work them out, and it picks the one its own provisioning profile
	// names.
	PushApps  map[string]string `json:"pushApps"`
	PushTopic string            `json:"pushTopic"`
}

// Open builds the mailbox from what the keychain held.
//
// cacheDir is the app's own directory. It is passed rather than guessed: a Go
// library inside an app has no business deciding where that app keeps its
// files, and on iOS the answer is a sandbox path only the app knows.
//
// The cache is not encrypted here, and that is deliberate. On the desktop it is,
// because a home directory travels in backups and synced folders. An app
// sandbox does not: iOS protects it with the device passcode already, and a
// second layer with a second key to manage would be more surface than shield.
func Open(setupJSON, cacheDir string) (*Mailbox, error) {
	var s setupPayload
	if err := json.Unmarshal([]byte(setupJSON), &s); err != nil {
		return nil, errors.New("that is not a mailbox")
	}
	if s.Bucket == "" || s.Region == "" {
		return nil, errors.New("the mailbox is missing its bucket or region")
	}
	cfg, err := awsx.Static(ctx(), s.AccessKey, s.Secret, s.Region)
	if err != nil {
		return nil, err
	}
	prefix := s.Prefix
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	// allowDelete is false: what disappears on a phone should be recoverable.
	// The trash is a folder, and emptying it is a decision for the desk.
	inner := store.NewMailbox(ctx(), awsx.NewS3(cfg, ""), awsx.NewKMS(cfg, ""),
		s.Bucket, prefix, cacheDir, nil, false)
	return &Mailbox{inner: inner, setup: s, cfg: cfg}, nil
}

// Refresh lists the bucket and fetches what changed. Answers with the counts,
// so the interface can say what happened rather than just stopping its spinner.
func (m *Mailbox) Refresh() (string, error) {
	res, err := m.inner.Refresh(ctx())
	if err != nil {
		return "", err
	}
	return asJSON(map[string]any{
		"checked": res.Checked, "new": res.New, "removed": res.Removed,
	})
}

// Folders with their counts, the way the sidebar shows them.
func (m *Mailbox) Folders() (string, error) {
	return asJSON(m.inner.Folders())
}

// Search is the same search line the desktop has - from:, subject:, after:,
// is:unread, tag:, in:. An empty folder name is the inbox; "*" is everywhere.
func (m *Mailbox) Search(query, folder string, limit int) (string, error) {
	o := core.SearchOpts{}
	if folder != "*" {
		clean, err := core.ValidFolder(folder)
		if err != nil {
			return "", err
		}
		o.Folder = &clean
	}
	msgs := m.inner.Search(query, o)
	if limit > 0 && len(msgs) > limit {
		msgs = msgs[:limit]
	}
	return asJSON(msgs)
}

// Read fetches one message whole and hands over what the reader sees: headers,
// text, HTML, the names of the attachments - not their bytes. A phone should
// not pull a ten-megabyte attachment into memory because somebody opened the
// message it hangs on.
func (m *Mailbox) Read(key string) (string, error) {
	// Fetch and parse, the same two steps the desktop's web layer takes. There
	// is no Read on the mailbox because reading is not one operation: the bytes
	// come from S3 or from the cache, and what they mean is mimeparse's job.
	raw, err := m.inner.Fetch(ctx(), key, 0)
	if err != nil {
		return "", err
	}
	full := mimeparse.Read(raw, time.Unix(0, 0).UTC())
	names := make([]map[string]any, 0, len(full.Attachments))
	for _, a := range full.Attachments {
		names = append(names, map[string]any{
			"index": a.Index, "filename": a.Filename,
			"content_type": a.ContentType, "size": a.Size,
		})
	}
	return asJSON(map[string]any{
		"subject": full.Subject, "from": full.From, "to": full.To, "cc": full.Cc,
		// Reply-To goes along because a reply has to obey it. Mailing lists and
		// ticket systems set it, and an answer that ignores it lands with the
		// person who happened to press send instead of with the list.
		"reply_to": full.ReplyTo,
		"date":     full.Date, "text": full.Text, "html": full.HTML,
		"spam": full.Spam, "virus": full.Virus, "auth": full.Auth,
		"unsubscribe": full.Unsub, "attachments": names,
	})
}

func asJSON(v any) (string, error) {
	blob, err := json.Marshal(v)
	return string(blob), err
}
