# SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
# SPDX-License-Identifier: Apache-2.0

# Der Go-Kern kommt als XCFramework herein. Er wird gebaut und nicht
# eingecheckt: 26 MB, und ein eingechecktes Binaerpaket ist nur so aktuell wie
# der Tag, an dem es jemand gebaut hat.
#
# Voraussetzungen: Xcode mit iOS-SDK, Go, und gomobile:
#   go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init

KERN ?= ../S3mail/go

.PHONY: framework test clean

framework:
	cd mobile && PATH="$$HOME/go/bin:$$PATH" gomobile bind -target=ios -o ../S3mailCore.xcframework .

# Braucht eine iOS-Simulator-Laufzeit: xcodebuild -downloadPlatform iOS
test: framework
	xcodebuild test -scheme S3mailKit -destination 'platform=iOS Simulator,name=iPhone 17' | tail -20

clean:
	rm -rf S3mailCore.xcframework .build
