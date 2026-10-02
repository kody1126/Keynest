import AppKit
import Foundation

// Exploration only. This renderer never changes AppIcon, the app bundle, or the
// active make-icon.swift script. A copies the accepted icon's exact pixels.
let macosDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : macosDirectory.appendingPathComponent("Resources/design/options", isDirectory: true)
let aSource = macosDirectory.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let ids = ["A", "B", "C", "D"]
let titles = ["冰青玻璃", "深蓝保险库", "暖白钥匙扣", "淡紫字形"]
let subtitles = ["Key + layered collection", "Vault + keyhole", "Ring + minimal outline", "Abstract K + key"]
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

func drawVault(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    shadowFill(ctx, enclosure, color(0x142641), scale: scale)
    gradient(ctx, enclosure, [color(0x345373), color(0x1B314E), color(0x0B182D)])
    radialLight(ctx, enclosure, value: color(0x6F9DBF, 0.20), at: CGPoint(x: 256, y: 980), radius: 780)
    let door = rounded(CGRect(x: 226, y: 218, width: 572, height: 592), 118)
    shadowFill(ctx, door, color(0x26486C), scale: scale, blur: 28, offset: -17, alpha: 0.43)
    gradient(ctx, door, [color(0x5F87AA), color(0x365C82), color(0x203F64)],
        start: CGPoint(x: 300, y: 810), end: CGPoint(x: 680, y: 218))
    stroke(ctx, door, color(0xA6CAE4, 0.46), small ? 6 : 3)
    let inset = rounded(CGRect(x: 255, y: 247, width: 514, height: 534), 93)
    stroke(ctx, inset, color(0x162E4F, small ? 0.18 : 0.43), small ? 3 : 4)
    // One lit aperture; the keyhole is a continuous filled silhouette.
    let aperture = CGMutablePath()
    aperture.move(to: CGPoint(x: 443, y: 395))
    aperture.addQuadCurve(to: CGPoint(x: 459, y: 378), control: CGPoint(x: 441, y: 378))
    aperture.addLine(to: CGPoint(x: 565, y: 378))
    aperture.addQuadCurve(to: CGPoint(x: 581, y: 395), control: CGPoint(x: 583, y: 378))
    aperture.addLine(to: CGPoint(x: 552, y: 514))
    aperture.addArc(center: CGPoint(x: 512, y: 584), radius: 81,
        startAngle: -.pi / 3, endAngle: 4 * .pi / 3, clockwise: false)
    aperture.addLine(to: CGPoint(x: 443, y: 395)); aperture.closeSubpath()
    shadowFill(ctx, aperture, color(0xDFEEF7), scale: scale, blur: 8, offset: -3, alpha: 0.32)
    gradient(ctx, aperture, [color(0xFFFFFF), color(0xDCECF4), color(0xAACBDD)],
        start: CGPoint(x: 480, y: 665), end: CGPoint(x: 550, y: 376))
    // Two broad hinge forms anchor the object without dial/corner-screw clutter.
    for y: CGFloat in [349, 598] {
        let hinge = rounded(CGRect(x: 205, y: y, width: 45, height: 80), 16)
        gradient(ctx, hinge, [color(0x668AAB), color(0x315374)],
            start: CGPoint(x: 205, y: y + 80), end: CGPoint(x: 250, y: y))
    }
    rim(ctx, enclosure, light: 0xA9D4EF, alpha: 0.50)
}

func drawRing(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    shadowFill(ctx, enclosure, color(0xE2DDD3), scale: scale, blur: 20, offset: -8, alpha: 0.16)
    gradient(ctx, enclosure, [color(0xFFFDF7), color(0xF2EEE6), color(0xDDD8CE)])
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
    shadowFill(ctx, hangingFob, color(0x45484A), scale: scale, blur: 9, offset: -5, alpha: 0.15, evenOdd: true)
    gradient(ctx, hangingFob, [color(0x686B6A), color(0x303538)],
        start: CGPoint(x: 500, y: 650), end: CGPoint(x: 680, y: 180), evenOdd: true)
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: 269, y: 514, width: 302, height: 302))
    let inner: CGFloat = small ? 94 : 98
    ring.addEllipse(in: CGRect(x: 420 - inner, y: 665 - inner, width: inner * 2, height: inner * 2))
    shadowFill(ctx, ring, color(0x373D40), scale: scale, blur: 9, offset: -5, alpha: 0.16, evenOdd: true)
    gradient(ctx, ring, [color(0x606668), color(0x292F33)],
        start: CGPoint(x: 380, y: 816), end: CGPoint(x: 500, y: 514), evenOdd: true)
    rim(ctx, enclosure, alpha: 0.80)
}

