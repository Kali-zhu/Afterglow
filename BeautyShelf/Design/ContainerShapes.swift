import SwiftUI

// MARK: - 容器几何（v1.0）

/// 容器家族的几何。所有形状都在同一个矩形里按比例绘制（架子上约 64×104，详情页 150×244）。
/// v1.0 起细节由 `VesselPainter` 在 Canvas 里画；这里只给出各部件的位置：
/// - vessel：外轮廓（玻璃外壁 / 管身 / 袋身……）
/// - cavity：内腔（外轮廓向内收一层玻璃厚度），液体只在这里面
/// - liquidRect：液面可以到达的区域（不含厚玻璃底）
/// - glass / solid：兼容旧接口的附属部分与实心部件
struct ContainerGeometry {
    var kind: VesselKind = .bottle
    var cap: CapStyle = .screw

    var glass = Path()
    var solid = Path()
    var vessel = Path()
    var cavity = Path()

    var vesselRect: CGRect = .zero
    var liquidRect: CGRect = .zero
    var wall: CGFloat = 0
    var corner: CGFloat = 0
    var baseRect: CGRect = .zero
    var neckRect: CGRect = .zero
    var capRect: CGRect = .zero
    var parts = CapParts()

    var labelCenter: CGPoint = .zero
    var labelDiameter: CGFloat = 0
    var badgeCenter: CGPoint = .zero
    /// 用一次时液滴 / 喷雾 / 粉雾出现的位置
    var emitPoint: CGPoint = .zero
    /// 液滴离开时的方向（单位向量，y 向下为正）
    var emitDirection: CGVector = CGVector(dx: 0, dy: 1)

    /// 瓶盖的细分部件（不同 capStyle 用到不同的几个）
    struct CapParts {
        var bulb: CGRect = .zero      // 滴管胶头
        var collar: CGRect = .zero    // 滴管 / 泵头 / 喷头的金属环
        var stem: CGRect = .zero      // 泵杆
        var head: CGRect = .zero      // 泵头 / 喷头按压部分
        var nozzle: CGRect = .zero    // 泵头出口
        var lip: CGRect = .zero       // 无盖瓶口
        // 管
        var crimp: CGRect = .zero
        var tubeTopWidth: CGFloat = 0
        var tubeBottomWidth: CGFloat = 0
        // 口红
        var sleeve: CGRect = .zero
        var ring: CGRect = .zero
        var bulletWidth: CGFloat = 0
        var bulletBottom: CGFloat = 0
        var bulletMaxLength: CGFloat = 0
        // 粉盒
        var topFace: CGRect = .zero
        var pan: CGRect = .zero
        var hingeY: CGFloat = 0
        var lidRadius: CGFloat = 0
    }

    static func make(_ kind: VesselKind, cap: CapStyle = .screw, in r: CGRect) -> ContainerGeometry {
        var g = ContainerGeometry()
        g.kind = kind
        g.cap = cap
        let w = r.width, h = r.height
        guard w > 1, h > 1 else { return g }

        switch kind {
        case .bottle: makeBottle(&g, cap: cap, r)
        case .jar: makeJar(&g, r)
        case .tube: makeTube(&g, r)
        case .sheet: makeSheet(&g, r)
        case .stick: makeStick(&g, r)
        case .compact: makeCompact(&g, r)
        }
        if g.badgeCenter == .zero {
            g.badgeCenter = CGPoint(x: g.vesselRect.midX, y: g.vesselRect.maxY - g.vesselRect.height * 0.2)
        }
        return g
    }

    // MARK: 瓶

