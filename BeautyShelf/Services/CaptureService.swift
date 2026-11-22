import UIKit
import Vision
import ImageIO
import CoreImage

/// 抠好的主体
struct ProductCutout: Equatable {
    /// 透明底 PNG，裁掉透明边，最长边 ≤ 1024
    var png: Data
    var image: UIImage
    /// 主体在原照片里的位置（归一化，左上角原点）——"浮起来"动画从这里起飞
    var rect: CGRect
    /// 像素高宽比（高 / 宽），用来猜形状
    var aspect: Double
    /// 照片里一共找到几个主体
    var instanceCount: Int
    /// 0 = 全部主体；1...n = 第 n 个主体。"重新抠图"时依次轮换
    var variant: Int

    static func == (a: ProductCutout, b: ProductCutout) -> Bool { a.png == b.png && a.variant == b.variant }
}

/// 一张照片的全部识别结果
struct CaptureAnalysis {
    /// 方向已归正（.up）的照片
    var photo: UIImage
    var cutout: ProductCutout?
    var reading: LabelReading
    var kind: VesselKind
    var category: ProductCategory?
    /// 主体平均色（已调成适合当液体颜色）
    var tintHex: String?
}

/// 拍照后的"10 秒添加"流水线：主体抠图 + 文字识别 + 形状 / 颜色猜测。全部在后台线程跑。
enum CaptureService {

    // MARK: 一步到位

    static func analyze(_ image: UIImage) async -> CaptureAnalysis {
        #if DEBUG
        runSelfCheckOnce()
        #endif
        let photo = await Task.detached(priority: .userInitiated) {
            ImageTools.normalized(image, maxSide: 2400)
        }.value

        async let cutoutTask = cutout(from: photo, variant: 0)
        async let linesTask = recognizeText(in: photo)
        let cut = await cutoutTask
        let lines = await linesTask

        let reading = LabelParser.parse(lines)
        let kind = suggestKind(hint: reading.kindHint, aspect: cut?.aspect, unit: reading.unit, capacity: reading.capacity)
        let category = reading.categoryHint.flatMap { ProductCategory(rawValue: $0.rawValue) }
        let tint = await Task.detached(priority: .utility) { () -> String? in
            if let cg = cut?.image.cgImage {
                return ImageTools.averageHex(of: cg).map(ImageTools.liquidFriendlyHex)
            }
            guard let cg = photo.cgImage else { return nil }
            return ImageTools.averageHex(of: cg, region: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4))
                .map(ImageTools.liquidFriendlyHex)
        }.value

