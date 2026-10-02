import AppKit
import Foundation

// Palette exploration preserving the exact C keyring geometry.
// No default icon, previous candidates, or app bundle is changed.
let macosDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : macosDirectory.appendingPathComponent("Resources/design/options-c-palette", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ids = ["C1", "C2", "C3", "C4"]
let titles = ["珍珠蓝紫", "冰蓝通透", "雾白双蓝", "冰蓝银白"]
let subtitles = ["E 配色 · 珍珠白与柔蓝紫", "F 配色 · 冰蓝与清透青蓝", "浅雾白底 · 青蓝与天蓝", "柔蓝底 · 银白与冰蓝"]
let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha])!
}
func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func bitmap(_ width: Int, _ height: Int? = nil) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height ?? width,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}
func fill(_ ctx: CGContext, _ path: CGPath, _ value: CGColor, evenOdd: Bool = false) {
    ctx.addPath(path); ctx.setFillColor(value); ctx.drawPath(using: evenOdd ? .eoFill : .fill)
}
func stroke(_ ctx: CGContext, _ path: CGPath, _ value: CGColor, _ width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(value); ctx.setLineWidth(width); ctx.strokePath()
}
func gradient(_ ctx: CGContext, _ path: CGPath, _ values: [CGColor],
              start: CGPoint = CGPoint(x: 240, y: 962), end: CGPoint = CGPoint(x: 760, y: 62),
              evenOdd: Bool = false) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip(using: evenOdd ? .evenOdd : .winding)
    let locations = values.indices.map { CGFloat($0) / CGFloat(values.count - 1) }
    let gradient = CGGradient(colorsSpace: rgb, colors: values as CFArray, locations: locations)!
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func shadowFill(_ ctx: CGContext, _ path: CGPath, _ value: CGColor, scale: CGFloat,
                blur: CGFloat = 19, offset: CGFloat = -10, alpha: CGFloat = 0.24, evenOdd: Bool = false) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: offset * scale), blur: blur * scale,
        color: color(0x071222, alpha))
    fill(ctx, path, value, evenOdd: evenOdd); ctx.restoreGState()
}
func radialLight(_ ctx: CGContext, _ path: CGPath, value: CGColor, at point: CGPoint, radius: CGFloat) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let light = CGGradient(colorsSpace: rgb, colors: [value, color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
    ctx.restoreGState()
}
let enclosure = rounded(CGRect(x: 62, y: 62, width: 900, height: 900), 211)
func rim(_ ctx: CGContext, _ path: CGPath, light: UInt32 = 0xFFFFFF, alpha: CGFloat = 0.5) {
    ctx.saveGState(); ctx.addPath(path); ctx.setLineWidth(3); ctx.replacePathWithStrokedPath(); ctx.clip()
    let gradient = CGGradient(colorsSpace: rgb, colors: [color(light, 0.06), color(light, alpha)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 80), end: CGPoint(x: 512, y: 963), options: [])
    ctx.restoreGState()
}

struct Palette {
    let base: [UInt32]
    let ring: [UInt32]
    let fob: [UInt32]
    let edge: UInt32?
}
let palettes: [String: Palette] = [
    "C1": Palette(base: [0xFFFFFF, 0xF1F5FA, 0xDEE6F1], ring: [0x98D5FD, 0x7499F0], fob: [0xA6B5F4, 0x8B83E1], edge: nil),
    "C2": Palette(base: [0xF7FDFF, 0xDDEFFA, 0xBFDEF3], ring: [0x9DE7F9, 0x6BBFE7], fob: [0x81CBEA, 0x579DD0], edge: nil),
    "C3": Palette(base: [0xFFFFFF, 0xF2FAFD, 0xDFEFF7], ring: [0x91E0F1, 0x60B9D8], fob: [0x94C7F8, 0x6C9DE6], edge: nil),
    "C4": Palette(base: [0xEDF9FF, 0xCAE5F7, 0xA7CDEB], ring: [0xFFFFFF, 0xE2EDF9], fob: [0xC4E8F9, 0x8BBADA], edge: 0x8AAFC9)
]

func drawRing(_ ctx: CGContext, scale: CGFloat, small: Bool, palette: Palette) {
    shadowFill(ctx, enclosure, color(palette.base.last!), scale: scale, blur: 20, offset: -8, alpha: 0.16)
    gradient(ctx, enclosure, palette.base.map { color($0) })
    radialLight(ctx, enclosure, value: color(0xFFFFFF, 0.45), at: CGPoint(x: 260, y: 900), radius: 850)
    // A spare key fob and a separate keyring: neither repeats A's key silhouette.
    let fob = CGMutablePath()
    fob.addPath(rounded(CGRect(x: 437, y: 193, width: 241, height: 483), 120.5))
    let thickness: CGFloat = small ? 59 : 53
    fob.addPath(rounded(CGRect(x: 437 + thickness, y: 193 + thickness,
        width: 241 - thickness * 2, height: 483 - thickness * 2), 120.5 - thickness))
    var transform = CGAffineTransform(translationX: 557.5, y: 434.5)
        .rotated(by: 25 * .pi / 180).translatedBy(x: -557.5, y: -434.5)
    let hangingFob = fob.copy(using: &transform)!
    shadowFill(ctx, hangingFob, color(palette.fob.last!), scale: scale, blur: 9, offset: -5, alpha: 0.15, evenOdd: true)
    gradient(ctx, hangingFob, palette.fob.map { color($0) },
        start: CGPoint(x: 500, y: 650), end: CGPoint(x: 680, y: 180), evenOdd: true)
    if let edge = palette.edge { stroke(ctx, hangingFob, color(edge, small ? 0.45 : 0.30), small ? 7 : 2) }
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: 269, y: 514, width: 302, height: 302))
    let inner: CGFloat = small ? 94 : 98
    ring.addEllipse(in: CGRect(x: 420 - inner, y: 665 - inner, width: inner * 2, height: inner * 2))
    shadowFill(ctx, ring, color(palette.ring.last!), scale: scale, blur: 9, offset: -5, alpha: 0.16, evenOdd: true)
    gradient(ctx, ring, palette.ring.map { color($0) },
        start: CGPoint(x: 380, y: 816), end: CGPoint(x: 500, y: 514), evenOdd: true)
    if let edge = palette.edge { stroke(ctx, ring, color(edge, small ? 0.60 : 0.42), small ? 8 : 2) }
    rim(ctx, enclosure, alpha: 0.80)
}

