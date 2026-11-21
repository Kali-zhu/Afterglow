import UIKit

/// 照片处理：居中裁成正方形并缩小，存成 JPEG（SwiftData 外部存储）
enum ImageTools {
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
}
