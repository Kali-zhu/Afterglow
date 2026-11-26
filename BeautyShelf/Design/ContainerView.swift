import SwiftUI
import UIKit
import ImageIO

/// 整个 App 唯一"大胆"的元素：产品本身。
/// - 有抠图（cutout）时显示真实产品：液面以下保持原色，液面以上褪色、提亮、磨砂，中间一条波浪高光线
/// - 没有抠图时显示精细的容器插画（厚玻璃、弯月面、盖子细节），见 `VesselPainter`
/// - 液面跟着手机倾斜（MotionService），`slosh` 每变化一次液面被晃一下
/// - 开启"减弱动态效果"或 `animated == false` 时完全静止
struct ContainerView: View {
    var kind: VesselKind
    var level: Double
    var tint: Color
    var photo: Data?
    var photoKey: String?
    var badge: String?
    var slosh: Int
    var animated: Bool
    var accessibilityText: String?
    var cap: CapStyle
    var finish: GlassFinish
    var material: CapMaterial?
    var cutout: Data?
    /// 抠图按片计数：不做磨砂，只显示 "7/10" 小胶囊
    var countMode: Bool
    var pose: VesselPose
    /// 实物模式：整张抠图铺满（详情页大图、倒空动画）。
    /// 标签模式（false）：画出来的容器做底，把抠图 / 照片当贴纸贴在瓶身上——架子上、托盘里、分享图上都用它。
    var wholeCutout: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(kind: VesselKind,
         level: Double,
         tint: Color,
         photo: Data? = nil,
         photoKey: String? = nil,
         badge: String? = nil,
         slosh: Int = 0,
         animated: Bool = true,
         accessibilityText: String? = nil,
         cap: CapStyle = .screw,
         finish: GlassFinish = .clear,
         material: CapMaterial? = nil,
         cutout: Data? = nil,
         countMode: Bool = false,
         pose: VesselPose = .rest,
         wholeCutout: Bool = true) {
        self.kind = kind
        self.level = level
        self.tint = tint
        self.photo = photo
        self.photoKey = photoKey
        self.badge = badge
        self.slosh = slosh
        self.animated = animated
        self.accessibilityText = accessibilityText
        self.cap = cap
        self.finish = finish
        self.material = material
        self.cutout = cutout
        self.countMode = countMode
        self.pose = pose
        self.wholeCutout = wholeCutout
    }

    private var live: Bool { animated && !reduceMotion }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText ?? "剩余 \(Int((level * 100).rounded()))%")
    }

    @ViewBuilder
    private var content: some View {
        if wholeCutout, let cutout, let image = PhotoCache.cutoutImage(for: cutout, key: photoKey) {
            CutoutVessel(image: image,
                         opaque: PhotoCache.opaqueBounds(of: image, key: photoKey),
                         kind: kind, level: level, frosted: !countMode,
                         badge: badge, pose: pose, slosh: slosh, live: live)
        } else {
            IllustratedVessel(style: VesselStyle(kind: kind, cap: cap, finish: finish,
                                                 material: material ?? CapMaterial.suggested(kind: kind, cap: cap, finish: finish, category: .skincare),
                                                 tint: tint),
                              level: level, pose: pose, slosh: slosh, live: live)
                .overlay { decorations }
        }
    }

    /// 照片 / 抠图贴纸、片数徽章
    private var decorations: some View {
        GeometryReader { geo in
            let g = ContainerGeometry.make(kind, cap: cap, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                if let image = stickerImage, g.labelDiameter > 4 {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: g.labelDiameter, height: g.labelDiameter)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: max(1, g.labelDiameter * 0.05)))
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                        .position(g.labelCenter)
                }
                if let badge {
                    CountBadge(text: badge, fontSize: max(8, geo.size.width * 0.17))
                        .position(g.badgeCenter)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 贴在瓶身上的那枚标签：标签模式下优先用抠图（干净、自带透明底），没有再退回照片
    private var stickerImage: UIImage? {
        if !wholeCutout, let cutout,
           let image = PhotoCache.cutoutImage(for: cutout, key: photoKey, maxPixel: 280) {
            return image
        }
        guard let photo else { return nil }
        return PhotoCache.image(for: photo, key: photoKey)
    }
}

