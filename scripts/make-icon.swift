// Uygulama simgesini üretir: swift scripts/make-icon.swift
import AppKit

let size = 1024.0
let output = "Economix/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Zemin: zümrüt yeşili dikey gradyan
let colors = [NSColor(srgbRed: 0.10, green: 0.70, blue: 0.50, alpha: 1).cgColor,
              NSColor(srgbRed: 0.03, green: 0.40, blue: 0.31, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Halka grafik: üç dilim, aralarında boşluk
let center = CGPoint(x: size / 2, y: size / 2)
let radius = 300.0
let lineWidth = 120.0
let slices: [(start: Double, end: Double, alpha: Double)] = [(90, 300, 1.0), (306, 390, 0.75), (396, 444, 0.5)]
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.butt)
for slice in slices {
    ctx.setStrokeColor(NSColor(white: 1, alpha: slice.alpha).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: -slice.start * .pi / 180,
               endAngle: -slice.end * .pi / 180, clockwise: true)
    ctx.strokePath()
}

// Ortada ₺
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 300, weight: .bold),
    .foregroundColor: NSColor.white,
]
let lira = NSAttributedString(string: "₺", attributes: attributes)
let textSize = lira.size()
lira.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2 + 6))

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("Yazıldı: \(output)")