    private static func makeBottle(_ g: inout ContainerGeometry, cap: CapStyle, _ r: CGRect) {
        let w = r.width, h = r.height, mx = r.midX
        let topFrac: CGFloat
        switch cap {
        case .screw: topFrac = 0.17
        case .dropper: topFrac = 0.27
        case .pump: topFrac = 0.24
        case .spray: topFrac = 0.21
        case .flip: topFrac = 0.16
        case .none: topFrac = 0.06
        }
        let neckH = h * (cap == .none ? 0.06 : 0.035)
        let bodyTop = r.minY + h * topFrac + neckH
        let body = CGRect(x: r.minX + w * 0.02, y: bodyTop, width: w * 0.96, height: r.maxY - bodyTop)
        let corner = min(w * 0.2, body.height * 0.22)
        let wall = max(1.0, w * 0.045)
        let baseT = max(2.0, body.height * 0.075)

        g.vesselRect = body
        g.corner = corner
        g.wall = wall
        g.vessel = Path(roundedRect: body, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        let inner = body.insetBy(dx: wall, dy: wall)
        let cavityRect = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: (body.maxY - baseT) - inner.minY)
        g.cavity = Path(roundedRect: cavityRect,
                        cornerSize: CGSize(width: max(1, corner - wall), height: max(1, corner - wall)),
                        style: .continuous)
        g.liquidRect = cavityRect
        g.baseRect = CGRect(x: body.minX, y: body.maxY - baseT - wall, width: body.width, height: baseT + wall)

        let capBottom = bodyTop - neckH
        g.neckRect = CGRect(x: mx - w * 0.16, y: capBottom - 0.5, width: w * 0.32, height: neckH + corner * 0.35)
        g.glass.addRect(g.neckRect)

        var p = CapParts()
        switch cap {
        case .screw:
            g.capRect = CGRect(x: mx - w * 0.23, y: r.minY, width: w * 0.46, height: capBottom - r.minY)
            g.emitPoint = CGPoint(x: mx, y: r.minY)
            g.emitDirection = CGVector(dx: 0, dy: -1)
        case .flip:
            g.capRect = CGRect(x: mx - w * 0.25, y: r.minY, width: w * 0.5, height: capBottom - r.minY)
            g.emitPoint = CGPoint(x: mx, y: r.minY)
            g.emitDirection = CGVector(dx: 0, dy: -1)
        case .dropper:
            p.collar = CGRect(x: mx - w * 0.22, y: capBottom - h * 0.09, width: w * 0.44, height: h * 0.09)
            p.bulb = CGRect(x: mx - w * 0.12, y: r.minY, width: w * 0.24, height: p.collar.minY - r.minY + h * 0.012)
            g.capRect = p.collar.union(p.bulb)
            // 挤胶头：一滴从滴管口落进瓶里
            g.emitPoint = CGPoint(x: mx, y: body.minY + wall * 2)
            g.emitDirection = CGVector(dx: 0, dy: 1)
        case .pump:
            p.collar = CGRect(x: mx - w * 0.22, y: capBottom - h * 0.075, width: w * 0.44, height: h * 0.075)
            p.head = CGRect(x: mx - w * 0.17, y: r.minY + h * 0.015, width: w * 0.34, height: h * 0.075)
            p.stem = CGRect(x: mx - w * 0.045, y: p.head.maxY - 1, width: w * 0.09, height: p.collar.minY - p.head.maxY + 2)
            p.nozzle = CGRect(x: p.head.minX - w * 0.2, y: p.head.minY + p.head.height * 0.18,
                              width: w * 0.22, height: p.head.height * 0.4)
            g.capRect = p.collar.union(p.head).union(p.nozzle)
            g.emitPoint = CGPoint(x: p.nozzle.minX, y: p.nozzle.midY)
            g.emitDirection = CGVector(dx: -0.6, dy: 0.8)
        case .spray:
            p.collar = CGRect(x: mx - w * 0.25, y: capBottom - h * 0.08, width: w * 0.5, height: h * 0.08)
            p.head = CGRect(x: mx - w * 0.14, y: r.minY + h * 0.02, width: w * 0.28, height: p.collar.minY - r.minY - h * 0.02 + 1)
            g.capRect = p.collar.union(p.head)
            g.emitPoint = CGPoint(x: p.head.minX, y: p.head.minY + p.head.height * 0.35)
            g.emitDirection = CGVector(dx: -1, dy: -0.1)
        case .none:
            p.lip = CGRect(x: mx - w * 0.19, y: capBottom - h * 0.028, width: w * 0.38, height: h * 0.028)
            g.neckRect = CGRect(x: mx - w * 0.16, y: p.lip.maxY - 0.5, width: w * 0.32, height: bodyTop - p.lip.maxY + corner * 0.35)
            g.capRect = p.lip
            g.emitPoint = CGPoint(x: mx, y: p.lip.minY)
            g.emitDirection = CGVector(dx: 0, dy: -1)
        }
        g.parts = p
        g.solid.addRect(g.capRect)
        g.labelCenter = CGPoint(x: body.midX, y: body.midY + body.height * 0.06)
        g.labelDiameter = w * 0.56
    }

