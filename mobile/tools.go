// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

//go:build tools

package mobile

// gomobile needs golang.org/x/mobile in go.mod, but nothing here imports it:
// the bridge code is generated at build time, not written. Without this file
// `go mod tidy` removes the requirement and the next `gomobile bind` fails with
// "missing golang.org/x/mobile dependency" - which says nothing about the cause.
import _ "golang.org/x/mobile/bind"