func drawMonogram(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    shadowFill(ctx, enclosure, color(0xB8AFE2), scale: scale, blur: 20, offset: -9, alpha: 0.20)
    gradient(ctx, enclosure, [color(0xF0EAFD), color(0xD5CCF2), color(0xABA3DF)])
    radialLight(ctx, enclosure, value: color(0xFFFFFF, 0.37), at: CGPoint(x: 300, y: 940), radius: 870)
    // K's vertical stem is also a key shaft; its upper terminal is a pierced bow.
    // This is custom geometry, not text or a font glyph.
    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: 315, y: 254))
    mark.addQuadCurve(to: CGPoint(x: 332, y: 237), control: CGPoint(x: 315, y: 237))
    mark.addLine(to: CGPoint(x: 396, y: 237))
    mark.addQuadCurve(to: CGPoint(x: 413, y: 254), control: CGPoint(x: 413, y: 237))
    mark.addLine(to: CGPoint(x: 413, y: 429))
    mark.addLine(to: CGPoint(x: 467, y: 487))
    mark.addLine(to: CGPoint(x: 659, y: 255))
    mark.addQuadCurve(to: CGPoint(x: 690, y: 241), control: CGPoint(x: 671, y: 241))
    mark.addLine(to: CGPoint(x: 757, y: 241))
    mark.addQuadCurve(to: CGPoint(x: 770, y: 267), control: CGPoint(x: 786, y: 241))
    mark.addLine(to: CGPoint(x: 539, y: 572))
    mark.addLine(to: CGPoint(x: 743, y: 775))
    mark.addQuadCurve(to: CGPoint(x: 731, y: 799), control: CGPoint(x: 766, y: 799))
    mark.addLine(to: CGPoint(x: 660, y: 799))
    mark.addQuadCurve(to: CGPoint(x: 628, y: 785), control: CGPoint(x: 642, y: 799))
    mark.addLine(to: CGPoint(x: 413, y: 582))
    let angle = acos(CGFloat(49) / 128)
    mark.addLine(to: CGPoint(x: 413, y: 717 - sqrt(128 * 128 - 49 * 49)))
    mark.addArc(center: CGPoint(x: 364, y: 717), radius: 128,
        startAngle: -angle, endAngle: .pi + angle, clockwise: false)
    mark.addLine(to: CGPoint(x: 315, y: 254)); mark.closeSubpath()
    let hole: CGFloat = small ? 55 : 54
    mark.addEllipse(in: CGRect(x: 364 - hole, y: 717 - hole, width: hole * 2, height: hole * 2))
    shadowFill(ctx, mark, color(0x4D4684), scale: scale, blur: 18, offset: -9, alpha: 0.20, evenOdd: true)
    gradient(ctx, mark, [color(0x7061AC), color(0x504087), color(0x342D65)],
        start: CGPoint(x: 370, y: 846), end: CGPoint(x: 720, y: 237), evenOdd: true)
    if !small { stroke(ctx, mark, color(0xFFFFFF, 0.24), 2) }
    rim(ctx, enclosure, alpha: 0.77)
}

func render(_ id: String, pixels: Int) throws -> NSBitmapImageRep {
    if id == "A" {
        let name = sizes.first(where: { $0.0 == pixels })!.1
        guard let rep = NSBitmapImageRep(data: try Data(contentsOf: aSource.appendingPathComponent(name + ".png"))) else {
            throw NSError(domain: "KeynestOptions", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Render the accepted A icon first with make-icon.swift"])
        }
        return rep
    }
    let rep = bitmap(pixels)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale); ctx.setShouldAntialias(true)
    switch id {
    case "B": drawVault(ctx, scale: scale, small: pixels <= 32)
    case "C": drawRing(ctx, scale: scale, small: pixels <= 32)
    case "D": drawMonogram(ctx, scale: scale, small: pixels <= 32)
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
    text("Keynest · 图标方案", x: 45, y: 1102, size: 29, weight: .semibold)
    text("四种形状与材质方向 · 当前 App 保留 A", x: 45, y: 1076, size: 15, color: 0x68737C)
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
        let target = iconset.appendingPathComponent(name + ".png")
        if id == "A" {
            try Data(contentsOf: aSource.appendingPathComponent(name + ".png")).write(to: target, options: .atomic)
        } else {
            try render(id, pixels: pixels).representation(using: .png, properties: [:])!.write(to: target, options: .atomic)
        }
    }
    // Exact A master copy, so the comparison cannot accidentally revise it.
    if id == "A" {
        try Data(contentsOf: aSource.appendingPathComponent("icon_512x512@2x.png")).write(to: output.appendingPathComponent("A.png"), options: .atomic)
    } else { try png(render(id, pixels: 1024), name: id + ".png") }
    try png(render(id, pixels: 256), name: id + "-256.png")
    try png(qaSheet(id), name: id + "-small-size-QA.png")
}
try png(comparison(), name: "Keynest-icon-options.png")
print("Wrote four static icon options to \(output.path). Active AppIcon was not changed.")