extension ContainerView {
    init(product: Product, level: Double? = nil, slosh: Int = 0, animated: Bool = true,
         pose: VesselPose = .rest, wholeCutout: Bool = false) {
        let count = product.measureMode == .count
        self.init(kind: product.kind,
                  level: level ?? product.level,
                  tint: product.tint,
                  photo: product.photo,
                  photoKey: product.uid.uuidString,
                  badge: count ? "\(Int(product.remainingAmount.rounded()))/\(Int(product.totalAmount.rounded()))" : nil,
                  slosh: slosh,
                  animated: animated,
                  accessibilityText: product.remainingText,
                  cap: product.capStyle,
                  finish: product.finish,
                  material: CapMaterial.suggested(kind: product.kind, cap: product.capStyle,
                                                  finish: product.finish, category: product.category),
                  cutout: product.cutout,
                  countMode: count,
                  pose: pose,
                  wholeCutout: wholeCutout)
    }

    /// 用一次时液滴 / 喷雾出现的位置（容器坐标系），给详情页的手势反馈用
    static func emitPoint(for product: Product, in size: CGSize) -> (point: CGPoint, direction: CGVector) {
        if let data = product.cutout, let image = PhotoCache.cutoutImage(for: data, key: product.uid.uuidString) {
            let layout = CutoutLayout(imageSize: image.size,
                                      opaque: PhotoCache.opaqueBounds(of: image, key: product.uid.uuidString),
                                      in: size, kind: product.kind)
            return (CGPoint(x: layout.contentRect.midX, y: layout.contentRect.minY), CGVector(dx: 0, dy: -1))
        }
        let g = ContainerGeometry.make(product.kind, cap: product.capStyle, in: CGRect(origin: .zero, size: size))
        return (g.emitPoint, g.emitDirection)
    }
}

/// 片数小胶囊
struct CountBadge: View {
    let text: String
    var fontSize: CGFloat = 11

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, fontSize * 0.45)
            .padding(.vertical, fontSize * 0.12)
            .background(Capsule().fill(.thinMaterial))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

// MARK: - 液体物理

/// 设备重力（由 MotionService 写入）。放在 Design 里，让容器不直接依赖 CoreMotion。
final class LiquidMotionSource {
    static let shared = LiquidMotionSource()
    /// 设备坐标系里的重力 x / y（竖直拿手机时约为 (0, -1)）
    var gravity = CGVector(dx: 0, dy: -1)
    var isActive = false

    /// 液面相对容器的目标倾角（弧度，正 = 右侧抬高），限制在 ±18°
    var targetTilt: Double {
        guard isActive else { return 0 }
        let gx = Double(gravity.dx), gy = Double(gravity.dy)
        let m = (gx * gx + gy * gy).squareRoot()
        guard m > 0.12 else { return 0 }
        let roll = atan2(gx, -gy)
        let limit = 18.0 * .pi / 180
        // 手机平放时 x/y 分量很小，倾角按比例减弱，避免乱跳
        return max(-limit, min(limit, roll)) * min(1, m / 0.35)
    }
}

/// 每个容器自己的一份液面状态：弹簧跟随目标倾角（有滞后、会过冲），点按时注入晃动能量
final class LiquidSim {
    private(set) var angle: Double = 0
    private var velocity: Double = 0
    private(set) var energy: Double = 0
    private var lastTime: TimeInterval?

    func kick(_ strength: Double = 1) {
        energy = min(1.6, energy + strength)
        velocity += (Bool.random() ? 1.0 : -1.0) * 1.5 * strength
    }

    /// 同一时间戳重复调用返回同一结果（多个遮罩共享一份状态）
    func step(at time: TimeInterval, target: Double, phaseSpeed: Double = 1.5) -> LiquidFrame {
        if let lastTime, abs(time - lastTime) < 0.0005 {
            return LiquidFrame(angle: angle, phase: time.truncatingRemainder(dividingBy: 3600) * phaseSpeed, energy: energy)
        }
        let dt = min(1.0 / 20, max(0, time - (lastTime ?? time)))
        lastTime = time
        let k = 70.0, c = 6.5
        var remaining = dt
        while remaining > 0 {
            let h = min(remaining, 1.0 / 120)
            let acc = -k * (angle - target) - c * velocity
            velocity += acc * h
            angle += velocity * h
            remaining -= h
        }
        angle = max(-0.4, min(0.4, angle))
        energy *= exp(-dt * 1.6)
        if energy < 0.002 { energy = 0 }
        return LiquidFrame(angle: angle, phase: time.truncatingRemainder(dividingBy: 3600) * phaseSpeed, energy: energy)
    }
}

