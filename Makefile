# SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
# SPDX-License-Identifier: Apache-2.0

# The Go core arrives as an XCFramework. It is built, not committed: 26 MB, and
# a committed binary package is only ever as current as the day somebody built
# it.
#
# Needs: Xcode with the iOS SDK, Go, and gomobile:
#   go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init

CORE ?= ../S3mail/go

.PHONY: framework test app app-test clean

framework:
	cd mobile && PATH="$$HOME/go/bin:$$PATH" gomobile bind -target=ios -o ../S3mailCore.xcframework .

# Needs an iOS simulator runtime: xcodebuild -downloadPlatform iOS
test: framework
	xcodebuild test -scheme S3mailKit -destination 'platform=iOS Simulator,name=iPhone 17' | tail -20

SIM ?= platform=iOS Simulator,name=iPhone 17 Pro

app: framework
	xcodebuild build -project ios-app/s3mail.xcodeproj -scheme s3mail \
		-destination '$(SIM)' CODE_SIGNING_ALLOWED=NO | tail -5

# The keychain tests live here and not in the package: a SwiftPM test bundle has
# no host app, and without one the simulator refuses keychain access (-34018).
app-test: framework
	xcodebuild test -project ios-app/s3mail.xcodeproj -scheme s3mail \
		-destination '$(SIM)' | tail -20

clean:
	rm -rf S3mailCore.xcframework .build DerivedData
