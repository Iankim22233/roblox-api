import AppKit

let canvasSize = 1024
let keySize: CGFloat = 340
let gap: CGFloat = 40
let cornerRadius: CGFloat = keySize * 0.18
let borderWidth: CGFloat = keySize * 0.045

let totalWidth = keySize * 2 + gap
let totalHeight = keySize
let originX = (CGFloat(canvasSize) - totalWidth) / 2
let originY = (CGFloat(canvasSize) - totalHeight) / 2

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
  data: nil, width: canvasSize, height: canvasSize,
  bitsPerComponent: 8, bytesPerRow: 0,
  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("could not create CGContext") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

func drawKey(x: CGFloat, fill: NSColor, letter: String) {
  let rect = CGRect(x: x, y: originY, width: keySize, height: keySize)
  let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

  fill.setFill()
  path.fill()

  NSColor.black.setStroke()
  path.lineWidth = borderWidth
  path.stroke()

  let paragraph = NSMutableParagraphStyle()
  paragraph.alignment = .center
  let font = NSFont.systemFont(ofSize: keySize * 0.5, weight: .bold)
  let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.black,
    .paragraphStyle: paragraph,
  ]
  let string = NSAttributedString(string: letter, attributes: attrs)
  let textSize = string.size()
  let textRect = CGRect(
    x: rect.midX - textSize.width / 2,
    y: rect.midY - textSize.height / 2,
    width: textSize.width,
    height: textSize.height
  )
  string.draw(in: textRect)
}

// Yellow matches the app's own key-press highlight color (--accent in style.css).
drawKey(x: originX, fill: .white, letter: "K")
drawKey(x: originX + keySize + gap, fill: NSColor(red: 0.780, green: 0.788, blue: 0.204, alpha: 1.0), letter: "O")

NSGraphicsContext.restoreGraphicsState()

guard let cgImage = ctx.makeImage() else { fatalError("could not render image") }
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_master.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