func render(_ id: String, pixels: Int) throws -> NSBitmapImageRep {
    let rep = bitmap(pixels)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale); ctx.setShouldAntialias(true)
    drawRing(ctx, scale: scale, small: pixels <= 32, palette: palettes[id]!)
    NSGraphicsContext.restoreGraphicsState(); return rep
}
func png(_ rep: NSBitmapImageRep, name: String) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name), options: .atomic)
}
func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color hex: UInt32 = 0x293640,
          weight: NSFont.Weight = .regular, centered: Bool = false) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color(hex))!]
    let string = value as NSString
    let origin = CGPoint(x: centered ? x - string.size(withAttributes: attributes).width / 2 : x, y: y)
    string.draw(at: origin, withAttributes: attributes)
}
func place(_ rep: NSBitmapImageRep, x: CGFloat, y: CGFloat, size: CGFloat) {
    let image = NSImage(size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)); image.addRepresentation(rep)
    image.draw(in: CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size),
        from: .zero, operation: .sourceOver, fraction: 1)
}
func comparison() throws -> NSBitmapImageRep {
    let rep = bitmap(1120, 1160)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    fill(ctx, CGPath(rect: CGRect(x: 0, y: 0, width: 1120, height: 1160), transform: nil), color(0xF0F2F3))
    text("Keynest · C 版配色探索", x: 45, y: 1102, size: 29, weight: .semibold)
    text("保留 C 的钥匙扣造型 · 延续 E / F 的浅色方向", x: 45, y: 1076, size: 15, color: 0x68737C)
    for index in ids.indices {
        let column = index % 2, row = index / 2
        let x: CGFloat = column == 0 ? 290 : 830
        let bottom: CGFloat = row == 0 ? 571 : 48
        let panel = rounded(CGRect(x: x - 252, y: bottom, width: 504, height: 479), 24)
        fill(ctx, panel, color(0xFFFFFF, 0.84))
        place(try render(ids[index], pixels: 512), x: x, y: bottom + 279, size: 326)
        text("\(ids[index])  ·  \(titles[index])", x: x, y: bottom + 62, size: 24, weight: .semibold, centered: true)
        text(subtitles[index], x: x, y: bottom + 35, size: 14, color: 0x75808A, centered: true)
    }
    NSGraphicsContext.restoreGraphicsState(); return rep
}
func qaSheet(_ id: String) throws -> NSBitmapImageRep {
    let rep = bitmap(1120, 600)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    fill(ctx, CGPath(rect: CGRect(x: 0, y: 300, width: 1120, height: 300), transform: nil), color(0xF5F6F7))
    fill(ctx, CGPath(rect: CGRect(x: 0, y: 0, width: 1120, height: 300), transform: nil), color(0x182632))
    text("\(id) · \(titles[ids.firstIndex(of: id)!]) / Actual pixel sizes", x: 36, y: 547, size: 17, weight: .semibold)
    for row in 0...1 {
        let y: CGFloat = row == 0 ? 421 : 116
        for (index, size) in [16, 32, 64, 128].enumerated() {
            let x = CGFloat(152 + index * 264)
            place(try render(id, pixels: size), x: x, y: y, size: CGFloat(size))
            text("\(size) × \(size)", x: x, y: y - 91, size: 13,
                color: row == 0 ? 0x586B79 : 0xBDCEDB, centered: true)
        }
    }
    text("Dark background", x: 36, y: 267, size: 13, color: 0xBDCEDB)
    NSGraphicsContext.restoreGraphicsState(); return rep
}

for id in ids {
    let iconset = output.appendingPathComponent(id + ".iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for (pixels, name) in sizes {
        try render(id, pixels: pixels).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name + ".png"), options: .atomic)
    }
    try png(render(id, pixels: 1024), name: id + ".png")
    try png(render(id, pixels: 256), name: id + "-256.png")
    try png(qaSheet(id), name: id + "-small-size-QA.png")
}
try png(comparison(), name: "Keynest-C-palette-options.png")
print("Rendered four C palette options to \(output.path). App icon selection was not changed.")
