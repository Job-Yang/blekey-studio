import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
  at: outputDirectory,
  withIntermediateDirectories: true
)

func renderIcon(size: Int) -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: size,
      pixelsHigh: size,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    fatalError("Unable to create icon bitmap")
  }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context

  let scale = CGFloat(size) / 1024
  let background = NSBezierPath(
    roundedRect: NSRect(x: 32 * scale, y: 32 * scale, width: 960 * scale, height: 960 * scale),
    xRadius: 220 * scale,
    yRadius: 220 * scale
  )
  NSGradient(
    starting: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.08, alpha: 1),
    ending: NSColor(srgbRed: 0.21, green: 0.21, blue: 0.21, alpha: 1))?
    .draw(in: background, angle: 90)
  NSColor(white: 1, alpha: 0.12).setStroke()
  background.lineWidth = 3 * scale
  background.stroke()

  let keyWidth = 230 * scale
  let keyHeight = 340 * scale
  let gap = 34 * scale
  let originX = (CGFloat(size) - keyWidth * 3 - gap * 2) / 2
  let originY = 342 * scale

  for index in 0..<3 {
    let rect = NSRect(
      x: originX + CGFloat(index) * (keyWidth + gap),
      y: originY,
      width: keyWidth,
      height: keyHeight
    )
    let base = NSBezierPath(
      roundedRect: rect,
      xRadius: 42 * scale,
      yRadius: 42 * scale
    )
    let selected = index == 1
    NSColor(white: 0.015, alpha: 1).setFill()
    base.fill()
    let face = NSBezierPath(
      roundedRect: NSRect(
        x: rect.minX, y: rect.minY + 16 * scale,
        width: rect.width, height: rect.height - 16 * scale),
      xRadius: 42 * scale, yRadius: 42 * scale)
    let top =
      selected
      ? NSColor(srgbRed: 0.91, green: 0.22, blue: 0.14, alpha: 1)
      : NSColor(white: 0.30, alpha: 1)
    let bottom =
      selected
      ? NSColor(srgbRed: 0.68, green: 0.11, blue: 0.07, alpha: 1)
      : NSColor(white: 0.16, alpha: 1)
    NSGradient(starting: bottom, ending: top)?.draw(in: face, angle: 90)
    NSColor(white: 1, alpha: 0.12).setStroke()
    face.lineWidth = 2 * scale
    face.stroke()

    let number = NSAttributedString(
      string: "\(index + 1)",
      attributes: [
        .font: NSFont.systemFont(ofSize: 112 * scale, weight: .semibold),
        .foregroundColor: NSColor.white,
      ]
    )
    let textSize = number.size()
    number.draw(
      at: NSPoint(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2
      )
    )
  }

  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render icon")
  }
  return png
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
  let data = renderIcon(size: size)
  try data.write(to: outputDirectory.appendingPathComponent("AppIcon-\(size).png"))
}
