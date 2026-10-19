import AppKit

// Renders the SF Symbol "bolt.fill" to a white silhouette PNG (bolt.fill.ink.png)
// used as a CSS mask, so the charging bolt can be tinted by the theme. The PNG is
// generated locally on first run and is NOT shipped (SF Symbols aren't ours to
// redistribute). Requires Xcode Command Line Tools (`swift`).

let names = ["bolt.fill"]
let outDir = CommandLine.arguments[1]
let cfg = NSImage.SymbolConfiguration(pointSize: 200, weight: .regular)

func newBitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
  NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

for name in names {
  guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil),
        let img = sym.withSymbolConfiguration(cfg) else { print("MISS \(name)"); continue }
  img.isTemplate = false
  let sz = img.size
  let w = Int(sz.width.rounded()), h = Int(sz.height.rounded())

  let src = newBitmap(w, h)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: src)
  img.draw(in: NSRect(origin: .zero, size: sz))
  NSGraphicsContext.restoreGraphicsState()

  // Ink = the full glyph silhouette in white; alpha carries the shape so a CSS
  // mask can tint it any colour.
  let ink = newBitmap(w, h)
  let clear = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0)
  for y in 0..<h {
    for x in 0..<w {
      guard let c = src.colorAt(x: x, y: y) else { continue }
      let a = c.alphaComponent
      ink.setColor(a < 0.05 ? clear : NSColor(deviceRed: 1, green: 1, blue: 1, alpha: a), atX: x, y: y)
    }
  }

  try! ink.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: outDir + "/" + name + ".ink.png"))
  print("OK \(name)  \(w)x\(h)")
}
