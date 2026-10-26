// Builds the Ambaplay app icon as an Icon Composer document (.icon) that
// actool compiles into Assets.car and <name>.icns.
//
//   icongen <ambaplay-mark.svg> <output.icon>
//
// The artwork is the brand mark from ambaplay-mark.svg (the ambaplay.dev
// favicon): a suspension bridge drawn with strokes. Its background <rect> is
// dropped, the icon fill below supplies the dark squircle. Paths at full
// opacity become the "Bridge" layer, the faded ones the "Reflection" layer.
// Only the SVG subset the mark uses is understood: one <g> with
// translate()+scale(), and <path> elements with stroke, stroke-width, opacity
// and M/L/H/V/C/S/Z commands.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("icongen: \(message)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: SVG subset

struct Stroke {
    var path: CGPath
    var width: CGFloat
    var opacity: CGFloat
}

func attribute(_ name: String, in tag: String) -> String? {
    let pattern = "\\s\(name)=\"([^\"]*)\""
    guard
        let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
        let range = Range(match.range(at: 1), in: tag)
    else { return nil }
    return String(tag[range])
}

func numbers(_ text: String) -> [CGFloat] {
    let regex = try! NSRegularExpression(pattern: "-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
    return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
        CGFloat(Double(text[Range($0.range, in: text)!])!)
    }
}

func tags(_ name: String, in svg: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: "<\(name)\\b[^>]*>")
    return regex.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)).map {
        String(svg[Range($0.range, in: svg)!])
    }
}

func parsePath(_ data: String, transform: CGAffineTransform) -> CGPath {
    let regex = try! NSRegularExpression(
        pattern: "[MmLlHhVvCcSsZz]|-?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?")
    let tokens = regex.matches(in: data, range: NSRange(data.startIndex..., in: data)).map {
        String(data[Range($0.range, in: data)!])
    }
    let path = CGMutablePath()
    var index = 0
    var command: Character = "M"
    var current = CGPoint.zero
    var start = CGPoint.zero
    var lastControl: CGPoint?

    func next() -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]) else {
            fail("bad path data: \(data)")
        }
        index += 1
        return CGFloat(value)
    }
    func point(relative: Bool) -> CGPoint {
        let x = next(), y = next()
        return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
    }

    while index < tokens.count {
        if let letter = tokens[index].first, letter.isLetter {
            command = letter
            index += 1
        }
        let relative = command.isLowercase
        switch command.uppercased().first! {
        case "M":
            current = point(relative: relative)
            start = current
            path.move(to: current, transform: transform)
            lastControl = nil
            // Extra coordinate pairs after a move are lines.
            command = relative ? "l" : "L"
        case "L":
            current = point(relative: relative)
            path.addLine(to: current, transform: transform)
            lastControl = nil
        case "H":
            let x = next()
            current.x = relative ? current.x + x : x
            path.addLine(to: current, transform: transform)
            lastControl = nil
        case "V":
            let y = next()
            current.y = relative ? current.y + y : y
            path.addLine(to: current, transform: transform)
            lastControl = nil
        case "C":
            let c1 = point(relative: relative)
            let c2 = point(relative: relative)
            let end = point(relative: relative)
            path.addCurve(to: end, control1: c1, control2: c2, transform: transform)
            lastControl = c2
            current = end
        case "S":
            let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) }
                ?? current
            let c2 = point(relative: relative)
            let end = point(relative: relative)
            path.addCurve(to: end, control1: c1, control2: c2, transform: transform)
            lastControl = c2
            current = end
        case "Z":
            path.closeSubpath()
            current = start
            lastControl = nil
        default:
            fail("unsupported path command \(command)")
        }
    }
    return path
}

