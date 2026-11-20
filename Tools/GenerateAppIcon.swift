import AppKit
import CoreGraphics
import Foundation

// Rebuild with: swift Tools/GenerateAppIcon.swift /tmp/FrictionBlocker.iconset
// Also writes /tmp/FrictionBlocker.icns; copy it to App/Resources/AppIcon.icns.
// The 1024px source is icon_512x512@2x.png in the generated iconset.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift Tools/GenerateAppIcon.swift <output.iconset>")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func drawIcon(size: Int) throws -> Data {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw NSError(domain: "AppIcon", code: 1)
    }
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)

    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 28,
                      color: color(0x07142C, alpha: 0.25))
    context.addPath(tile)
    context.setFillColor(color(0x113063))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [color(0x2B69BA), color(0x142F63), color(0x10203E)] as CFArray,
                              locations: [0, 0.55, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 170, y: 120),
                               end: CGPoint(x: 820, y: 930), options: [])
    context.restoreGState()
    context.addPath(tile)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.14))
    context.setLineWidth(3)
    context.strokePath()

    // Four scan corners frame a closed lock, without relying on a real barcode.
    context.setStrokeColor(color(0x66EAD3))
    context.setLineWidth(26)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let left: CGFloat = 258, right: CGFloat = 766
    let top: CGFloat = 252, bottom: CGFloat = 772, arm: CGFloat = 76
    for (x, y, dx, dy) in [(left, top, arm, arm), (right, top, -arm, arm),
                           (left, bottom, arm, -arm), (right, bottom, -arm, -arm)] {
        context.move(to: CGPoint(x: x, y: y + dy))
        context.addLine(to: CGPoint(x: x, y: y))
        context.addLine(to: CGPoint(x: x + dx, y: y))
        context.strokePath()
    }

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 10), blur: 15,
                      color: color(0x030D24, alpha: 0.3))
    let shackle = CGPath(roundedRect: CGRect(x: 408, y: 302, width: 208, height: 276),
                        cornerWidth: 104, cornerHeight: 104, transform: nil)
    context.addPath(shackle)
    context.setStrokeColor(color(0xF3F8FF))
    context.setLineWidth(45)
    context.strokePath()
    let body = CGPath(roundedRect: CGRect(x: 338, y: 448, width: 348, height: 266),
                     cornerWidth: 48, cornerHeight: 48, transform: nil)
    context.addPath(body)
    context.setFillColor(color(0xF3F8FF))
    context.fillPath()
    context.restoreGState()

    // Large bars remain readable as a scan motif at Dock and Finder sizes.
    context.setFillColor(color(0x173963))
    let bars: [(CGFloat, CGFloat)] = size <= 32
        ? [(423, 34), (490, 25), (548, 53)]
        : [(413, 17), (447, 30), (494, 14), (524, 23), (565, 14), (596, 17)]
    for (x, width) in bars {
        context.fill(CGRect(x: x, y: 538, width: width, height: 86))
    }
    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIcon", code: 2)
    }
    return png
}

// Native ICNS elements can carry PNG data, preserving every resolution and alpha.
let elementTypes = ["16-1": "icp4", "16-2": "ic11", "32-1": "icp5", "32-2": "ic12",
                    "128-1": "ic07", "128-2": "ic13", "256-1": "ic08", "256-2": "ic14",
                    "512-1": "ic09", "512-2": "ic10"]
var elements = Data()
func bigEndianLength(_ value: Int) -> Data {
    var length = UInt32(value).bigEndian
    return withUnsafeBytes(of: &length) { Data($0) }
}
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
        let png = try drawIcon(size: pointSize * scale)
        try png.write(to: directory.appendingPathComponent(name))
        elements.append(Data(elementTypes["\(pointSize)-\(scale)"]!.utf8))
        elements.append(bigEndianLength(png.count + 8))
        elements.append(png)
    }
}

var icns = Data("icns".utf8)
icns.append(bigEndianLength(elements.count + 8))
icns.append(elements)
try icns.write(to: directory.deletingPathExtension().appendingPathExtension("icns"))
