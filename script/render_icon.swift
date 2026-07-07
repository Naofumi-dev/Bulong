import AppKit
import CoreGraphics

// Bulong icon: ink squircle, mint waveform glyph with a soft glow.
// Renders the AppIcon iconset sizes + a 256px transparent glyph for MenuIcon.
// Run from the repo root: swift script/render_icon.swift

let ink = CGColor(red: 7/255, green: 9/255, blue: 11/255, alpha: 1)
let inkEdge = CGColor(red: 16/255, green: 20/255, blue: 22/255, alpha: 1)
let mint = CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 1)
let mintPale = CGColor(red: 176/255, green: 249/255, blue: 226/255, alpha: 1)

func render(size: Int, glyphOnly: Bool) -> NSBitmapImageRep {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = gctx.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx

    if !glyphOnly {
        // Squircle-ish background (macOS masks Dock icons itself; we still round for Finder)
        let r = s * 0.2237
        let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                          cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        // Subtle vertical ink gradient
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [inkEdge, ink] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: s/2, y: s), end: CGPoint(x: s/2, y: 0), options: [])
    }

    // Glyph: waveform bars, whisper-quiet silhouette.
    // At 16/32px the 7-bar glyph smears into noise, so those sizes drop to 5 bars
    // and pixel-snap the bar rects (standard small-size icon simplification);
    // 64px and up keep the full 7.
    let small = size <= 32 && !glyphOnly
    let heights: [CGFloat] = small
        ? [0.34, 0.56, 0.44, 0.60, 0.28]
        : [0.18, 0.34, 0.56, 0.44, 0.60, 0.28, 0.15]
    let glyphWidth = s * 0.62
    let barW = glyphWidth / CGFloat(heights.count * 2 - 1)   // n bars + (n-1) gaps
    let x0 = (s - glyphWidth) / 2
    let midY = s * (glyphOnly ? 0.5 : 0.52)

    // Soft glow behind the glyph (skipped at 16/32px where it reads as haze)
    if !glyphOnly && !small {
        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 0.28),
                     CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 0)] as CFArray,
            locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s/2, y: midY), startRadius: 0,
                               endCenter: CGPoint(x: s/2, y: midY), endRadius: s * 0.42, options: [])
    }

    let barGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [mintPale, mint] as CFArray, locations: [0, 1])!
    for (i, h) in heights.enumerated() {
        var rect = CGRect(x: x0 + CGFloat(i) * barW * 2, y: midY - s * h / 2,
                          width: barW, height: s * h)
        if small {   // snap to the pixel grid so sub-pixel bars don't smear
            rect = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                          width: max(1, barW.rounded()), height: max(2, rect.height.rounded()))
        }
        let bar = CGPath(roundedRect: rect, cornerWidth: rect.width/2, cornerHeight: rect.width/2, transform: nil)
        ctx.saveGState()
        ctx.addPath(bar)
        ctx.clip()
        ctx.drawLinearGradient(barGrad, start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.minX, y: rect.minY), options: [])
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let iconsetDir = "LocalTalk/Resources/Assets.xcassets/AppIcon.appiconset"
for (px, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                   (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
                   (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    write(render(size: px, glyphOnly: false), to: "\(iconsetDir)/\(name).png")
}
write(render(size: 256, glyphOnly: true), to: "LocalTalk/Resources/Assets.xcassets/MenuIcon.imageset/LocalTalkLogo.png")
