// SPDX-FileCopyrightText: 2026 Kai Ole Hartwig <mail@ole-hartwig.eu>
// SPDX-License-Identifier: Apache-2.0
//
// Draws the app icon. Run it, do not hand-edit the PNG:
//
//     swift ios-app/icon.swift ios-app/Sources/Assets.xcassets/AppIcon.appiconset/icon.png
//
// A committed image with no source is a thing nobody can change: the next
// person who wants a different shade has a binary and no way in. This is the
// same reasoning as the XCFramework being built rather than committed.
//
// The design is deliberately plain. An icon is read at 29 points on a settings
// screen, and whatever does not survive that size is decoration that makes the
// small version worse. So: one ground, one envelope, nothing else. No gradient,
// no shadow, no rounded corners - iOS applies its own mask, and a corner drawn
// here would show up as a dark rim inside Apple's.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
// No alpha: the App Store refuses an icon with transparency, and the refusal
// arrives at upload time, long after anybody was thinking about the icon.
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                    bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, 1])!
}

// Ink, not black: a pure black square looks like a hole between other icons.
ctx.setFillColor(color(0x1C, 0x27, 0x36))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

let u = CGFloat(side) / 32          // one grid unit
let w = 20 * u, h = 13 * u          // the envelope
let x = (CGFloat(side) - w) / 2, y = (CGFloat(side) - h) / 2

// The body, as an outline rather than a filled block: filled, the flap below
// would have to be drawn in the ground colour, and then the icon falls apart on
// any background that is not this one.
let stroke = 1.15 * u
ctx.setStrokeColor(color(0xF7, 0xF9, 0xFB))
ctx.setLineWidth(stroke)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)

let r = 1.2 * u
let body = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                  cornerWidth: r, cornerHeight: r, transform: nil)
ctx.addPath(body)
ctx.strokePath()

// The flap. It stops short of the corners on purpose: running it exactly into
// them makes the join look heavy at small sizes.
let inset = 0.9 * u
ctx.move(to: CGPoint(x: x + inset, y: y + h - inset))
ctx.addLine(to: CGPoint(x: x + w/2, y: y + h/2 - 0.6*u))
ctx.addLine(to: CGPoint(x: x + w - inset, y: y + h - inset))
ctx.strokePath()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("cannot write \(out)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("PNG not written\n".utf8))
    exit(1)
}
print("\(out): \(side)x\(side)")
