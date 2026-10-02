import AppKit
import Foundation

// Standalone exploration. It never writes the default AppIcon, any installed
// app bundle, or the first set of icon candidates. All artwork is vector-native.
let macosDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : macosDirectory.appendingPathComponent("Resources/design/options-light-ai", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ids = ["E", "F", "G", "H"]
let titles = ["珍珠星钥", "冰蓝光环", "薄荷连结", "浅紫灵钥"]
let subtitles = ["Pearl + star-cut key", "Ice blue + halo key", "Mint + infinity link", "Lavender + spark key"]
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

func star(_ center: CGPoint, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let r = radius
    p.move(to: CGPoint(x: 0, y: r))
    p.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: r * 0.10, y: r * 0.35), control2: CGPoint(x: r * 0.35, y: r * 0.10))
    p.addCurve(to: CGPoint(x: 0, y: -r), control1: CGPoint(x: r * 0.35, y: -r * 0.10), control2: CGPoint(x: r * 0.10, y: -r * 0.35))
    p.addCurve(to: CGPoint(x: -r, y: 0), control1: CGPoint(x: -r * 0.10, y: -r * 0.35), control2: CGPoint(x: -r * 0.35, y: -r * 0.10))
    p.addCurve(to: CGPoint(x: 0, y: r), control1: CGPoint(x: -r * 0.35, y: r * 0.10), control2: CGPoint(x: -r * 0.10, y: r * 0.35))
    p.closeSubpath()
    var t = CGAffineTransform(translationX: center.x, y: center.y)
    return p.copy(using: &t)!
}
func base(_ ctx: CGContext, scale: CGFloat, shades: [UInt32], glow: UInt32) {
    shadowFill(ctx, enclosure, color(shades.last!), scale: scale, blur: 20, offset: -9, alpha: 0.15)
    gradient(ctx, enclosure, shades.map { color($0) })
    radialLight(ctx, enclosure, value: color(glow, 0.52), at: CGPoint(x: 310, y: 932), radius: 760)
    rim(ctx, enclosure, alpha: 0.82)
}
func material(_ ctx: CGContext, _ path: CGPath, scale: CGFloat, colors: [UInt32],
              evenOdd: Bool = false, small: Bool = false, highlight: Bool = true) {
    shadowFill(ctx, path, color(colors[0]), scale: scale, blur: 15, offset: -8,
        alpha: 0.18, evenOdd: evenOdd)
    gradient(ctx, path, colors.map { color($0) },
        start: CGPoint(x: 350, y: 790), end: CGPoint(x: 690, y: 238), evenOdd: evenOdd)
    if !small && highlight { stroke(ctx, path, color(0xFFFFFF, 0.45), 2) }
}
func starKey(small: Bool) -> CGPath {
    let key = CGMutablePath()
    let half: CGFloat = small ? 48 : 44
    let r: CGFloat = 156
    let a = asin(half / r), neck = sqrt(r * r - half * half)
    key.move(to: CGPoint(x: neck, y: half))
    key.addLine(to: CGPoint(x: 254, y: half))
    key.addLine(to: CGPoint(x: 254, y: 104))
    key.addQuadCurve(to: CGPoint(x: 268, y: 118), control: CGPoint(x: 254, y: 118))
    key.addLine(to: CGPoint(x: 316, y: 118))
    key.addQuadCurve(to: CGPoint(x: 330, y: 104), control: CGPoint(x: 330, y: 118))
    key.addLine(to: CGPoint(x: 330, y: half))
    key.addLine(to: CGPoint(x: 367, y: half))
    key.addLine(to: CGPoint(x: 367, y: 89))
    key.addQuadCurve(to: CGPoint(x: 381, y: 103), control: CGPoint(x: 367, y: 103))
    key.addLine(to: CGPoint(x: 421, y: 103))
    key.addQuadCurve(to: CGPoint(x: 435, y: 89), control: CGPoint(x: 435, y: 103))
    key.addLine(to: CGPoint(x: 435, y: half))
    key.addLine(to: CGPoint(x: 457, y: half))
    key.addQuadCurve(to: CGPoint(x: 481, y: half - 24), control: CGPoint(x: 481, y: half))
    key.addLine(to: CGPoint(x: 481, y: 24 - half))
    key.addQuadCurve(to: CGPoint(x: 457, y: -half), control: CGPoint(x: 481, y: -half))
    key.addLine(to: CGPoint(x: neck, y: -half))
    key.addArc(center: .zero, radius: r, startAngle: -a, endAngle: a, clockwise: true)
    key.closeSubpath()
    key.addPath(star(.zero, radius: small ? 96 : 100))
    var t = CGAffineTransform(translationX: 383, y: 619).rotated(by: -42 * .pi / 180)
    return key.copy(using: &t)!
}
func drawE(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    base(ctx, scale: scale, shades: [0xFFFFFF, 0xF1F5FA, 0xDEE6F1], glow: 0xFFFFFF)
    let key = starKey(small: small)
    material(ctx, key, scale: scale, colors: [0x98D5FD, 0x7499F0, 0x8B83E1], evenOdd: true, small: small)
}
func drawF(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    base(ctx, scale: scale, shades: [0xF7FDFF, 0xDDEFFA, 0xBFDEF3], glow: 0xF7FFFF)
    let key = CGMutablePath()
    key.move(to: CGPoint(x: 470, y: 254))
    key.addQuadCurve(to: CGPoint(x: 489, y: 235), control: CGPoint(x: 470, y: 235))
    key.addLine(to: CGPoint(x: 535, y: 235))
    key.addQuadCurve(to: CGPoint(x: 554, y: 254), control: CGPoint(x: 554, y: 235))
    key.addLine(to: CGPoint(x: 554, y: 286))
    key.addLine(to: CGPoint(x: 637, y: 286))
    key.addQuadCurve(to: CGPoint(x: 656, y: 305), control: CGPoint(x: 656, y: 286))
    key.addLine(to: CGPoint(x: 656, y: 351))
    key.addQuadCurve(to: CGPoint(x: 637, y: 370), control: CGPoint(x: 656, y: 370))
    key.addLine(to: CGPoint(x: 554, y: 370))
    key.addLine(to: CGPoint(x: 554, y: 426))
    key.addLine(to: CGPoint(x: 610, y: 426))
    key.addQuadCurve(to: CGPoint(x: 629, y: 445), control: CGPoint(x: 629, y: 426))
    key.addLine(to: CGPoint(x: 629, y: 488))
    key.addQuadCurve(to: CGPoint(x: 610, y: 507), control: CGPoint(x: 629, y: 507))
    key.addLine(to: CGPoint(x: 554, y: 507))
    key.addLine(to: CGPoint(x: 554, y: 513))
    key.addCurve(to: CGPoint(x: 730, y: 663), control1: CGPoint(x: 661, y: 522), control2: CGPoint(x: 730, y: 579))
    key.addCurve(to: CGPoint(x: 512, y: 818), control1: CGPoint(x: 730, y: 758), control2: CGPoint(x: 633, y: 818))
    key.addCurve(to: CGPoint(x: 294, y: 663), control1: CGPoint(x: 391, y: 818), control2: CGPoint(x: 294, y: 758))
    key.addCurve(to: CGPoint(x: 470, y: 513), control1: CGPoint(x: 294, y: 579), control2: CGPoint(x: 363, y: 522))
    key.addLine(to: CGPoint(x: 470, y: 254)); key.closeSubpath()
    key.addEllipse(in: CGRect(x: 365, y: 587, width: 294, height: 152))
    material(ctx, key, scale: scale, colors: [0xACECFD, 0x7ECDEC, 0x66A8DC], evenOdd: true, small: small)
    // A single orbital highlight follows the head, rather than extra circuitry.
    if !small {
        let arc = CGMutablePath()
        arc.move(to: CGPoint(x: 327, y: 690))
        arc.addCurve(to: CGPoint(x: 694, y: 700), control1: CGPoint(x: 379, y: 809), control2: CGPoint(x: 611, y: 813))
        ctx.setLineCap(.round); stroke(ctx, arc, color(0xF5FFFF, 0.65), 8)
    }
}
func outline(_ path: CGPath, width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}
func drawG(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    base(ctx, scale: scale, shades: [0xFBFFFD, 0xDDF7ED, 0xB5E8D7], glow: 0xFFFFFF)
    let infinity = CGMutablePath()
    infinity.move(to: CGPoint(x: 480, y: 650))
    infinity.addCurve(to: CGPoint(x: 269, y: 650), control1: CGPoint(x: 383, y: 776), control2: CGPoint(x: 269, y: 760))
    infinity.addCurve(to: CGPoint(x: 480, y: 650), control1: CGPoint(x: 269, y: 540), control2: CGPoint(x: 383, y: 524))
    infinity.addCurve(to: CGPoint(x: 691, y: 650), control1: CGPoint(x: 577, y: 776), control2: CGPoint(x: 691, y: 760))
    infinity.addCurve(to: CGPoint(x: 480, y: 650), control1: CGPoint(x: 691, y: 540), control2: CGPoint(x: 577, y: 524))
    infinity.closeSubpath()
    let shaft = CGMutablePath()
    shaft.move(to: CGPoint(x: 601, y: 568)); shaft.addLine(to: CGPoint(x: 725, y: 331))
    let teeth = CGMutablePath()
    teeth.move(to: CGPoint(x: 678, y: 421)); teeth.addLine(to: CGPoint(x: 740, y: 452))
    teeth.move(to: CGPoint(x: 714, y: 352)); teeth.addLine(to: CGPoint(x: 775, y: 383))
    // Boolean union creates one boundary, including the head/shaft junction.
    let body = outline(infinity, width: small ? 77 : 72)
        .union(outline(shaft, width: small ? 81 : 75))
        .union(outline(teeth, width: small ? 65 : 61))
    material(ctx, body, scale: scale, colors: [0x91DBCF, 0x60C1AB, 0x47A99B], small: small, highlight: false)
}
func drawH(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    base(ctx, scale: scale, shades: [0xFDF7FF, 0xEEE0F7, 0xD9C6EE], glow: 0xFFFEFF)
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 551, y: 589)); stem.addLine(to: CGPoint(x: 304, y: 337))
    let teeth = CGMutablePath()
    teeth.move(to: CGPoint(x: 379, y: 413)); teeth.addLine(to: CGPoint(x: 432, y: 361))
    teeth.move(to: CGPoint(x: 322, y: 356)); teeth.addLine(to: CGPoint(x: 372, y: 305))
    let shades: [UInt32] = [0xC6AAEB, 0xB299E1, 0xA18ACF]
    let hole: CGFloat = small ? 48 : 47
    let aperture = CGPath(ellipseIn: CGRect(x: 617 - hole, y: 655 - hole,
        width: hole * 2, height: hole * 2), transform: nil)
    let body = star(CGPoint(x: 617, y: 655), radius: 208)
        .union(outline(stem, width: small ? 86 : 81))
        .union(outline(teeth, width: small ? 65 : 61))
        .subtracting(aperture)
    material(ctx, body, scale: scale, colors: shades, small: small, highlight: false)
}

func render(_ id: String, pixels: Int) throws -> NSBitmapImageRep {
    let rep = bitmap(pixels)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale); ctx.setShouldAntialias(true)
    switch id {
    case "E": drawE(ctx, scale: scale, small: pixels <= 32)
    case "F": drawF(ctx, scale: scale, small: pixels <= 32)
    case "G": drawG(ctx, scale: scale, small: pixels <= 32)
    case "H": drawH(ctx, scale: scale, small: pixels <= 32)
    default: preconditionFailure("Unknown design")
    }
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
    text("Keynest · 浅色 AI 钥匙", x: 45, y: 1102, size: 29, weight: .semibold)
    text("星芒、光环与连结 · 新一组浅色方案", x: 45, y: 1076, size: 15, color: 0x68737C)
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
try png(comparison(), name: "Keynest-light-ai-options.png")
print("Rendered four light AI/key options to \(output.path). App icon selection was not changed.")
