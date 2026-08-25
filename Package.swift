// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

// The Go core arrives as a binary target and nothing above it knows that. That
// is the seam from IOS.md: Swift above, the same code the desktop runs below.
let package = Package(
    name: "S3mailKit",
    // The language the catalogue falls back to when the phone is set to one
    // that is not in it. English, not German: an unknown language reaching a
    // German sentence would be a surprise, an English one is a convention.
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "S3mailKit", targets: ["S3mailKit"])
    ],
    targets: [
        .binaryTarget(name: "S3mailCore", path: "S3mailCore.xcframework"),
        // The catalogue holds the sentences. The Go core deliberately does not:
        // it names a case ("send_not_permitted") and the phone says it in the
        // language the phone is set to - the same split the desktop makes
        // between core and i18n/locales.
        .target(name: "S3mailKit", dependencies: ["S3mailCore"],
                resources: [.process("Resources")]),
        .testTarget(name: "S3mailKitTests", dependencies: ["S3mailKit"],
                    resources: [.process("20-mixed-charset-subject.eml"),
                                .process("21-outlook-related.eml")])
    ]
)
