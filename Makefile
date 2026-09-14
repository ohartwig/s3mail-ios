# SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
# SPDX-License-Identifier: Apache-2.0

# The Go core arrives as an XCFramework. It is built, not committed: 26 MB, and
# a committed binary package is only ever as current as the day somebody built
# it.
#
# Needs: Xcode with the iOS SDK and Go. gomobile is built here, not installed
# by hand - see the tools target.

.PHONY: framework test app app-test shots tools clean

# gomobile and gobind are built into .bin from the versions pinned in
# mobile/go.mod - deliberately not `@latest`.
#
# Two reasons. A build machine somebody set up by hand once is a machine nobody
# can rebuild: the first CI run on the Mac failed with "gomobile: command not
# found", and the answer to that is a Makefile that brings its own tools, not a
# runner with a special history. And `@latest` would let the CI build with a
# different gomobile than the desk - "it must be gomobile" is the hardest kind
# of bug hunt there is.
BIN := $(CURDIR)/.bin

$(BIN)/gomobile:
	cd mobile && GOBIN=$(BIN) go install \
		golang.org/x/mobile/cmd/gomobile golang.org/x/mobile/cmd/gobind

tools: $(BIN)/gomobile

framework: $(BIN)/gomobile
	cd mobile && PATH="$(BIN):$$PATH" gomobile bind -target=ios -o ../S3mailCore.xcframework .

# Needs an iOS simulator runtime: xcodebuild -downloadPlatform iOS
test: framework
	xcodebuild test -scheme S3mailKit -destination 'platform=iOS Simulator,name=iPhone 17' | tail -20

SIM ?= platform=iOS Simulator,name=iPhone 17 Pro
# Das 6,9-Zoll-Geraet, fuer das Apple die Screenshots verlangt.
SHOT_SIM ?= platform=iOS Simulator,name=iPhone 17 Pro Max

app: framework
	xcodebuild build -project ios-app/s3mail.xcodeproj -scheme s3mail \
		-destination '$(SIM)' CODE_SIGNING_ALLOWED=NO | tail -5

# The keychain tests live here and not in the package: a SwiftPM test bundle has
# no host app, and without one the simulator refuses keychain access (-34018).
app-test: framework
	xcodebuild test -project ios-app/s3mail.xcodeproj -scheme s3mail \
		-skip-testing:UITests -destination '$(SIM)' | tail -20

# Die App-Store-Screenshots. Getrennt von app-test, weil sie den Simulator
# hochfahren und die App durchklicken - das gehoert nicht in jeden Testlauf.
# Die Bilder landen als Anhaenge im Result-Bundle; herausholen mit
# `xcrun xcresulttool export attachments --path shots.xcresult --output-path .`
shots: framework
	rm -rf shots.xcresult
	xcodebuild test -project ios-app/s3mail.xcodeproj -scheme s3mail \
		-only-testing:UITests -destination '$(SHOT_SIM)' \
		-resultBundlePath shots.xcresult | tail -20

clean:
	rm -rf S3mailCore.xcframework .build DerivedData $(BIN)