    // MARK: 罐

    private static func makeJar(_ g: inout ContainerGeometry, _ r: CGRect) {
        let w = r.width, h = r.height
        let lidH = h * 0.13, bodyH = h * 0.46
        let body = CGRect(x: r.minX + w * 0.03, y: r.maxY - bodyH, width: w * 0.94, height: bodyH)
        let lid = CGRect(x: r.minX, y: body.minY - lidH + h * 0.012, width: w, height: lidH)
        let corner = w * 0.12
        let wall = max(1.2, w * 0.055)
        let baseT = max(2.5, bodyH * 0.15)
        g.vesselRect = body
        g.corner = corner
        g.wall = wall
        g.capRect = lid
        g.vessel = Path(roundedRect: body, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        let cavityRect = CGRect(x: body.minX + wall, y: body.minY + wall * 1.6,
                                width: body.width - wall * 2, height: body.maxY - baseT - body.minY - wall * 1.6)
        g.cavity = Path(roundedRect: cavityRect, cornerSize: CGSize(width: max(1, corner - wall), height: max(1, corner - wall)),
                        style: .continuous)
        g.liquidRect = cavityRect
        g.baseRect = CGRect(x: body.minX, y: body.maxY - baseT - wall, width: body.width, height: baseT + wall)
        g.solid.addRoundedRect(in: lid, cornerSize: CGSize(width: w * 0.07, height: w * 0.07), style: .continuous)
        g.labelCenter = CGPoint(x: body.midX, y: body.midY + bodyH * 0.04)
        g.labelDiameter = min(bodyH * 0.66, w * 0.52)
        g.emitPoint = CGPoint(x: lid.midX, y: lid.minY)
        g.emitDirection = CGVector(dx: 0, dy: -1)
    }

    // MARK: 管（倒立：盖子在下，压封的尾部在上）

    private static func makeTube(_ g: inout ContainerGeometry, _ r: CGRect) {
        let w = r.width, h = r.height, mx = r.midX
        let capH = h * 0.13, capW = w * 0.46
        let cap = CGRect(x: mx - capW / 2, y: r.maxY - capH, width: capW, height: capH)
        let topW = w * 0.96, botW = capW * 1.08
        let crimp = CGRect(x: mx - topW / 2, y: r.minY + h * 0.02, width: topW, height: h * 0.07)
        g.capRect = cap
        g.parts.crimp = crimp
        g.parts.tubeTopWidth = topW
        g.parts.tubeBottomWidth = botW
        g.vessel = tubeBody(top: crimp.maxY, bottom: cap.minY + 1, midX: mx, topW: topW, botW: botW, squeeze: 0)
        g.cavity = g.vessel
        g.vesselRect = CGRect(x: mx - topW / 2, y: crimp.maxY, width: topW, height: cap.minY - crimp.maxY)
        g.liquidRect = g.vesselRect
        g.solid.addRect(cap)
        g.glass.addRect(crimp)
        g.labelCenter = CGPoint(x: mx, y: crimp.maxY + g.vesselRect.height * 0.42)
        g.labelDiameter = w * 0.5
        g.emitPoint = CGPoint(x: mx, y: r.maxY)
        g.emitDirection = CGVector(dx: 0, dy: 1)
    }

    /// 管身：上宽下窄，squeeze 0...1 时腰部被捏细
    static func tubeBody(top: CGFloat, bottom: CGFloat, midX: CGFloat, topW: CGFloat, botW: CGFloat, squeeze: CGFloat) -> Path {
        let H = bottom - top
        let pinch = topW * 0.22 * max(0, min(1, squeeze))
        var p = Path()
        p.move(to: CGPoint(x: midX - topW / 2, y: top))
        p.addLine(to: CGPoint(x: midX + topW / 2, y: top))
        p.addCurve(to: CGPoint(x: midX + botW / 2, y: bottom),
                   control1: CGPoint(x: midX + topW / 2 - pinch, y: top + H * 0.5),
                   control2: CGPoint(x: midX + topW / 2 - pinch * 0.3, y: bottom - H * 0.26))
        p.addLine(to: CGPoint(x: midX - botW / 2, y: bottom))
        p.addCurve(to: CGPoint(x: midX - topW / 2, y: top),
                   control1: CGPoint(x: midX - topW / 2 + pinch * 0.3, y: bottom - H * 0.26),
                   control2: CGPoint(x: midX - topW / 2 + pinch, y: top + H * 0.5))
        p.closeSubpath()
        return p
    }

    // MARK: 面膜袋

    private static func makeSheet(_ g: inout ContainerGeometry, _ r: CGRect) {
        let w = r.width, h = r.height
        let front = CGRect(x: r.minX, y: r.maxY - h * 0.66, width: w * 0.84, height: h * 0.66)
        let corner = w * 0.06
        g.vesselRect = front
        g.liquidRect = front
        g.corner = corner
        g.vessel = Path(roundedRect: front, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        g.cavity = g.vessel
        g.glass.addRoundedRect(in: front.offsetBy(dx: w * 0.16, dy: -h * 0.1), cornerSize: CGSize(width: corner, height: corner))
        g.glass.addRoundedRect(in: front.offsetBy(dx: w * 0.08, dy: -h * 0.05), cornerSize: CGSize(width: corner, height: corner))
        g.labelCenter = CGPoint(x: front.midX, y: front.minY + front.height * 0.44)
        g.labelDiameter = front.width * 0.52
        g.badgeCenter = CGPoint(x: front.midX, y: front.maxY - front.height * 0.17)
        g.emitPoint = CGPoint(x: front.maxX, y: front.minY)
        g.emitDirection = CGVector(dx: 0.7, dy: -0.7)
    }

    // MARK: 口红

    private static func makeStick(_ g: inout ContainerGeometry, _ r: CGRect) {
        let w = r.width, h = r.height, mx = r.midX
        let base = CGRect(x: mx - w * 0.3, y: r.maxY - h * 0.4, width: w * 0.6, height: h * 0.4)
        let ring = CGRect(x: mx - w * 0.27, y: base.minY - h * 0.04, width: w * 0.54, height: h * 0.04)
        let sleeve = CGRect(x: mx - w * 0.22, y: ring.minY - h * 0.11, width: w * 0.44, height: h * 0.11)
        let bw = w * 0.36
        var p = CapParts()
        p.ring = ring
        p.sleeve = sleeve
        p.bulletWidth = bw
        p.bulletBottom = sleeve.minY + sleeve.height * 0.35
        p.bulletMaxLength = p.bulletBottom - (r.minY + h * 0.02)
        g.parts = p
        g.capRect = base
        g.solid.addRoundedRect(in: base, cornerSize: CGSize(width: w * 0.06, height: w * 0.06), style: .continuous)
        g.glass.addRect(ring)
        g.vesselRect = CGRect(x: mx - bw / 2, y: r.minY + h * 0.02, width: bw, height: p.bulletMaxLength)
        g.liquidRect = g.vesselRect
        g.vessel = Path(g.vesselRect)
        g.cavity = g.vessel
        g.labelCenter = CGPoint(x: base.midX, y: base.midY + base.height * 0.05)
        g.labelDiameter = min(base.width * 0.7, base.height * 0.58)
        g.emitPoint = CGPoint(x: mx, y: r.minY + h * 0.1)
        g.emitDirection = CGVector(dx: 0, dy: -1)
    }

    // MARK: 粉盒（圆形，镜面盖立在后面）

    private static func makeCompact(_ g: inout ContainerGeometry, _ r: CGRect) {
        let w = r.width, h = r.height
        let faceH = min(h * 0.2, w * 0.34)
        let baseRect = CGRect(x: r.minX, y: r.maxY - faceH * 1.5, width: w, height: faceH * 1.5)
        let topFace = CGRect(x: r.minX, y: baseRect.minY, width: w, height: faceH)
        let pan = topFace.insetBy(dx: w * 0.13, dy: faceH * 0.16)
        var p = CapParts()
        p.topFace = topFace
        p.pan = pan
        p.hingeY = topFace.minY + faceH * 0.12
        p.lidRadius = min(w * 0.44, (p.hingeY - r.minY) / 2 - 1)
        g.parts = p
        g.vesselRect = pan
        g.liquidRect = pan
        g.capRect = baseRect
        g.vessel = Path(ellipseIn: pan)
        g.cavity = g.vessel
        g.solid.addEllipse(in: topFace)
        g.solid.addRect(CGRect(x: r.minX, y: topFace.midY, width: w, height: baseRect.maxY - faceH / 2 - topFace.midY))
        g.glass.addEllipse(in: CGRect(x: r.midX - p.lidRadius, y: p.hingeY - p.lidRadius * 2,
                                      width: p.lidRadius * 2, height: p.lidRadius * 2))
        g.labelCenter = CGPoint(x: r.midX, y: p.hingeY - p.lidRadius)
        g.labelDiameter = p.lidRadius * 1.25
        g.badgeCenter = CGPoint(x: pan.midX, y: pan.midY)
        g.emitPoint = CGPoint(x: pan.midX, y: pan.midY)
        g.emitDirection = CGVector(dx: 0, dy: -1)
    }
}

// MARK: - 兼容旧接口的 Shape

/// 把几何里的某一部分当成 SwiftUI Shape 使用
struct ContainerPart: Shape {
    enum Part { case glass, solid, vessel, cavity }
    var kind: VesselKind
    var part: Part
    var cap: CapStyle = .screw

    func path(in rect: CGRect) -> Path {
        let g = ContainerGeometry.make(kind, cap: cap, in: rect)
        switch part {
        case .glass: return g.glass
        case .solid: return g.solid
        case .vessel: return g.vessel
        case .cavity: return g.cavity
        }
    }
}

// MARK: - 液面数学

/// 一帧液面的状态：倾角（弧度，正 = 右侧抬高）、相位、晃动能量
struct LiquidFrame: Equatable {
    var angle: Double = 0
    var phase: Double = 0
    var energy: Double = 0
    static let still = LiquidFrame()
}

/// 液面曲线：基准高度 + 倾斜 + 波浪 + 贴壁的弯月面
enum LiquidMath {
    static func baseY(region: CGRect, level: Double) -> CGFloat {
        region.maxY - region.height * CGFloat(max(0, min(1, level)))
    }

    static func surfaceY(_ x: CGFloat, region: CGRect, level: Double, angle: Double,
                         phase: Double, amp: CGFloat, meniscus: CGFloat) -> CGFloat {
        let base = baseY(region: region, level: level)
        let tilt = -CGFloat(tan(max(-0.6, min(0.6, angle)))) * (x - region.midX)
        let u = (x - region.minX) / max(1, region.width)
        let wave = CGFloat(sin(Double(u) * .pi * 2 + phase)) * amp
            + CGFloat(sin(Double(u) * .pi * 3.4 - phase * 1.3)) * amp * 0.35
        var m: CGFloat = 0
        if meniscus > 0 {
            let mw = max(1, region.width * 0.07)
            let dl = max(0, x - region.minX), dr = max(0, region.maxX - x)
            m = meniscus * (CGFloat(exp(-Double(dl / mw))) + CGFloat(exp(-Double(dr / mw))))
        }
        return base + tilt + wave - m
    }

    private static func xs(_ x0: CGFloat, _ x1: CGFloat) -> [CGFloat] {
        let step = max(1, (x1 - x0) / 48)
        var out: [CGFloat] = []
        var x = x0
        while x < x1 {
            out.append(x)
            x += step
        }
        out.append(x1)
        return out
    }

    /// 液面线（开放路径），横跨 xRange
    static func line(region: CGRect, level: Double, angle: Double, phase: Double, amp: CGFloat,
                     meniscus: CGFloat, xRange: ClosedRange<CGFloat>? = nil) -> Path {
        var p = Path()
        let range = xRange ?? (region.minX - 2)...(region.maxX + 2)
        for (i, x) in xs(range.lowerBound, range.upperBound).enumerated() {
            let pt = CGPoint(x: x, y: surfaceY(x, region: region, level: level, angle: angle,
                                              phase: phase, amp: amp, meniscus: meniscus))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    /// 液面以下的闭合区域，向下延伸到 bottom
    static func fillBelow(region: CGRect, level: Double, angle: Double, phase: Double, amp: CGFloat,
                          meniscus: CGFloat, xRange: ClosedRange<CGFloat>? = nil, bottom: CGFloat? = nil) -> Path {
        guard level > 0.002 else { return Path() }
        let range = xRange ?? (region.minX - 2)...(region.maxX + 2)
        var p = line(region: region, level: level, angle: angle, phase: phase, amp: amp, meniscus: meniscus, xRange: range)
        let b = bottom ?? region.maxY + 2
        p.addLine(to: CGPoint(x: range.upperBound, y: b))
        p.addLine(to: CGPoint(x: range.lowerBound, y: b))
        p.closeSubpath()
        return p
    }

    /// 液面以上的闭合区域，向上延伸到 top
    static func fillAbove(region: CGRect, level: Double, angle: Double, phase: Double, amp: CGFloat,
                          meniscus: CGFloat, xRange: ClosedRange<CGFloat>? = nil, top: CGFloat) -> Path {
        let range = xRange ?? (region.minX - 2)...(region.maxX + 2)
        var p = line(region: region, level: level, angle: angle, phase: phase, amp: amp, meniscus: meniscus, xRange: range)
        p.addLine(to: CGPoint(x: range.upperBound, y: top))
        p.addLine(to: CGPoint(x: range.lowerBound, y: top))
        p.closeSubpath()
        return p
    }
}

/// 晃动的液面（旧接口，保留给其他界面用）。level 可动画。
struct WaveShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double
    /// 液体所在区域（容器坐标系）
    var region: CGRect

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        LiquidMath.fillBelow(region: region, level: level, angle: 0, phase: phase,
                             amp: CGFloat(amplitude), meniscus: 0)
    }
}

/// 抠图上的"剩余量"遮罩：液面以下（below）或以上（above），波浪边界、跟随倾斜。
/// 横向铺满整个矩形，让整张抠图都被覆盖。
struct LevelMaskShape: Shape {
    var level: Double
    var frame: LiquidFrame
    var amplitude: CGFloat
    var region: CGRect
    var below: Bool

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let big = max(rect.width, rect.height)
        let range = (rect.minX - big)...(rect.maxX + big)
        if level >= 0.999 { return below ? Path(rect.insetBy(dx: -big, dy: -big)) : Path() }
        if level <= 0.001 { return below ? Path() : Path(rect.insetBy(dx: -big, dy: -big)) }
        if below {
            return LiquidMath.fillBelow(region: region, level: level, angle: frame.angle, phase: frame.phase,
                                        amp: amplitude, meniscus: 0, xRange: range, bottom: rect.maxY + big)
        }
        return LiquidMath.fillAbove(region: region, level: level, angle: frame.angle, phase: frame.phase,
                                    amp: amplitude, meniscus: 0, xRange: range, top: rect.minY - big)
    }
}

/// 抠图上的液面分界线（1pt 白色高光沿着波浪走）
struct LevelLineShape: Shape {
    var level: Double
    var frame: LiquidFrame
    var amplitude: CGFloat
    var region: CGRect

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard level > 0.01, level < 0.99 else { return Path() }
        return LiquidMath.line(region: region, level: level, angle: frame.angle, phase: frame.phase,
                               amp: amplitude, meniscus: 0, xRange: (rect.minX - 4)...(rect.maxX + 4))
    }
}

