import SwiftUI
import UIKit

/// 整个 App 唯一"大胆"的元素：形状跟实物一致的容器 + 会晃动的液面。
/// - 液面高度 = 剩余量
/// - `slosh` 每变化一次，液面被晃一下（记录使用后的反馈）
/// - 有照片时，照片作为圆形标签贴在容器上
/// - 开启"减弱动态效果"或 `animated == false` 时液面静止
struct ContainerView: View {
    var kind: VesselKind
    var level: Double
    var tint: Color
    var photo: Data? = nil
    var photoKey: String? = nil
    var badge: String? = nil
    var slosh: Int = 0
    var animated: Bool = true
    var accessibilityText: String? = nil

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var sloshStart: Date = .distantPast

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let g = ContainerGeometry.make(kind, in: rect)
            ZStack(alignment: .topLeading) {
                ContainerPart(kind: kind, part: .glass).fill(.ultraThinMaterial)
                ContainerPart(kind: kind, part: .glass).stroke(Color.primary.opacity(0.14), lineWidth: 1)
                ContainerPart(kind: kind, part: .solid).fill(Theme.cap)
                ContainerPart(kind: kind, part: .vessel).fill(.ultraThinMaterial)

                liquid(region: g.vesselRect)

                // 玻璃的竖向反光：静止，不做循环扫光
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: max(2, g.vesselRect.width * 0.07), height: max(4, g.vesselRect.height * 0.45))
                    .position(x: g.vesselRect.minX + g.vesselRect.width * 0.2,
                              y: g.vesselRect.minY + g.vesselRect.height * 0.38)
                    .blendMode(.plusLighter)

                ContainerPart(kind: kind, part: .vessel).stroke(Color.primary.opacity(0.14), lineWidth: 1)
                ContainerPart(kind: kind, part: .vessel).stroke(Color.white.opacity(0.5), lineWidth: 0.5)

                if let image = photoImage, g.labelDiameter > 4 {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.labelDiameter, height: g.labelDiameter)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: max(1, g.labelDiameter * 0.05)))
                        .position(g.labelCenter)
                }

                if let badge {
                    Text(badge)
                        .font(.system(size: max(8, rect.width * 0.2), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.horizontal, max(2, rect.width * 0.06))
                        .background(Capsule().fill(.thinMaterial))
                        .position(g.badgeCenter)
                }
            }
        }
        .onChange(of: slosh) {
            guard !reduceMotion else { return }
            sloshStart = .now
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? "剩余 \(Int((level * 100).rounded()))%")
    }

    private var photoImage: UIImage? {
        guard let photo else { return nil }
        return PhotoCache.image(for: photo, key: photoKey)
    }

    private func liquid(region: CGRect) -> some View {
        let still = reduceMotion || !animated
        // 小尺寸容器（今日列表、表单图标）液面起伏更小
        let scale = max(0.35, min(1.2, region.height / 120))
        return TimelineView(.animation(minimumInterval: nil, paused: still)) { timeline in
            let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let since = timeline.date.timeIntervalSince(sloshStart)
            let energy: Double = (still || since < 0 || since > 3) ? 0 : exp(-since * 1.8)
            ZStack {
                WaveShape(level: level, phase: t * 1.4, amplitude: (1.6 + energy * 6) * scale, region: region)
                    .fill(tint.opacity(0.5))
                WaveShape(level: level, phase: t * 1.9 + 1.2, amplitude: (1.2 + energy * 4) * scale, region: region)
                    .fill(tint)
            }
        }
        .clipShape(ContainerPart(kind: kind, part: .vessel))
    }
}

extension ContainerView {
    init(product: Product, level: Double? = nil, slosh: Int = 0, animated: Bool = true) {
        self.init(kind: product.kind,
                  level: level ?? product.level,
                  tint: product.tint,
                  photo: product.photo,
                  photoKey: product.uid.uuidString,
                  badge: product.badgeText,
                  slosh: slosh,
                  animated: animated,
                  accessibilityText: product.remainingText)
    }
}

/// 解码过的照片缓存，避免每次刷新都重新解码 JPEG
enum PhotoCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    static func image(for data: Data, key: String?) -> UIImage? {
        guard let key else { return UIImage(data: data) }
        let k = "\(key)-\(data.count)" as NSString
        if let hit = cache.object(forKey: k) { return hit }
        guard let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: k)
        return img
    }
}
