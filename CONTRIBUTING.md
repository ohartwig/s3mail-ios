<!--
SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
SPDX-License-Identifier: Apache-2.0
-->

# Contributing

Thank you for looking at this. The app is a thin Swift layer over the Go core
of [s3mail](https://github.com/ohartwig/s3mail); most contributions are a
screen that behaves wrongly, a test that shows it, and the lines that fix it.

## Where to send what

- **Bugs and ideas:** issues on [GitHub](https://github.com/ohartwig/s3mail-ios/issues).
  If the problem is in parsing, sending or the bucket, it is probably the
  core's — its issues live at <https://github.com/ohartwig/s3mail/issues>.
- **Changes:** pull requests on GitHub are welcome. Development and the
  pipeline run on the author's GitLab; a pull request is reviewed on GitHub
  and lands there through the mirror, so a merge may take a day.
- **Security problems:** see [SECURITY.md](SECURITY.md), not an issue.

## Setup

Xcode with the iOS SDK and a simulator runtime, and Go 1.27. The core is a
versioned dependency in `mobile/go.mod`; `make framework` builds `gomobile`
into `.bin` and the XCFramework from it; nothing is installed by hand. The author's own checkout carries pipeline material that
is not part of the public repository.

## Commits

Conventional Commits: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`,
`ci`, `chore`. The body says *why*; where a decision was made against an
alternative, it names the alternative. Identifiers, comments and test
messages are English. The author's own commit messages are German; yours may
be either.

## What a change brings with it

- **A test that fails without it.** The package tests under `Tests/` run in
  the simulator against the same mails as the Go corpus; what needs a host
  app (the keychain) lives under `ios-app/Tests`.
- **Every sentence in all three languages** (`de`, `en`, `es`) in
  `Sources/S3mailKit/Resources`; `CatalogueTests` fails otherwise. The
  bridge returns codes, never sentences.
- **Nothing rebuilt that the core already does.** MIME, folders, state,
  sending — if the phone needs it and the core has it, the change is a
  function on the facade in `mobile/`, not a second implementation in Swift.
- **No new dependency.** The package has one binary target and nothing
  else; a Swift package would be a decision, not a convenience.

Before pushing:

```sh
cd mobile && gofmt -l . && go vet ./... && cd ..
make test
```

## What not to add

The limits are decisions, not gaps: no deleting from the phone, no second
encryption layer over the app sandbox, no key that travels in the QR code.
A change to one of those is a conversation first, an issue, and a pull
request last.