/// 一滴液体
struct DropShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.midX + r.width * 0.15, y: r.minY + r.height * 0.3),
                   control2: CGPoint(x: r.maxX + r.width * 0.15, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX - r.width * 0.15, y: r.maxY),
                   control2: CGPoint(x: r.midX - r.width * 0.15, y: r.minY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}

// MARK: - 姿态（详情页手势驱动的部件动画）

/// 容器各部件的姿态。全部可动画（VectorArithmetic），由详情页的手势 / 按钮驱动。
struct VesselPose: VectorArithmetic {
    /// 瓶盖 / 泵头 / 喷头 / 胶头按下（0...1）；有抠图时 = 整体压扁
    var capPress: Double = 0
    /// 管身被捏（0...1）
    var squeeze: Double = 0
    /// 罐盖抬起（0...1）
    var lidLift: Double = 0
    /// 罐盖拧过的角度（弧度）
    var lidTurn: Double = 0
    /// 面膜最上一片被揭起（0...1）
    var peel: Double = 0
    /// 揭下的那片飞走（0...1）
    var fly: Double = 0
    /// 口红旋出（0...1）
    var twist: Double = 0
    /// 粉盒盖打开（1 = 打开，平时就是打开的）
    var lidOpen: Double = 1

    static let rest = VesselPose()

