// Draws the app icon into an .iconset folder. Run: swift Resources/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // macOS icon grid: the rounded square fills ~80% of the canvas, with a soft shadow below.
    let inset = s * 0.1
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = tile.width * 0.225
    let shape = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.12, green: 0.16, blue: 0.42, alpha: 1),
        NSColor(srgbRed: 0.33, green: 0.22, blue: 0.70, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.36, blue: 0.95, alpha: 1),
    ])!
    gradient.draw(in: shape, angle: 70)

    // A faint glow behind the shield.
    let glowRect = tile.insetBy(dx: tile.width * 0.18, dy: tile.width * 0.18)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.52, weight: .semibold)
        .applying(.init(paletteColors: [NSColor(srgbRed: 0.30, green: 0.22, blue: 0.66, alpha: 1), .white]))
    if let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        let rect = NSRect(x: tile.midX - size.width / 2, y: tile.midY - size.height / 2, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        let symShadow = NSShadow()
        symShadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        symShadow.shadowBlurRadius = s * 0.02
        symShadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        symShadow.set()
        symbol.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