func loadMark(_ url: URL) -> [Stroke] {
    guard let svg = try? String(contentsOf: url, encoding: .utf8) else {
        fail("cannot read \(url.path)")
    }
    guard
        let root = tags("svg", in: svg).first,
        let viewBox = attribute("viewBox", in: root).map(numbers), viewBox.count == 4
    else { fail("\(url.lastPathComponent) has no viewBox") }

    // SVG space (y down, viewBox units) to the canvas (y up, pixels).
    let scale = canvas / max(viewBox[2], viewBox[3])
    var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                                      tx: -viewBox[0] * scale, ty: canvas + viewBox[1] * scale)
    if let group = tags("g", in: svg).first, let spec = attribute("transform", in: group) {
        var inner = CGAffineTransform.identity
        let parts = try! NSRegularExpression(pattern: "(translate|scale)\\(([^)]*)\\)")
        for match in parts.matches(in: spec, range: NSRange(spec.startIndex..., in: spec)) {
            let kind = String(spec[Range(match.range(at: 1), in: spec)!])
            let args = numbers(String(spec[Range(match.range(at: 2), in: spec)!]))
            if kind == "translate", args.count >= 1 {
                inner = inner.translatedBy(x: args[0], y: args.count > 1 ? args[1] : 0)
            } else if kind == "scale", args.count >= 1 {
                inner = inner.scaledBy(x: args[0], y: args.count > 1 ? args[1] : args[0])
            } else {
                fail("unsupported group transform \(spec)")
            }
        }
        transform = inner.concatenating(transform)
    }

    let strokes = tags("path", in: svg).compactMap { tag -> Stroke? in
        guard let data = attribute("d", in: tag), attribute("stroke", in: tag) != nil else {
            return nil
        }
        let width = attribute("stroke-width", in: tag).flatMap { numbers($0).first } ?? 1
        let opacity = attribute("opacity", in: tag).flatMap { numbers($0).first } ?? 1
        return Stroke(path: parsePath(data, transform: transform),
                      width: width * transform.a, opacity: opacity)
    }
    guard !strokes.isEmpty else { fail("\(url.lastPathComponent) has no stroked paths") }
    return strokes
}

// MARK: Icon document

func render(_ strokes: [Stroke]) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8,
        bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for stroke in strokes {
        context.setLineWidth(stroke.width)
        context.addPath(stroke.path)
        context.strokePath()
    }
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

// #f5f5f7, the mark's colour on ambaplay.dev.
let glyphFill = "srgb:0.96078,0.96078,0.96863,1.00000"

func group(name: String, file: String, opacity: Double) -> [String: Any] {
    [
        "blur-material": NSNull(),
        "layers": [
            [
                "fill": ["solid": glyphFill],
                "image-name": file,
                "name": name,
            ]
        ],
        "opacity": opacity,
        "shadow": ["kind": "neutral", "opacity": 0.5],
        "specular": "inside",
        "translucency": ["enabled": true, "value": 0.2],
    ]
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: icongen <mark.svg> <output.icon>\n".data(using: .utf8)!)
    exit(2)
}

let strokes = loadMark(URL(fileURLWithPath: CommandLine.arguments[1]))
let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
try? FileManager.default.removeItem(at: root)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let bridge = strokes.filter { $0.opacity >= 1 }
let reflection = strokes.filter { $0.opacity < 1 }
var groups: [[String: Any]] = []
// Icon Composer lists groups front to back.
write(render(bridge), to: assets.appendingPathComponent("bridge.png"))
groups.append(group(name: "Bridge", file: "bridge.png", opacity: 1))
if let faded = reflection.first?.opacity {
    write(render(reflection), to: assets.appendingPathComponent("reflection.png"))
    groups.append(group(name: "Reflection", file: "reflection.png", opacity: Double(faded)))
}

let document: [String: Any] = [
    "fill": [
        "linear-gradient": [
            "srgb:0.11373,0.11373,0.12157,1.00000",
            "srgb:0.03137,0.03137,0.03529,1.00000",
        ]
    ],
    "groups": groups,
    "supported-platforms": ["circles": ["watchOS"], "squares": "shared"],
]
try JSONSerialization
    .data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("icon.json"))