        return CaptureAnalysis(photo: photo, cutout: cut, reading: reading, kind: kind, category: category, tintHex: tint)
    }

    // MARK: 主体抠图（iOS 17 VNGenerateForegroundInstanceMaskRequest）

    /// 找不到主体 / 模拟器 / 出错时返回 nil，调用方退回用整张照片。
    static func cutout(from photo: UIImage, variant: Int = 0) async -> ProductCutout? {
        await Task.detached(priority: .userInitiated) {
            CaptureService.makeCutout(from: photo, variant: variant)
        }.value
    }

    private static func makeCutout(from photo: UIImage, variant: Int) -> ProductCutout? {
        // 抠图不需要超大分辨率，1600 足够且更快
        let working = ImageTools.normalized(photo, maxSide: 1600)
        guard let cg = working.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let all = observation.allInstances
        guard !all.isEmpty else { return nil }

        let count = all.count
        let v = count > 1 ? ((variant % (count + 1)) + (count + 1)) % (count + 1) : 0
        let instances: IndexSet = v == 0 ? all : IndexSet(integer: Array(all)[v - 1])

        // 不裁到主体范围（croppedToInstancesExtent: false），这样能算出主体在原图里的位置，
        // 再自己按 alpha 裁掉透明边——结果与 croppedToInstancesExtent: true 相同，但多了位置信息。
        let buffer: CVPixelBuffer
        do {
            buffer = try observation.generateMaskedImage(ofInstances: instances, from: handler, croppedToInstancesExtent: false)
        } catch {
            return nil
        }
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let full = ImageTools.ciContext.createCGImage(ci, from: ci.extent, format: .RGBA8,
                                                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
              let bounds = ImageTools.alphaBounds(of: full) else { return nil }

        let W = CGFloat(full.width), H = CGFloat(full.height)
        // 主体太小（< 2% 面积）多半是误识别
        guard bounds.width * bounds.height > W * H * 0.02 else { return nil }

        // 留 2% 边，阴影 / 抗锯齿边缘不被切掉
        let pad = max(bounds.width, bounds.height) * 0.02
        let padded = bounds.insetBy(dx: -pad, dy: -pad)
            .intersection(CGRect(x: 0, y: 0, width: W, height: H)).integral
        guard let cropped = full.cropping(to: padded),
              let png = ImageTools.pngData(cropped, maxSide: 1024),
              let image = UIImage(data: png) else { return nil }

        return ProductCutout(png: png,
                             image: image,
                             rect: CGRect(x: padded.minX / W, y: padded.minY / H, width: padded.width / W, height: padded.height / H),
                             aspect: Double(bounds.height / max(1, bounds.width)),
                             instanceCount: count,
                             variant: v)
    }

    // MARK: 文字识别

    static func recognizeText(in photo: UIImage) async -> [LabelLine] {
        await Task.detached(priority: .userInitiated) { () -> [LabelLine] in
            guard let cg = photo.cgImage else { return [] }
            var lines = CaptureService.readLines(cg, orientation: .up, weight: 1)
            // 管身上的 EXP 常常是竖着印的：正着读不到日期时，再转 90° 读一遍
            if LabelParser.parse(lines).expiry == nil {
                lines += CaptureService.readLines(cg, orientation: .right, weight: 0.5)
            }
            return lines
        }.value
    }

    private static func readLines(_ cg: CGImage, orientation: CGImagePropertyOrientation, weight: Double) -> [LabelLine] {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        let observations = request.results ?? []
        // 按从上到下排（Vision 的 y 原点在下方），保持"关键字在上一行、日期在下一行"的顺序
        return observations
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { o -> LabelLine? in
                guard let c = o.topCandidates(1).first else { return nil }
                return LabelLine(text: c.string, height: Double(o.boundingBox.height) * weight, confidence: Double(c.confidence))
            }
    }

    // MARK: 猜形状 / 默认盖子与材质

    /// 文字里的关键词（面膜、口红、面霜……）优先；否则看抠图的高宽比和容量单位。
    static func suggestKind(hint: VesselKindHint?, aspect: Double?, unit: String?, capacity: Double?) -> VesselKind {
        if unit == "片" { return .sheet }
        if let hint, let k = VesselKind(rawValue: hint.rawValue) { return k }
        guard let a = aspect else { return unit == "g" ? .jar : .bottle }
        switch a {
        case 2.8...:
            if unit == "g", let c = capacity, c <= 6 { return .stick }
            return .tube
        case 1.3..<2.8:
            return unit == "g" ? .tube : .bottle
        case 0.8..<1.3:
            return .jar
        default:
            if unit == nil || (unit == "g" && (capacity ?? 0) <= 20) { return .compact }
            return .jar
        }
    }

    /// 精华瓶（护肤）→ 滴管；粉底液 → 按压泵；香氛 → 喷头；面膜 → 无；其余旋盖
    static func defaultCap(kind: VesselKind, category: ProductCategory, name: String) -> CapStyle {
        let n = name.uppercased()
        if category == .fragrance { return .spray }
        if n.contains("粉底液") || n.contains("FOUNDATION") { return .pump }
        if kind == .bottle, category == .skincare,
           ["精华", "SERUM", "AMPOULE", "安瓶", "原液"].contains(where: { n.contains($0) }),
           !n.contains("精华水") {
            return .dropper
        }
        if kind == .sheet { return .none }
        return .screw
    }

    static func defaultFinish(kind: VesselKind, category: ProductCategory) -> GlassFinish {
        switch kind {
        case .bottle: return .clear
        case .jar: return .frosted
        case .tube, .sheet, .stick, .compact: return .opaque
        }
    }

    #if DEBUG
    private static var didSelfCheck = false
    private static func runSelfCheckOnce() {
        guard !didSelfCheck else { return }
        didSelfCheck = true
        let failures = LabelParser.runExamples()
        if !failures.isEmpty {
            print("⚠️ LabelParser 样例未通过：\n" + failures.joined(separator: "\n"))
        }
    }
    #endif
}
