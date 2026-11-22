import UIKit
import CoreImage

/// 照片处理：方向归正、缩放、裁切、透明边裁掉、取主色。
enum ImageTools {

    // MARK: 方形 JPEG（旧接口，保留给其他地方用）

    static func squareJPEG(from data: Data, side: CGFloat = 640) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return squareJPEG(image, side: side)
    }

    static func squareJPEG(_ image: UIImage, side: CGFloat = 640) -> Data? {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let shortest = min(w, h)
        guard shortest > 0 else { return nil }
        let target = min(side, shortest)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format)
        let output = renderer.image { _ in
            let factor = target / shortest
            let drawW = w * factor, drawH = h * factor
            // draw(in:) 会按照片方向（orientation）正确绘制
            image.draw(in: CGRect(x: (target - drawW) / 2, y: (target - drawH) / 2, width: drawW, height: drawH))
        }
        return output.jpegData(compressionQuality: 0.8)
    }

    // MARK: 归正 + 缩放

    /// 把照片画成 `.up` 方向、scale = 1、最长边不超过 maxSide 的新图（Vision 只认像素方向）
    static func normalized(_ image: UIImage, maxSide: CGFloat = 2400) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        guard w > 0, h > 0 else { return image }
        let factor = min(1, maxSide / max(w, h))
        if image.imageOrientation == .up, factor >= 1, image.scale == 1, image.cgImage != nil { return image }
        let size = CGSize(width: (w * factor).rounded(), height: (h * factor).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 存进 SwiftData 的照片：保持原比例，最长边 1600
    static func photoJPEG(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.82) -> Data? {
        normalized(image, maxSide: maxSide).jpegData(compressionQuality: quality)
    }

    /// 按归一化矩形（左上角为原点，0...1）裁切。图片须已是 `.up` 方向。
    static func crop(_ image: UIImage, normalizedRect r: CGRect) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let rr = r.intersection(unit)
        guard !rr.isNull, rr.width > 0.05, rr.height > 0.05 else { return image }
        let px = CGRect(x: rr.minX * W, y: rr.minY * H, width: rr.width * W, height: rr.height * H).integral
        guard let out = cg.cropping(to: px) else { return image }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    // MARK: 透明图

    /// 非透明像素的外接矩形（像素坐标，左上角为原点）。全透明返回 nil。
    static func alphaBounds(of cg: CGImage, threshold: UInt8 = 12) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }

        var minX = w, minY = h, maxX = -1, maxY = -1
        buffer.withUnsafeBufferPointer { p in
            for y in 0..<h {
                let row = y * bytesPerRow
                var x = 0
                while x < w {
                    if p[row + x * 4 + 3] > threshold {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                    x += 1
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // 位图内存第一行就是图像顶部，所以这里已经是左上角原点
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// 缩到最长边 maxSide 的透明 PNG
    static func pngData(_ cg: CGImage, maxSide: CGFloat = 1024) -> Data? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w > 0, h > 0 else { return nil }
        let factor = min(1, maxSide / max(w, h))
        let size = CGSize(width: max(1, (w * factor).rounded()), height: max(1, (h * factor).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }

    // MARK: 取色

    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// 平均色（透明像素不参与：CIAreaAverage 得到预乘颜色，再除以平均 alpha）。
    /// `region` 为归一化矩形（左上角原点），不传 = 整张图。
    static func averageHex(of cg: CGImage, region: CGRect? = nil) -> String? {
        let input = CIImage(cgImage: cg)
        var extent = input.extent
        if let r = region {
            // CIImage 原点在左下角
            extent = CGRect(x: extent.minX + r.minX * extent.width,
                            y: extent.minY + (1 - r.maxY) * extent.height,
                            width: r.width * extent.width,
                            height: r.height * extent.height)
        }
        guard let filter = CIFilter(name: "CIAreaAverage") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        // 先渲染成 1×1 CGImage，再画进"预乘 alpha"的位图，保证读到的一定是预乘值
        let one = CGRect(origin: output.extent.origin, size: CGSize(width: 1, height: 1))
        guard let avg = ciContext.createCGImage(output, from: one, format: .RGBA8,
                                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = px.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(avg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let a = Double(px[3]) / 255
        guard a > 0.02 else { return nil }
        let r = min(1, Double(px[0]) / 255 / a)
        let g = min(1, Double(px[1]) / 255 / a)
        let b = min(1, Double(px[2]) / 255 / a)
        return hex(r: r, g: g, b: b)
    }

    static func hex(r: Double, g: Double, b: Double) -> String {
        func c(_ v: Double) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "%02lX%02lX%02lX", c(r), c(g), c(b))
    }

    /// 液体颜色不要太灰太暗：把取到的颜色往"能看出是液体"的方向推一点
    static func liquidFriendlyHex(_ hex: String) -> String {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        let color = UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                            green: CGFloat((v >> 8) & 0xFF) / 255,
                            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &br, alpha: &a) else { return hex }
        let s2 = min(0.75, max(s, s > 0.06 ? 0.22 : s))
        let b2 = min(0.96, max(br, 0.42))
        let out = UIColor(hue: h, saturation: s2, brightness: b2, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        out.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Self.hex(r: Double(r), g: Double(g), b: Double(b))
    }
}
