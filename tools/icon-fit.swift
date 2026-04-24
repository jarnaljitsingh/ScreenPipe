import AppKit
import CoreGraphics

// Crop PNG to its opaque bounding box, pad with ~8% margin, resize to 1024x1024.
// Usage: swift icon-fit.swift input.png output.png

guard CommandLine.arguments.count == 3 else {
    print("usage: icon-fit input.png output.png")
    exit(1)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])

guard let src = NSImage(contentsOf: input),
      let tiff = src.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else {
    print("failed to load \(input.path)"); exit(1)
}

let w = Int(rep.pixelsWide)
let h = Int(rep.pixelsHigh)
guard let bmp = rep.bitmapData else { print("no bitmap data"); exit(1) }
let bpp = rep.bitsPerPixel / 8
let bpr = rep.bytesPerRow
let alphaIdx: Int = {
    switch rep.bitmapFormat {
    case .alphaFirst, .alphaNonpremultiplied:
        return rep.bitmapFormat.contains(.sixteenBitBigEndian) ? 0 : 0
    default:
        return bpp - 1
    }
}()

var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h {
    for x in 0..<w {
        let p = bmp + y * bpr + x * bpp
        let a = p[alphaIdx]
        if a > 8 {
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
    }
}
guard maxX > 0, maxY > 0 else { print("empty image?"); exit(1) }

let cropW = maxX - minX + 1
let cropH = maxY - minY + 1
let side = max(cropW, cropH)
let margin = Int(Double(side) * 0.06)
let canvas = side + margin * 2

print("bbox=\(minX),\(minY) - \(maxX),\(maxY)  cropped=\(cropW)x\(cropH)  canvas=\(canvas)")

// Draw onto a canvas of size `canvas` x `canvas`, centered, then resize to 1024.
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: canvas, height: canvas,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { print("ctx fail"); exit(1) }
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

guard let srcCG = rep.cgImage else { print("no cg"); exit(1) }
let cropRect = CGRect(x: minX, y: h - maxY - 1, width: cropW, height: cropH)
guard let cropped = srcCG.cropping(to: cropRect) else { print("crop fail"); exit(1) }

let dstX = (canvas - cropW) / 2
let dstY = (canvas - cropH) / 2
ctx.draw(cropped, in: CGRect(x: dstX, y: dstY, width: cropW, height: cropH))

guard let padded = ctx.makeImage() else { print("padded fail"); exit(1) }

// Resize to 1024x1024.
guard let resizeCtx = CGContext(
    data: nil,
    width: 1024, height: 1024,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { print("resize ctx fail"); exit(1) }
resizeCtx.interpolationQuality = .high
resizeCtx.draw(padded, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

guard let final = resizeCtx.makeImage() else { print("final fail"); exit(1) }
let dest = NSBitmapImageRep(cgImage: final)
guard let pngData = dest.representation(using: .png, properties: [:]) else {
    print("png rep fail"); exit(1)
}
try pngData.write(to: output)
print("wrote \(output.path)")
