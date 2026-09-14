<!--
SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
SPDX-License-Identifier: Apache-2.0
-->

# Security policy

## Reporting a vulnerability

Please do not open a public issue or pull request for a security problem.
Send a report to <security@ole-hartwig.eu>; a PGP key for attachments is
published at <https://ole-hartwig.eu/.well-known/openpgpkey> (RFC 9580).

You will get an acknowledgement within 72 hours on business days and a
triage result within 7 days. Findings stay embargoed until a fix is released,
90 days after first response at the latest, and the reporter is credited
unless they prefer not to be.

## What counts

In scope: the app built from this repository and the Go bridge under
`mobile/` — in particular anything that lets a key be read from the QR code
without the PIN, from the keychain while the phone is locked, or from a
backup on another device; lets a mail in the bucket run script or load a
remote resource in the HTML view; reaches a mailbox beyond the prefix the
device's IAM user was scoped to; or makes a message leave twice or not at all
while the send marker says otherwise.

Out of scope: AWS itself (S3, SES, SNS, IAM — report those to Amazon), iOS,
and the desktop program, which has its own repository and the same policy:
<https://github.com/ohartwig/s3mail>.

## Supported versions

The latest release in the App Store. Fixes go out as the next release and
are noted in the release notes with a `security` mention.
