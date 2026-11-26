// The app's icon, drawn rather than exported: Lun's wordmark, the same stroke
// as Design.swift's `Logomark`, on a warm paper plate. A Dock icon has to be
// an opaque square whether the logo itself wants a background or not.

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")

/// A dev build (build.sh) puts the mark on a yellow plate rather than a paper
/// one, as Chrome Canary does, so the build from a worktree and the installed
/// app are told apart at a glance: in the Dock, in ⌘Tab, at 16 points.
let dev = ProcessInfo.processInfo.environment["SEARCH_DEV"] == "1"
let plateColor = dev ? NSColor(srgbRed: 1.0, green: 0.8, blue: 0.2, alpha: 1) : NSColor(srgbRed: 0xF4 / 255, green: 0xEE / 255, blue: 0xE6 / 255, alpha: 1)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// The wordmark's ink, on a canvas of its own size, y growing downward as in
/// SVG: three letters from one round-ended stroke.
let canvas = CGSize(width: 143, height: 77)
let pen: CGFloat = 13
/// Its share of the plate's width, and the lone l's stroke and height.
let markShare: CGFloat = 0.715
let smallPen: CGFloat = 0.16
let smallHeight: CGFloat = 0.68

/// The wordmark as one outline, its overlaps merged so any fill rule and any
/// SVG reader draws it the same.
func wordmark() -> CGPath {
    let h = pen / 2
    let line = CGMutablePath()
    line.move(to: CGPoint(x: h, y: h))
    line.addLine(to: CGPoint(x: h, y: 64 + h))
    line.move(to: CGPoint(x: 26 + h, y: 24 + h))
    line.addLine(to: CGPoint(x: 26 + h, y: 44 + h))
    line.addArc(center: CGPoint(x: 46 + h, y: 44 + h), radius: 20, startAngle: .pi, endAngle: 0, clockwise: true)
    line.addLine(to: CGPoint(x: 66 + h, y: 24 + h))
    line.move(to: CGPoint(x: 66 + h, y: 24 + h))
    line.addLine(to: CGPoint(x: 66 + h, y: 64 + h))
    line.move(to: CGPoint(x: 90 + h, y: 24 + h))
    line.addLine(to: CGPoint(x: 90 + h, y: 64 + h))
    line.move(to: CGPoint(x: 90 + h, y: 44 + h))
    line.addArc(center: CGPoint(x: 110 + h, y: 44 + h), radius: 20, startAngle: .pi, endAngle: 0, clockwise: false)
    line.addLine(to: CGPoint(x: 130 + h, y: 64 + h))
    return line.copy(strokingWithWidth: pen, lineCap: .round, lineJoin: .round, miterLimit: 10)
        .normalized(using: .winding)
}

/// The mark centred on `plate`: the whole word, or at 32 points and below the
/// l alone, which still reads at 16.
func markPath(in plate: NSRect, small: Bool) -> CGPath {
    if small {
        let width = plate.width * smallPen
        let height = plate.height * smallHeight
        let bar = CGRect(x: plate.midX - width / 2, y: plate.midY - height / 2, width: width, height: height)
        return CGPath(roundedRect: bar, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)
    }
    let scale = plate.width * markShare / canvas.width
    // AppKit's y grows upward, so the word is turned over on the way in.
    var fit = CGAffineTransform(translationX: plate.midX - canvas.width * scale / 2,
                                y: plate.midY + canvas.height * scale / 2).scaledBy(x: scale, y: -scale)
    return wordmark().copy(using: &fit)!
}

/// A path's commands as an SVG path's data.
func svgData(_ path: CGPath) -> String {
    var out = ""
    func n(_ p: CGPoint) -> String { String(format: "%.3f %.3f ", p.x, p.y) }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: out += "M" + n(e.points[0])
        case .addLineToPoint: out += "L" + n(e.points[0])
        case .addQuadCurveToPoint: out += "Q" + n(e.points[0]) + n(e.points[1])
        case .addCurveToPoint: out += "C" + n(e.points[0]) + n(e.points[1]) + n(e.points[2])
        case .closeSubpath: out += "Z"
        @unknown default: break
        }
    }
    return out
}

func draw(_ size: CGFloat, small: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Apple's grid: the shape takes 824 of 1024, and its corners are 22.37%.
    let s = size / 1024
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let radius = 824 * 0.2237 * s
    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    // A soft shadow under the plate, the way every icon on the Dock has one.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    plateColor.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, alpha: 1).setFill()
    NSBezierPath(cgPath: markPath(in: plate, small: small)).fill()
    return image
}

func write(_ image: NSImage, to url: URL, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { return }
    // The bitmap is asked for at the pixel size, whatever the screen thinks.
    let sized = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    sized.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sized)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = sized.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = draw(CGFloat(pixels), small: points <= 32)
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(image, to: out.appendingPathComponent(name), pixels: pixels)
    }
}
print("drew: \(out.path)")

// The same icon as an Icon Composer document, when a second path is given.
// macOS 26 lets the Dock show icons Dark, Clear or Tinted, and it can only
// do that well with an icon that says what each style should be: from the
// flat image above it made a darkened plate with the black mark still on
// it, black on black (#337). Here the plate and the mark are separate, so
// Dark turns them round — a paper mark on the ink colour — and Tinted gets a
// white mark whose brightness the system tints. The light look is the same
// as above: the same paper, the same ink, the mark at the same size, and no
// glass, gloss or shadow of its own. It has the whole word at every size; an
// Icon Composer document has no size of its own for small icons.
// build.sh compiles it with actool; the images above stay the .icns.
if CommandLine.arguments.count > 2 {
    let doc = URL(fileURLWithPath: CommandLine.arguments[2])
    let assets = doc.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: doc)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

    // An Icon Composer canvas is the plate, 1024 points across; the mark
    // takes the same share of it as it does of the plate drawn above.
    let width = 1024 * markShare
    let height = width * canvas.height / canvas.width
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(Int(canvas.width)) \(Int(canvas.height))">\
    <path fill="#171717" d="\(svgData(wordmark()))"/></svg>
    """
    try svg.write(to: assets.appendingPathComponent("mark.svg"), atomically: true, encoding: .utf8)

    let white = #"{ "solid" : "srgb:1.00000,1.00000,1.00000,1.00000" }"#
    let paper = #"{ "solid" : "srgb:0.95686,0.93333,0.90196,1.00000" }"#
    let yellow = #"{ "solid" : "srgb:1.00000,0.80000,0.20000,1.00000" }"#
    let ink = #"{ "solid" : "srgb:0.09020,0.09020,0.09020,1.00000" }"#
    // A dev build keeps its yellow in Dark too: the plate yellow in light,
    // the mark yellow on ink in dark.
    let plate = dev ? yellow : paper
    let json = """
    {
      "fill" : \(plate),
      "fill-specializations" : [
        { "value" : \(plate) },
        { "appearance" : "dark", "value" : \(ink) }
      ],
      "groups" : [
        {
          "layers" : [
            {
              "name" : "mark",
              "image-name" : "mark.svg",
              "glass" : false,
              "fill-specializations" : [
                { "value" : \(ink) },
                { "appearance" : "dark", "value" : \(plate) },
                { "appearance" : "tinted", "value" : \(white) }
              ]
            }
          ],
          "shadow" : { "kind" : "none", "opacity" : 0.5 },
          "specular" : false,
          "translucency" : { "enabled" : false, "value" : 0.5 }
        }
      ],
      "supported-platforms" : { "squares" : [ "macOS" ] }
    }
    """
    try json.write(to: doc.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
    print("wrote: \(doc.path)")
}
