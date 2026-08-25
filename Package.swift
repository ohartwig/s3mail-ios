// swift-tools-version: 5.9
// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

// The Go core arrives as a binary target and nothing above it knows that. That
// is the seam from IOS.md: Swift above, the same code the desktop runs below.
let package = Package(
    name: "S3mailKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "S3mailKit", targets: ["S3mailKit"])
    ],
    targets: [
        .binaryTarget(name: "S3mailCore", path: "S3mailCore.xcframework"),
        .target(name: "S3mailKit", dependencies: ["S3mailCore"]),
        .testTarget(name: "S3mailKitTests", dependencies: ["S3mailKit"],
                    resources: [.process("20-mixed-charset-subject.eml"),
                                .process("21-outlook-related.eml")])
    ]
)
