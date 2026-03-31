import AppKit

/// Generates the Lidmeup app icon as an .icns file
func generateIcon(outputPath: String) {
    let sizes: [(CGFloat, String)] = [
        (16, "icon_16x16"),
        (32, "icon_16x16@2x"),
        (32, "icon_32x32"),
        (64, "icon_32x32@2x"),
        (128, "icon_128x128"),
        (256, "icon_128x128@2x"),
        (256, "icon_256x256"),
        (512, "icon_256x256@2x"),
        (512, "icon_512x512"),
        (1024, "icon_512x512@2x"),
    ]

    let iconsetPath = "/tmp/Lidmeup.iconset"
    let fm = FileManager.default
    try? fm.removeItem(atPath: iconsetPath)
    try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    for (size, name) in sizes {
        let image = drawIcon(size: size)
        let url = URL(fileURLWithPath: "\(iconsetPath)/\(name).png")
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { continue }
        try! png.write(to: url)
    }

    // Convert iconset to icns
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconsetPath, "-o", outputPath]
    try! task.run()
    task.waitUntilExit()

    try? fm.removeItem(atPath: iconsetPath)
    print("Icon generated: \(outputPath)")
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = size
    let pad = s * 0.1

    // Background rounded rect
    let bgRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0))
    ctx.fillPath()

    // Draw gauge arc (background)
    let cx = s / 2
    let cy = s * 0.48
    let radius = s * 0.28
    let startAngle = CGFloat.pi * 0.8
    let endAngle = CGFloat.pi * 0.2

    ctx.setStrokeColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0))
    ctx.setLineWidth(s * 0.06)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: -startAngle, endAngle: -endAngle, clockwise: true)
    ctx.strokePath()

    // Draw gauge arc (colored - ~75% filled)
    let segments: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        // r, g, b, start fraction, end fraction
        (0.2, 0.85, 0.3, 0.0, 0.25),   // green
        (0.95, 0.85, 0.15, 0.25, 0.5),  // yellow
        (1.0, 0.55, 0.1, 0.5, 0.75),    // orange
    ]

    let totalArc = startAngle - endAngle + CGFloat.pi * 2
    let arcRange = totalArc > CGFloat.pi * 2 ? totalArc - CGFloat.pi * 2 : totalArc
    let actualArcRange = CGFloat.pi * 1.6 // 0.8π to 0.2π going clockwise in flipped coords

    for (r, g, b, startFrac, endFrac) in segments {
        let segStart = -startAngle + actualArcRange * startFrac
        let segEnd = -startAngle + actualArcRange * endFrac

        ctx.setStrokeColor(CGColor(red: r, green: g, blue: b, alpha: 1.0))
        ctx.setLineWidth(s * 0.06)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: radius, startAngle: segStart, endAngle: segEnd, clockwise: false)
        ctx.strokePath()
    }

    // Draw laptop icon in center
    let laptopW = s * 0.2
    let laptopH = s * 0.13
    let laptopX = cx - laptopW / 2
    let laptopY = cy - laptopH / 2 - s * 0.02

    // Screen
    let screenRect = CGRect(x: laptopX, y: laptopY + laptopH * 0.3, width: laptopW, height: laptopH * 0.7)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: s * 0.015, cornerHeight: s * 0.015, transform: nil)
    ctx.addPath(screenPath)
    ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1.0))
    ctx.fillPath()

    // Base
    let baseRect = CGRect(x: laptopX - s * 0.02, y: laptopY, width: laptopW + s * 0.04, height: laptopH * 0.25)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: s * 0.01, cornerHeight: s * 0.01, transform: nil)
    ctx.addPath(basePath)
    ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1.0))
    ctx.fillPath()

    // Degree text below gauge
    let fontSize = s * 0.16
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor(red: 0.2, green: 0.85, blue: 0.3, alpha: 1.0),
    ]
    let text = "92%"
    let textSize = text.size(withAttributes: attrs)
    let textPoint = NSPoint(x: cx - textSize.width / 2, y: cy - radius - fontSize * 1.4)
    text.draw(at: textPoint, withAttributes: attrs)

    image.unlockFocus()
    return image
}

// Main
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
generateIcon(outputPath: outputPath)
