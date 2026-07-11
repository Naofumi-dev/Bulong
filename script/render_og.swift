import AppKit
import CoreGraphics

// Bulong Open Graph card: 1200x630, ink background, the mint waveform-orb glyph,
// the mono `bulong` wordmark, and the tagline. Mirrors script/render_icon.swift.
// One-off asset — run from the repo root: swift script/render_og.swift

let W = 1200, H = 630
let ink      = CGColor(red: 7/255,   green: 9/255,   blue: 11/255,  alpha: 1)
let inkEdge  = CGColor(red: 16/255,  green: 20/255,  blue: 22/255,  alpha: 1)
let mint     = CGColor(red: 43/255,  green: 222/255, blue: 177/255, alpha: 1)
let mintPale = CGColor(red: 176/255, green: 249/255, blue: 226/255, alpha: 1)
let mintNS   = NSColor(red: 43/255,  green: 222/255, blue: 177/255, alpha: 1)
let textNS   = NSColor(red: 240/255, green: 242/255, blue: 242/255, alpha: 1)
let text2NS  = NSColor(white: 1, alpha: 0.60)
let text3NS  = NSColor(white: 1, alpha: 0.42)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext
let cs = CGColorSpaceCreateDeviceRGB()

// --- Background: diagonal ink gradient ---
let bg = CGGradient(colorsSpace: cs, colors: [inkEdge, ink] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(H)),
                       end: CGPoint(x: CGFloat(W), y: 0), options: [])

// --- Glyph tile (ink squircle + mint waveform + glow), left of the wordmark ---
func drawGlyph(in rect: CGRect) {
    ctx.saveGState()
    let r = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(path); ctx.clip()
    let tile = CGGradient(colorsSpace: cs, colors: [inkEdge, ink] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(tile, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()

    let s = rect.width
    let heights: [CGFloat] = [0.18, 0.34, 0.56, 0.44, 0.60, 0.28, 0.15]
    let glyphWidth = s * 0.62
    let barW = glyphWidth / CGFloat(heights.count * 2 - 1)
    let x0 = rect.minX + (s - glyphWidth) / 2
    let midY = rect.minY + s * 0.52

    let glow = CGGradient(colorsSpace: cs, colors: [
        CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 0.30),
        CGColor(red: 43/255, green: 222/255, blue: 177/255, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: rect.midX, y: midY), startRadius: 0,
                           endCenter: CGPoint(x: rect.midX, y: midY), endRadius: s * 0.42, options: [])

    let barGrad = CGGradient(colorsSpace: cs, colors: [mintPale, mint] as CFArray, locations: [0, 1])!
    for (i, h) in heights.enumerated() {
        let bar = CGRect(x: x0 + CGFloat(i) * barW * 2, y: midY - s * h / 2, width: barW, height: s * h)
        let p = CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
        ctx.saveGState(); ctx.addPath(p); ctx.clip()
        ctx.drawLinearGradient(barGrad, start: CGPoint(x: bar.minX, y: bar.maxY),
                               end: CGPoint(x: bar.minX, y: bar.minY), options: [])
        ctx.restoreGState()
    }
}

let margin: CGFloat = 96
let glyphSize: CGFloat = 132
// y measured from the bottom; center the block vertically
let blockMidY = CGFloat(H) / 2
drawGlyph(in: CGRect(x: margin, y: blockMidY - glyphSize / 2, width: glyphSize, height: glyphSize))

// --- Text (NSAttributedString draws right-side-up in the unflipped bitmap context) ---
func draw(_ s: NSAttributedString, at p: CGPoint) { s.draw(at: p) }

let textX = margin + glyphSize + 40

// Wordmark: mono, large
let wordFont = NSFont.monospacedSystemFont(ofSize: 76, weight: .semibold)
let word = NSAttributedString(string: "bulong", attributes: [.font: wordFont, .foregroundColor: textNS])
let wordSize = word.size()
let wordY = blockMidY + 6   // baseline block: wordmark sits just above center
draw(word, at: CGPoint(x: textX, y: wordY))

// Tagline: "Dictation that speaks Filipino — and never leaves your Mac." with Filipino in mint
let tagFont = NSFont.systemFont(ofSize: 34, weight: .regular)
let tag1 = NSMutableAttributedString(string: "Dictation that speaks ",
    attributes: [.font: tagFont, .foregroundColor: text2NS])
tag1.append(NSAttributedString(string: "Filipino", attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: mintNS]))
tag1.append(NSAttributedString(string: " —", attributes: [.font: tagFont, .foregroundColor: text2NS]))
draw(tag1, at: CGPoint(x: textX, y: wordY - 58))
let tag2 = NSAttributedString(string: "and never leaves your Mac.",
    attributes: [.font: tagFont, .foregroundColor: text2NS])
draw(tag2, at: CGPoint(x: textX, y: wordY - 106))

// Bottom mono line
let footFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
let foot = NSAttributedString(string: "100% on-device  ·  nothing uploaded, ever",
    attributes: [.font: footFont, .foregroundColor: text3NS])
draw(foot, at: CGPoint(x: margin, y: 64))

_ = wordSize
NSGraphicsContext.restoreGraphicsState()

let outPath = "site/assets/og.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (\(W)x\(H))")
