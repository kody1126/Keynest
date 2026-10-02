import AppKit
import Foundation

// First argument stays compatible with build-app.sh. Optional second argument
// emits previews and clean SVG layers, always outside the .iconset directory.
guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift make-icon.swift OUTPUT.iconset [DESIGN_DIRECTORY]\n", stderr)
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let designOutput = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true) : nil
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [CGFloat((hex >> 16) & 255) / 255,
        CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha])!
}
func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func rotated(_ path: CGPath, degrees: CGFloat, around center: CGPoint) -> CGPath {
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: degrees * .pi / 180).translatedBy(x: -center.x, y: -center.y)
    return path.copy(using: &transform)!
}
let enclosure = rounded(CGRect(x: 62, y: 62, width: 900, height: 900), 211)
let backCard = rotated(rounded(CGRect(x: 231, y: 237, width: 574, height: 603), 105),
    degrees: 8, around: CGPoint(x: 518, y: 540))
let frontCard = rounded(CGRect(x: 208, y: 196, width: 602, height: 627), 111)

// One filled silhouette and one punched-out hole. The small representation has
// optical compensation in its shaft width; it is not a stroked SF Symbol.
func keyShape(compact: Bool = false) -> CGPath {
    let radius: CGFloat = 151
    let halfShaft: CGFloat = compact ? 48 : 44
    let neck = sqrt(radius * radius - halfShaft * halfShaft)
    let angle = asin(halfShaft / radius)
    let key = CGMutablePath()
    key.move(to: CGPoint(x: neck, y: halfShaft))
    key.addLine(to: CGPoint(x: 254, y: halfShaft))
    key.addLine(to: CGPoint(x: 254, y: 106))
    key.addQuadCurve(to: CGPoint(x: 266, y: 118), control: CGPoint(x: 254, y: 118))
    key.addLine(to: CGPoint(x: 314, y: 118))
    key.addQuadCurve(to: CGPoint(x: 326, y: 106), control: CGPoint(x: 326, y: 118))
    key.addLine(to: CGPoint(x: 326, y: halfShaft))
    key.addLine(to: CGPoint(x: 360, y: halfShaft))
    key.addLine(to: CGPoint(x: 360, y: 92))
    key.addQuadCurve(to: CGPoint(x: 372, y: 104), control: CGPoint(x: 360, y: 104))
    key.addLine(to: CGPoint(x: 416, y: 104))
    key.addQuadCurve(to: CGPoint(x: 428, y: 92), control: CGPoint(x: 428, y: 104))
    key.addLine(to: CGPoint(x: 428, y: halfShaft))
    key.addLine(to: CGPoint(x: 461, y: halfShaft))
    key.addQuadCurve(to: CGPoint(x: 485, y: halfShaft - 24), control: CGPoint(x: 485, y: halfShaft))
    key.addLine(to: CGPoint(x: 485, y: 24 - halfShaft))
    key.addQuadCurve(to: CGPoint(x: 461, y: -halfShaft), control: CGPoint(x: 485, y: -halfShaft))
    key.addLine(to: CGPoint(x: neck, y: -halfShaft))
    key.addArc(center: .zero, radius: radius, startAngle: -angle, endAngle: angle, clockwise: true)
    key.closeSubpath()
    let hole: CGFloat = compact ? 70 : 72
    key.addEllipse(in: CGRect(x: -hole, y: -hole, width: hole * 2, height: hole * 2))
    var transform = CGAffineTransform(translationX: 388, y: 614).rotated(by: -.pi / 4)
    return key.copy(using: &transform)!
}
func gradient(_ ctx: CGContext, path: CGPath, colors: [CGColor], locations: [CGFloat],
              from: CGPoint, to: CGPoint, evenOdd: Bool = false) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip(using: evenOdd ? .evenOdd : .winding)
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}
func stroke(_ ctx: CGContext, _ path: CGPath, _ value: CGColor, width: CGFloat) {
    ctx.addPath(path); ctx.setStrokeColor(value); ctx.setLineWidth(width); ctx.strokePath()
}
func fillShadow(_ ctx: CGContext, path: CGPath, value: CGColor, blur: CGFloat,
                offset: CGFloat, scale: CGFloat, evenOdd: Bool = false) {
    ctx.saveGState()
    // Quartz shadows use device space, independently of the current scale.
    ctx.setShadow(offset: CGSize(width: 0, height: offset * scale), blur: blur * scale,
        color: color(0x042D48, 0.30))
    ctx.addPath(path); ctx.setFillColor(value)
    ctx.drawPath(using: evenOdd ? .eoFill : .fill)
    ctx.restoreGState()
}
func renderIcon(_ pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
    fillShadow(ctx, path: enclosure, value: color(0x176D86), blur: 20, offset: -9, scale: scale)
    gradient(ctx, path: enclosure,
        colors: [color(0xA3DFE7), color(0x41ACB3), color(0x08718A), color(0x07546D)],
        locations: [0, 0.34, 0.74, 1], from: CGPoint(x: 230, y: 966), to: CGPoint(x: 780, y: 62))
    // Broad top light, without glare flecks or decorative objects.
    ctx.saveGState(); ctx.addPath(enclosure); ctx.clip()
    let glow = CGGradient(colorsSpace: colorSpace,
        colors: [color(0xE2FFFF, 0.52), color(0xCEF9F4, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 340, y: 944), startRadius: 0,
        endCenter: CGPoint(x: 340, y: 944), endRadius: 790, options: [])
    ctx.restoreGState()
    // The rear storage slip remains subordinate at 16 and 32 pixels.
    ctx.saveGState(); ctx.setAlpha(pixels <= 32 ? 0.58 : 1)
    fillShadow(ctx, path: backCard, value: color(0x82DADF, 0.23), blur: 20, offset: -10, scale: scale)
    gradient(ctx, path: backCard, colors: [color(0xEEFFFF, 0.47), color(0xA9E8EC, 0.10)],
        locations: [0, 1], from: CGPoint(x: 400, y: 873), to: CGPoint(x: 750, y: 225))
    stroke(ctx, backCard, color(0xEDFFFF, 0.42), width: pixels <= 32 ? 3 : 2)
    ctx.restoreGState()
    fillShadow(ctx, path: frontCard, value: color(0x8BD9E1, 0.10), blur: 25, offset: -15, scale: scale)
    gradient(ctx, path: frontCard,
        colors: [color(0xE7FFFF, 0.29), color(0xB9F1ED, 0.11), color(0x56C6D9, 0.18)],
        locations: [0, 0.55, 1], from: CGPoint(x: 390, y: 823), to: CGPoint(x: 610, y: 196))
    stroke(ctx, frontCard, color(0xD5FFFF, pixels <= 32 ? 0.22 : 0.38), width: 2.5)
    ctx.saveGState(); ctx.addPath(frontCard); ctx.replacePathWithStrokedPath(); ctx.clip()
    let rim = CGGradient(colorsSpace: colorSpace,
        colors: [color(0xFFFFFF, 0), color(0xFFFFFF, 0.85)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(rim, start: CGPoint(x: 512, y: 610), end: CGPoint(x: 512, y: 823), options: [])
    ctx.restoreGState()
    let key = keyShape(compact: pixels <= 32)
    fillShadow(ctx, path: key, value: color(0xEBFCFB), blur: 15, offset: -9, scale: scale, evenOdd: true)
    gradient(ctx, path: key, colors: [color(0xFFFFFF), color(0xF1FFFF), color(0xC7EDF3)],
        locations: [0, 0.43, 1], from: CGPoint(x: 420, y: 763), to: CGPoint(x: 670, y: 256), evenOdd: true)
    if pixels >= 64 { stroke(ctx, key, color(0xFFFFFF, 0.66), width: 2) }
    // Defined upper edge in the static fallback. Dynamic system refraction and
    // appearance variants require a separate Icon Composer .icon build.
    ctx.saveGState(); ctx.addPath(enclosure); ctx.setLineWidth(3)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    let edge = CGGradient(colorsSpace: colorSpace,
        colors: [color(0xDFFFFF, 0.10), color(0xFFFFFF, 0.76)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(edge, start: CGPoint(x: 512, y: 180), end: CGPoint(x: 512, y: 964), options: [])
    ctx.restoreGState(); NSGraphicsContext.restoreGraphicsState()
    return rep
}
func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "KeynestIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url, options: .atomic)
}
let representations: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]
for (pixels, name) in representations {
    try writePNG(renderIcon(pixels), to: output.appendingPathComponent(name + ".png"))
}
func pathData(_ path: CGPath) -> String {
    var pieces: [String] = []
    func number(_ x: CGFloat) -> String { String(format: "%.3f", Double(x)) }
    path.applyWithBlock { element in
        let point = element.pointee.points
        func pair(_ index: Int) -> String { "\(number(point[index].x)) \(number(point[index].y))" }
        switch element.pointee.type {
        case .moveToPoint: pieces.append("M \(pair(0))")
        case .addLineToPoint: pieces.append("L \(pair(0))")
        case .addQuadCurveToPoint: pieces.append("Q \(pair(0)) \(pair(1))")
        case .addCurveToPoint: pieces.append("C \(pair(0)) \(pair(1)) \(pair(2))")
        case .closeSubpath: pieces.append("Z")
        @unknown default: break
        }
    }
    return pieces.joined(separator: " ")
}
func writeLayer(_ path: CGPath, name: String, fill: String, to directory: URL) throws {
    // Solid and unmasked: Icon Composer supplies translucency and material.
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <title>Keynest — \(name)</title>
      <g transform="translate(0 1024) scale(1 -1)">
        <path fill="\(fill)" fill-rule="evenodd" d="\(pathData(path))"/>
      </g>
    </svg>
    """
    try svg.write(to: directory.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}
func contactSheet() -> NSBitmapImageRep {
    let width = 1120, height = 640
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(color(0xF4F7F8)); ctx.fill(CGRect(x: 0, y: 320, width: width, height: 320))
    ctx.setFillColor(color(0x172A35)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: 320))
    func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, dark: Bool, weight: NSFont.Weight = .regular) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: color(dark ? 0xC9D8E1 : 0x415563))!]
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }
    label("KEYNEST  /  ICON SIZE REVIEW", x: 40, y: 589, size: 16, dark: false, weight: .semibold)
    label("Actual pixels · static compatibility icon", x: 40, y: 562, size: 13, dark: false)
    for (row, dark) in [(0, false), (1, true)] {
        let y: CGFloat = row == 0 ? 430 : 120
        for (index, size) in [16, 32, 64, 128].enumerated() {
            let center: CGFloat = 152 + CGFloat(index) * 264
            let icon = renderIcon(size)
            let image = NSImage(size: NSSize(width: size, height: size)); image.addRepresentation(icon)
            image.draw(in: CGRect(x: center - CGFloat(size) / 2, y: y - CGFloat(size) / 2,
                width: CGFloat(size), height: CGFloat(size)), from: .zero, operation: .sourceOver, fraction: 1)
            label("\(size) × \(size)", x: center - 24, y: y - 88, size: 13, dark: dark)
        }
    }
    label("Dark background", x: 40, y: 277, size: 13, dark: true)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}
if let designOutput {
    try FileManager.default.createDirectory(at: designOutput, withIntermediateDirectories: true)
    let layers = designOutput.appendingPathComponent("IconComposer-layers", isDirectory: true)
    try FileManager.default.createDirectory(at: layers, withIntermediateDirectories: true)
    try writePNG(renderIcon(1024), to: designOutput.appendingPathComponent("Keynest-1024.png"))
    try writePNG(contactSheet(), to: designOutput.appendingPathComponent("Keynest-small-size-QA.png"))
    try writeLayer(backCard, name: "01-storage-back", fill: "#C7F3F3", to: layers)
    try writeLayer(frontCard, name: "02-storage-front", fill: "#AEE7EE", to: layers)
    try writeLayer(keyShape(), name: "03-key", fill: "#FFFFFF", to: layers)
}
print("Rendered Keynest icon: \(output.path)")