    static var zero: VesselPose {
        VesselPose(capPress: 0, squeeze: 0, lidLift: 0, lidTurn: 0, peel: 0, fly: 0, twist: 0, lidOpen: 0)
    }

    private var values: [Double] { [capPress, squeeze, lidLift, lidTurn, peel, fly, twist, lidOpen] }

    private init(_ v: [Double]) {
        self.init(capPress: v[0], squeeze: v[1], lidLift: v[2], lidTurn: v[3],
                  peel: v[4], fly: v[5], twist: v[6], lidOpen: v[7])
    }

    init(capPress: Double = 0, squeeze: Double = 0, lidLift: Double = 0, lidTurn: Double = 0,
         peel: Double = 0, fly: Double = 0, twist: Double = 0, lidOpen: Double = 1) {
        self.capPress = capPress
        self.squeeze = squeeze
        self.lidLift = lidLift
        self.lidTurn = lidTurn
        self.peel = peel
        self.fly = fly
        self.twist = twist
        self.lidOpen = lidOpen
    }

    static func + (l: VesselPose, r: VesselPose) -> VesselPose {
        VesselPose(zip(l.values, r.values).map { $0 + $1 })
    }

    static func - (l: VesselPose, r: VesselPose) -> VesselPose {
        VesselPose(zip(l.values, r.values).map { $0 - $1 })
    }

    mutating func scale(by rhs: Double) {
        self = VesselPose(values.map { $0 * rhs })
    }

    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}