// MARK: - 插画容器

/// Canvas 画的容器。level 与 pose 可动画；有液体时用 TimelineView 逐帧画液面。
struct IllustratedVessel: View, Animatable {
    var style: VesselStyle
    var level: Double
    var pose: VesselPose
    var slosh: Int
    var live: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var sim = LiquidSim()
    @State private var onScreen = true

    var animatableData: AnimatablePair<Double, VesselPose> {
        get { AnimatablePair(level, pose) }
        set {
            level = newValue.first
            pose = newValue.second
        }
    }

    var body: some View {
        GeometryReader { geo in
            let dark = scheme == .dark
            if live && style.hasLiquid {
                // 小尺寸（架子上）30fps 足够；详情页 60fps
                TimelineView(.animation(minimumInterval: geo.size.height < 160 ? 1.0 / 30 : nil, paused: !onScreen)) { tl in
                    let f = sim.step(at: tl.date.timeIntervalSinceReferenceDate,
                                     target: LiquidMotionSource.shared.targetTilt)
                    canvas(dark: dark, frame: f)
                }
            } else {
                canvas(dark: dark, frame: .still)
            }
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: slosh) {
            guard live else { return }
            sim.kick()
        }
    }

    private func canvas(dark: Bool, frame: LiquidFrame) -> some View {
        let painter = VesselPainter(style: style, dark: dark, level: level, pose: pose, frame: frame)
        return Canvas { ctx, size in
            painter.draw(ctx, size: size)
        }
    }
}

// MARK: - 抠图容器

/// 抠图在容器里的摆放：按不透明区域等比放大、底部对齐、水平居中
struct CutoutLayout {
    var imageRect: CGRect = .zero
    var contentRect: CGRect = .zero
    /// 剩余量对应的竖直范围（去掉盖子 / 罐盖那一段）
    var levelRegion: CGRect = .zero

    init(imageSize: CGSize, opaque: CGRect, in size: CGSize, kind: VesselKind) {
        guard imageSize.width > 0, imageSize.height > 0, size.width > 0, size.height > 0,
              opaque.width > 0, opaque.height > 0 else { return }
        let cw = imageSize.width * opaque.width, ch = imageSize.height * opaque.height
        let s = min(size.width / cw, size.height / ch)
        let drawW = imageSize.width * s, drawH = imageSize.height * s
        let content = CGRect(x: (size.width - cw * s) / 2, y: size.height - ch * s, width: cw * s, height: ch * s)
        contentRect = content
        imageRect = CGRect(x: content.minX - opaque.minX * drawW, y: content.minY - opaque.minY * drawH,
                           width: drawW, height: drawH)
        let topInset: CGFloat
        switch kind {
        case .bottle: topInset = 0.16
        case .jar: topInset = 0.3
        case .tube: topInset = 0.06
        case .stick: topInset = 0.32
        case .compact, .sheet: topInset = 0
        }
        levelRegion = CGRect(x: content.minX, y: content.minY + content.height * topInset,
                             width: content.width, height: content.height * (1 - topInset))
    }
}

/// 真实产品抠图 + 剩余量（液面以下原色，以上磨砂褪色）
struct CutoutVessel: View, Animatable {
    let image: UIImage
    let opaque: CGRect
    var kind: VesselKind
    var level: Double
    var frosted: Bool
    var badge: String?
    var pose: VesselPose
    var slosh: Int
    var live: Bool

    @State private var sim = LiquidSim()
    @State private var onScreen = true

    var animatableData: AnimatablePair<Double, VesselPose> {
        get { AnimatablePair(level, pose) }
        set {
            level = newValue.first
            pose = newValue.second
        }
    }

    var body: some View {
        GeometryReader { geo in
            let layout = CutoutLayout(imageSize: image.size, opaque: opaque, in: geo.size, kind: kind)
            let blur = max(1.2, 3 * min(1, geo.size.height / 240))
            let region = layout.levelRegion
            ZStack(alignment: .topLeading) {
                if frosted {
                    // 液面以上：去饱和、提亮、磨砂（模糊 + 35% 白）
                    art(layout)
                        .saturation(0)
                        .brightness(0.06)
                        .blur(radius: blur)
                        .overlay { Color.white.opacity(0.35) }
                        .mask { art(layout) }
                        .mask { surface(geo.size) { f in LevelMaskShape(level: level, frame: f, amplitude: amp(f, region), region: region, below: false) } }
                    // 液面以下：原色
                    art(layout)
                        .mask { surface(geo.size) { f in LevelMaskShape(level: level, frame: f, amplitude: amp(f, region), region: region, below: true) } }
                    // 分界：沿波浪走的 1pt 白色高光
                    surface(geo.size) { f in
                        ZStack {
                            LevelLineShape(level: level, frame: f, amplitude: amp(f, region), region: region)
                                .stroke(Color.white.opacity(0.45), lineWidth: 3)
                                .blur(radius: 1.5)
                            LevelLineShape(level: level, frame: f, amplitude: amp(f, region), region: region)
                                .stroke(Color.white.opacity(0.95), lineWidth: 1)
                        }
                    }
                    .mask { art(layout) }
                } else {
                    art(layout)
                }
                if let badge {
                    CountBadge(text: badge, fontSize: max(9, min(13, layout.contentRect.width * 0.16)))
                        .position(x: layout.contentRect.midX, y: layout.contentRect.maxY - layout.contentRect.height * 0.14)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(x: CGFloat(1 + 0.06 * pose.capPress), y: CGFloat(1 - 0.09 * pose.capPress), anchor: .bottom)
        }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: slosh) {
            guard live else { return }
            sim.kick()
        }
    }

    /// 波浪高度：随实物大小缩放，晃动能量越大越高
    private func amp(_ f: LiquidFrame, _ region: CGRect) -> CGFloat {
        max(0.8, region.height * 0.012) * CGFloat(1 + f.energy * 4)
    }

    private func art(_ layout: CutoutLayout) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: layout.imageRect.width, height: layout.imageRect.height)
            .position(x: layout.imageRect.midX, y: layout.imageRect.midY)
    }

    /// 需要逐帧更新的部分：live 时放进 TimelineView，否则画静止的一帧
    @ViewBuilder
    private func surface<V: View>(_ size: CGSize, @ViewBuilder _ make: @escaping (LiquidFrame) -> V) -> some View {
        if live {
            TimelineView(.animation(minimumInterval: size.height < 160 ? 1.0 / 30 : nil, paused: !onScreen)) { tl in
                make(sim.step(at: tl.date.timeIntervalSinceReferenceDate,
                              target: LiquidMotionSource.shared.targetTilt * 0.8))
            }
        } else {
            make(.still)
        }
    }
}

// MARK: - 图片缓存

/// 解码过的照片 / 抠图缓存，避免每次刷新都重新解码
enum PhotoCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 160
        return c
    }()
    private static let bounds: NSCache<NSString, NSValue> = {
        let c = NSCache<NSString, NSValue>()
        c.countLimit = 300
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

    /// 抠图（透明 PNG），按最长边 900px 降采样，保留透明通道
    static func cutoutImage(for data: Data, key: String?, maxPixel: Int = 900) -> UIImage? {
        let k = "cutout-\(key ?? "nokey")-\(data.count)-\(maxPixel)" as NSString
        if let hit = cache.object(forKey: k) { return hit }
        var result: UIImage?
        if let src = CGImageSourceCreateWithData(data as CFData, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                result = UIImage(cgImage: cg)
            }
        }
        if result == nil { result = UIImage(data: data) }
        if let result, key != nil { cache.setObject(result, forKey: k) }
        return result
    }

    /// 抠图里不透明像素的外接框（0...1 归一化）。用来让实物底边贴住架子、液面只按实物高度算。
    static func opaqueBounds(of image: UIImage, key: String?) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)
        let k = "bounds-\(key ?? "nokey")-\(Int(image.size.width))x\(Int(image.size.height))" as NSString
        if key != nil, let hit = bounds.object(forKey: k) { return hit.cgRectValue }
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return full }
        let w = 64
        let h = max(1, min(256, Int((Double(cg.height) / Double(cg.width) * 64).rounded())))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        pixels.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = .low
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<h {
                for x in 0..<w where p[(y * w + x) * 4 + 3] > 24 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        var r = full
        if maxX >= minX, maxY >= minY {
            // 位图第 0 行是图片顶部
            r = CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                       width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
        }
        if key != nil { bounds.setObject(NSValue(cgRect: r), forKey: k) }
        return r
    }
}
