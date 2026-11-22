import SwiftUI

// MARK: - 盖子材质

/// 瓶盖 / 外壳的材质。Product 里没有存这个字段，按形状、盖子、材质和分类推断。
enum CapMaterial: String, CaseIterable {
    case matteBlack, gold, white

    static func suggested(kind: VesselKind, cap: CapStyle, finish: GlassFinish, category: ProductCategory) -> CapMaterial {
        if category == .fragrance { return .gold }
        switch kind {
        case .stick, .compact: return .gold
        case .tube: return .white
        case .sheet: return .white
        case .jar: return finish == .amber ? .matteBlack : (finish == .clear ? .gold : .white)
        case .bottle:
            switch cap {
            case .dropper: return finish == .amber ? .gold : .matteBlack
            case .pump, .spray: return finish == .clear ? .matteBlack : .white
            default:
                switch finish {
                case .frosted, .opaque: return .white
                case .amber, .clear: return .matteBlack
                }
            }
        }
    }

    var stops: [Gradient.Stop] {
        switch self {
        case .matteBlack:
            return [.init(color: Color(hex: "1C1C1E"), location: 0),
                    .init(color: Color(hex: "3D3D40"), location: 0.26),
                    .init(color: Color(hex: "2B2B2D"), location: 0.6),
                    .init(color: Color(hex: "141416"), location: 1)]
        case .gold:
            return [.init(color: Color(hex: "755620"), location: 0),
                    .init(color: Color(hex: "E6CB84"), location: 0.24),
                    .init(color: Color(hex: "FFF4CC"), location: 0.36),
                    .init(color: Color(hex: "B98F3E"), location: 0.62),
                    .init(color: Color(hex: "684B1B"), location: 1)]
        case .white:
            return [.init(color: Color(hex: "D3D3D8"), location: 0),
                    .init(color: Color(hex: "FFFFFF"), location: 0.3),
                    .init(color: Color(hex: "F1F1F3"), location: 0.6),
                    .init(color: Color(hex: "C4C4CA"), location: 1)]
        }
    }

    /// 刻纹 / 分割线的颜色
    var groove: Color { self == .white ? Color.black.opacity(0.12) : Color.black.opacity(0.35) }
    var shine: Color { self == .matteBlack ? Color.white.opacity(0.14) : Color.white.opacity(0.55) }
    /// 胶头（滴管）
    var rubber: Color { self == .white ? Color(hex: "EDEDED") : Color(hex: "29292B") }
}

/// 一件容器插画的静态外观
struct VesselStyle: Equatable {
    var kind: VesselKind
    var cap: CapStyle
    var finish: GlassFinish
    var material: CapMaterial
    var tint: Color

    /// 是否有会晃动的液体（需要 TimelineView）
    var hasLiquid: Bool { (kind == .bottle || kind == .jar) && finish != .opaque }
}

// MARK: - 画师

/// 在 Canvas 里画一件容器：厚玻璃、弯月面、双层液体、高光、盖子细节。
/// 只依赖 style + 当前 level / pose / 液面帧，纯函数，可以每帧调用。
struct VesselPainter {
    var style: VesselStyle
    var dark: Bool
    var level: Double
    var pose: VesselPose
    var frame: LiquidFrame

    // 调色（初始化时算一次）
    private let liquid: Color
    private let liquidLight: Color
    private let liquidDeep: Color
    private let amber = Color(hex: "9A5A1C")
    private let outlineColor: Color

    init(style: VesselStyle, dark: Bool, level: Double, pose: VesselPose, frame: LiquidFrame) {
        self.style = style
        self.dark = dark
        self.level = level
        self.pose = pose
        self.frame = frame
        self.liquid = style.tint
        self.liquidLight = style.tint.mixed(with: .white, 0.38)
        self.liquidDeep = style.tint.mixed(with: .black, 0.22)
        self.outlineColor = dark ? Color.white.opacity(0.26) : Color.black.opacity(0.17)
    }

    func draw(_ ctx: GraphicsContext, size: CGSize) {
        let r = CGRect(origin: .zero, size: size)
        guard r.width > 2, r.height > 2 else { return }
        let g = ContainerGeometry.make(style.kind, cap: style.cap, in: r)
        switch style.kind {
        case .bottle: drawBottle(ctx, g)
        case .jar: drawJar(ctx, g)
        case .tube: drawTube(ctx, g, r)
        case .sheet: drawSheets(ctx, g, r)
        case .stick: drawStick(ctx, g, r)
        case .compact: drawCompact(ctx, g, r)
        }
    }

    // MARK: 通用

    private func metal(_ rect: CGRect, _ m: CapMaterial? = nil) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: (m ?? style.material).stops),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY))
    }

    private func vertical(_ colors: [Color], _ rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY))
    }

    private func horizontal(_ stops: [Gradient.Stop], _ rect: CGRect) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops),
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY))
    }

    private func rounded(_ r: CGRect, _ c: CGFloat) -> Path {
        Path(roundedRect: r, cornerSize: CGSize(width: max(0, c), height: max(0, c)), style: .continuous)
    }

    /// 竖向刻纹（旋盖、罐盖）
    private func ridges(_ ctx: GraphicsContext, in rect: CGRect, spacing: CGFloat, offset: CGFloat = 0, m: CapMaterial? = nil) {
        let mat = m ?? style.material
        guard spacing > 0.8, rect.width > 4 else { return }
        var grooves = Path(), light = Path()
        let off = offset.truncatingRemainder(dividingBy: spacing)
        var x = rect.minX + spacing * 0.5 + off
        if x < rect.minX { x += spacing }
        while x < rect.maxX - 0.5 {
            grooves.move(to: CGPoint(x: x, y: rect.minY))
            grooves.addLine(to: CGPoint(x: x, y: rect.maxY))
            light.move(to: CGPoint(x: x + 0.6, y: rect.minY))
            light.addLine(to: CGPoint(x: x + 0.6, y: rect.maxY))
            x += spacing
        }
        var c = ctx
        c.clip(to: Path(rect))
        c.stroke(grooves, with: .color(mat.groove), lineWidth: 0.5)
        c.stroke(light, with: .color(mat.shine.opacity(0.5)), lineWidth: 0.4)
        // 圆柱体明暗叠在刻纹上
        c.fill(Path(rect), with: horizontal([.init(color: .black.opacity(0.18), location: 0),
                                             .init(color: .clear, location: 0.3),
                                             .init(color: .clear, location: 0.7),
                                             .init(color: .black.opacity(0.22), location: 1)], rect))
    }

    /// 顶部一道细亮边
    private func topShine(_ ctx: GraphicsContext, _ rect: CGRect, corner: CGFloat, m: CapMaterial? = nil) {
        let mat = m ?? style.material
        var c = ctx
        c.clip(to: rounded(rect, corner))
        c.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.8, rect.height * 0.12))),
               with: .color(mat.shine.opacity(0.7)))
        c.fill(Path(CGRect(x: rect.minX, y: rect.maxY - max(0.8, rect.height * 0.12), width: rect.width, height: max(0.8, rect.height * 0.12))),
               with: .color(.black.opacity(0.18)))
    }

    private func glassBackColor() -> Color {
        switch style.finish {
        case .clear: return .white.opacity(dark ? 0.06 : 0.20)
        case .frosted: return .white.opacity(dark ? 0.14 : 0.36)
        case .amber: return amber.opacity(dark ? 0.30 : 0.26)
        case .opaque: return liquid
        }
    }

    // MARK: 液体（瓶 / 罐）

    private func drawLiquid(_ ctx: GraphicsContext, g: ContainerGeometry, viscous: Bool) {
        let region = g.liquidRect
        guard level > 0.002, region.height > 1 else { return }
        var c = ctx
        c.clip(to: g.cavity)
        let scale = max(0.35, min(1.2, region.height / 120))
        let amp = CGFloat((viscous ? 0.2 : 0.9) + frame.energy * (viscous ? 1.0 : 5.5)) * scale
        let angle = frame.angle * (viscous ? 0.15 : 1)
        let men: CGFloat = viscous ? 0 : max(0.8, region.width * 0.04)
        let top = LiquidMath.baseY(region: region, level: level) - region.height * 0.04
        let fillRect = CGRect(x: region.minX, y: top, width: region.width, height: region.maxY - top)

        let paint: (GraphicsContext) -> Void = { l in
            // 后层：液体的"背面"，相位错开、颜色更深，制造厚度
            let back = LiquidMath.fillBelow(region: region, level: level, angle: angle * 0.85,
                                            phase: frame.phase + 1.3, amp: amp * 0.8, meniscus: men * 0.6)
            l.fill(back, with: .color(liquidDeep.opacity(0.55)))
            // 前层：上浅下深的渐变
            let front = LiquidMath.fillBelow(region: region, level: level, angle: angle,
                                             phase: frame.phase, amp: amp, meniscus: men)
            l.fill(front, with: vertical([liquidLight, liquid, liquidDeep], fillRect))
            // 底部聚光：光透过液体打在厚玻璃底上
            l.fill(Path(ellipseIn: CGRect(x: region.minX + region.width * 0.15, y: region.maxY - region.height * 0.1,
                                          width: region.width * 0.7, height: region.height * 0.16))
                .intersection(front),
                   with: .color(liquidLight.opacity(0.35)))
            let line = LiquidMath.line(region: region, level: level, angle: angle,
                                       phase: frame.phase, amp: amp, meniscus: men)
            if viscous {
                // 膏体顶面：一条较宽的亮带，像从上方略微俯视
                let band = max(1.5, region.height * 0.07)
                l.stroke(line.offsetBy(dx: 0, dy: band * 0.5), with: .color(liquidLight.opacity(0.75)), lineWidth: band)
                l.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 0.7)
            } else {
                // 液面高光 + 液面下方一道暗线（表面张力的厚度）
                l.stroke(line.offsetBy(dx: 0, dy: max(1, region.width * 0.02)),
                         with: .color(liquidDeep.opacity(0.28)), lineWidth: max(0.8, region.width * 0.02))
                l.stroke(line, with: .color(.white.opacity(0.62)), lineWidth: max(0.6, region.width * 0.013))
            }
        }

        if style.finish == .frosted {
            c.drawLayer { layer in
                layer.addFilter(.blur(radius: max(1, region.width * 0.04)))
                paint(layer)
            }
        } else {
            paint(c)
        }
    }

    /// 玻璃壁 + 厚底 + 材质罩色
    private func drawGlassBody(_ ctx: GraphicsContext, g: ContainerGeometry) {
        let body = g.vesselRect
        var c = ctx
        c.clip(to: g.vessel)
        // 玻璃壁：外轮廓与内腔之间的一圈
        var ring = g.vessel
        let inner = body.insetBy(dx: g.wall, dy: g.wall)
        ring.addPath(rounded(inner, g.corner - g.wall))
        let wallColor: Color
        switch style.finish {
        case .clear: wallColor = .white.opacity(dark ? 0.16 : 0.42)
        case .frosted: wallColor = .white.opacity(dark ? 0.22 : 0.5)
        case .amber: wallColor = Color(hex: "C98B46").opacity(0.5)
        case .opaque: wallColor = .white.opacity(0.18)
        }
        c.fill(ring, with: .color(wallColor), style: FillStyle(eoFill: true))
        if style.finish != .opaque {
            c.stroke(rounded(inner, g.corner - g.wall), with: .color(.black.opacity(dark ? 0.3 : 0.08)), lineWidth: 0.5)
        }

        // 厚玻璃底
        if style.finish != .opaque {
            let base = g.baseRect
            c.fill(Path(base), with: vertical([.white.opacity(dark ? 0.22 : 0.55), .white.opacity(dark ? 0.08 : 0.22)], base))
            if level > 0.01 {
                // 液体颜色折射进玻璃底
                c.fill(Path(CGRect(x: base.minX, y: base.minY, width: base.width, height: base.height * 0.55)),
                       with: .color(liquid.opacity(0.22)))
            }
            var floor = Path()
            floor.move(to: CGPoint(x: base.minX + g.wall, y: base.minY + 0.5))
            floor.addLine(to: CGPoint(x: base.maxX - g.wall, y: base.minY + 0.5))
            c.stroke(floor, with: .color(.white.opacity(0.75)), lineWidth: 0.8)
            // 底部内侧的一道弧形反光
            var arc = Path()
            arc.move(to: CGPoint(x: base.minX + base.width * 0.22, y: base.maxY - base.height * 0.35))
            arc.addQuadCurve(to: CGPoint(x: base.maxX - base.width * 0.22, y: base.maxY - base.height * 0.35),
                             control: CGPoint(x: base.midX, y: base.maxY - base.height * 0.05))
            c.stroke(arc, with: .color(.white.opacity(0.4)), lineWidth: 0.7)
        }

        // 材质罩色
        switch style.finish {
        case .frosted:
            c.fill(g.vessel, with: .color(.white.opacity(dark ? 0.10 : 0.24)))
        case .amber:
            var m = c
            m.blendMode = .multiply
            m.fill(g.vessel, with: .color(Color(hex: "B8752F").opacity(0.55)))
            c.fill(g.vessel, with: .color(amber.opacity(0.08)))
        default: break
        }
    }

    /// 不透明瓶身：圆柱明暗 + 侧边细竖条显示剩余
    private func drawOpaqueBody(_ ctx: GraphicsContext, g: ContainerGeometry) {
        let body = g.vesselRect
        let shell = liquid.mixed(with: .white, dark ? 0.1 : 0.25)
        ctx.fill(g.vessel, with: horizontal([.init(color: shell.mixed(with: .black, 0.22), location: 0),
                                             .init(color: shell.mixed(with: .white, 0.25), location: 0.28),
                                             .init(color: shell, location: 0.55),
                                             .init(color: shell.mixed(with: .black, 0.28), location: 1)], body))
        drawGauge(ctx, g: g)
    }

    private func drawGauge(_ ctx: GraphicsContext, g: ContainerGeometry) {
        let region = g.liquidRect
        let gw = max(2, g.vesselRect.width * 0.055)
        let track = CGRect(x: g.vesselRect.maxX - g.wall - gw * 2.4, y: region.minY + region.height * 0.08,
                           width: gw, height: region.height * 0.84)
        ctx.fill(Path(roundedRect: track, cornerRadius: gw / 2), with: .color(.white.opacity(0.42)))
        let fh = track.height * CGFloat(max(0, min(1, level)))
        if fh > 0.5 {
            let fill = CGRect(x: track.minX, y: track.maxY - fh, width: gw, height: fh)
            ctx.fill(Path(roundedRect: fill, cornerRadius: gw / 2),
                     with: .color(style.tint.luminance > 0.75 ? liquidDeep.mixed(with: .black, 0.25) : liquidDeep))
        }
        ctx.stroke(Path(roundedRect: track, cornerRadius: gw / 2), with: .color(.black.opacity(0.12)), lineWidth: 0.5)
    }

    /// 高光：随倾斜轻轻移动
    private func drawSpecular(_ ctx: GraphicsContext, g: ContainerGeometry, strength: Double) {
        let body = g.vesselRect
        let shift = CGFloat(frame.angle) * body.width * 0.09
        var c = ctx
        c.clip(to: g.vessel)
        let s1 = CGRect(x: body.minX + body.width * 0.13 + shift, y: body.minY + body.height * 0.09,
                        width: body.width * 0.075, height: body.height * 0.72)
        c.fill(rounded(s1, s1.width / 2),
               with: vertical([.white.opacity(0), .white.opacity(0.62 * strength), .white.opacity(0.38 * strength), .white.opacity(0)], s1))
        let s2 = CGRect(x: body.minX + body.width * 0.25 + shift * 1.3, y: body.minY + body.height * 0.16,
                        width: max(0.8, body.width * 0.025), height: body.height * 0.48)
        c.fill(rounded(s2, s2.width / 2),
               with: vertical([.white.opacity(0), .white.opacity(0.4 * strength), .white.opacity(0)], s2))
        let s3 = CGRect(x: body.maxX - body.width * 0.12 + shift * 0.5, y: body.minY + body.height * 0.18,
                        width: max(0.8, body.width * 0.035), height: body.height * 0.55)
        c.fill(rounded(s3, s3.width / 2),
               with: vertical([.white.opacity(0), .white.opacity(0.26 * strength), .white.opacity(0)], s3))
        // 肩部的一小段弧光
        var shoulder = Path()
        shoulder.move(to: CGPoint(x: body.minX + g.corner * 0.55, y: body.minY + g.corner * 0.35))
        shoulder.addQuadCurve(to: CGPoint(x: body.minX + body.width * 0.42, y: body.minY + g.wall * 0.8),
                              control: CGPoint(x: body.minX + body.width * 0.18, y: body.minY + g.wall * 0.4))
        c.stroke(shoulder, with: .color(.white.opacity(0.55 * strength)), lineWidth: max(0.6, body.width * 0.018))
    }

    /// 边缘光 + 轮廓
    private func drawRim(_ ctx: GraphicsContext, path: Path, rect: CGRect) {
        ctx.stroke(path, with: horizontal([.init(color: .white.opacity(0.65), location: 0),
                                           .init(color: .white.opacity(0.06), location: 0.35),
                                           .init(color: .white.opacity(0.0), location: 0.65),
                                           .init(color: .white.opacity(0.42), location: 1)], rect),
                   lineWidth: 1)
        ctx.stroke(path, with: .color(outlineColor), lineWidth: 0.6)
    }

    // MARK: 瓶

    private func drawBottle(_ ctx: GraphicsContext, _ g: ContainerGeometry) {
        // 瓶颈（玻璃）
        let neck = g.neckRect
        if style.finish == .opaque {
            ctx.fill(Path(neck), with: metal(neck, .white))
        } else {
            ctx.fill(Path(neck), with: .color(glassBackColor()))
            ctx.fill(Path(neck), with: horizontal([.init(color: .white.opacity(0.5), location: 0),
                                                   .init(color: .clear, location: 0.3),
                                                   .init(color: .clear, location: 0.75),
                                                   .init(color: .white.opacity(0.35), location: 1)], neck))
        }
        ctx.stroke(Path(neck), with: .color(outlineColor), lineWidth: 0.5)

        if style.finish == .opaque {
            drawOpaqueBody(ctx, g: g)
        } else {
            ctx.fill(g.vessel, with: .color(glassBackColor()))
            drawLiquid(ctx, g: g, viscous: false)
            drawDipTube(ctx, g)
            drawGlassBody(ctx, g: g)
        }
        drawSpecular(ctx, g: g, strength: style.finish == .frosted ? 0.55 : (style.finish == .opaque ? 0.7 : 1))
        drawRim(ctx, path: g.vessel, rect: g.vesselRect)
        drawBottleCap(ctx, g)
    }

    /// 泵 / 喷头的吸管、滴管的玻璃管：透过玻璃看得见
    private func drawDipTube(_ ctx: GraphicsContext, _ g: ContainerGeometry) {
        guard style.finish == .clear || style.finish == .amber || style.finish == .frosted else { return }
        let body = g.vesselRect
        var c = ctx
        c.clip(to: g.cavity)
        switch style.cap {
        case .pump, .spray:
            let tw = max(0.8, body.width * 0.025)
            var p = Path()
            p.move(to: CGPoint(x: body.midX, y: body.minY))
            p.addLine(to: CGPoint(x: body.midX + body.width * 0.05, y: g.liquidRect.maxY - 1))
            c.stroke(p, with: .color(.white.opacity(dark ? 0.3 : 0.55)), lineWidth: tw)
        case .dropper:
            let tw = max(2, body.width * 0.075)
            let tube = CGRect(x: body.midX - tw / 2, y: body.minY, width: tw, height: g.liquidRect.height * 0.72)
            c.fill(rounded(tube, tw / 2), with: .color(.white.opacity(dark ? 0.14 : 0.28)))
            c.stroke(rounded(tube, tw / 2), with: .color(.white.opacity(0.6)), lineWidth: 0.5)
        default: break
        }
    }

    private func drawBottleCap(_ ctx: GraphicsContext, _ g: ContainerGeometry) {
        let p = g.parts
        let h = g.vesselRect.maxY - (g.capRect.minY)
        let press = CGFloat(max(0, min(1, pose.capPress)))
        switch style.cap {
        case .screw:
            let cap = g.capRect
            let cr = cap.width * 0.1
            ctx.fill(rounded(cap, cr), with: metal(cap))
            ridges(ctx, in: cap.insetBy(dx: cap.width * 0.04, dy: cap.height * 0.14), spacing: max(1.6, cap.width / 14))
            topShine(ctx, cap, corner: cr)
            ctx.stroke(rounded(cap, cr), with: .color(outlineColor), lineWidth: 0.5)

        case .flip:
            let cap = g.capRect
            let cr = cap.width * 0.16
            ctx.fill(rounded(cap, cr), with: metal(cap))
            var seam = Path()
            seam.move(to: CGPoint(x: cap.minX, y: cap.minY + cap.height * 0.4))
            seam.addLine(to: CGPoint(x: cap.maxX, y: cap.minY + cap.height * 0.4))
            ctx.stroke(seam, with: .color(style.material.groove), lineWidth: 0.7)
            let notch = CGRect(x: cap.midX - cap.width * 0.12, y: cap.minY + cap.height * 0.32, width: cap.width * 0.24, height: cap.height * 0.14)
            ctx.fill(rounded(notch, notch.height / 2), with: .color(style.material.groove))
            topShine(ctx, cap, corner: cr)
            ctx.stroke(rounded(cap, cr), with: .color(outlineColor), lineWidth: 0.5)

        case .dropper:
            // 胶头：按下时变矮变胖，底部贴着金属环
            let b = p.bulb
            let bh = b.height * (1 - 0.38 * press)
            let bw = b.width * (1 + 0.14 * press)
            let bulb = CGRect(x: b.midX - bw / 2, y: b.maxY - bh, width: bw, height: bh)
            let rubber = style.material.rubber
            ctx.fill(rounded(bulb, bw / 2), with: horizontal([.init(color: rubber.mixed(with: .black, 0.25), location: 0),
                                                              .init(color: rubber.mixed(with: .white, 0.18), location: 0.32),
                                                              .init(color: rubber, location: 0.6),
                                                              .init(color: rubber.mixed(with: .black, 0.35), location: 1)], bulb))
            let hl = CGRect(x: bulb.minX + bw * 0.22, y: bulb.minY + bh * 0.12, width: max(0.8, bw * 0.12), height: bh * 0.5)
            ctx.fill(rounded(hl, hl.width / 2), with: .color(.white.opacity(style.material == .white ? 0.7 : 0.22)))
            ctx.stroke(rounded(bulb, bw / 2), with: .color(outlineColor), lineWidth: 0.5)
            let collar = p.collar
            ctx.fill(rounded(collar, collar.width * 0.08), with: metal(collar))
            ridges(ctx, in: collar.insetBy(dx: 1, dy: collar.height * 0.18), spacing: max(1.8, collar.width / 10))
            topShine(ctx, collar, corner: collar.width * 0.08)
            ctx.stroke(rounded(collar, collar.width * 0.08), with: .color(outlineColor), lineWidth: 0.5)

        case .pump:
            let dy = press * h * 0.045
            let stem = CGRect(x: p.stem.minX, y: p.stem.minY + dy, width: p.stem.width, height: max(0.5, p.stem.height - dy))
            ctx.fill(Path(stem), with: metal(stem, style.material == .gold ? CapMaterial.gold : CapMaterial.white))
            ctx.stroke(Path(stem), with: .color(outlineColor), lineWidth: 0.4)
            let head = p.head.offsetBy(dx: 0, dy: dy)
            let nozzle = p.nozzle.offsetBy(dx: 0, dy: dy)
            ctx.fill(rounded(nozzle, nozzle.height / 2), with: metal(nozzle))
            ctx.fill(Path(ellipseIn: CGRect(x: nozzle.minX + 0.5, y: nozzle.midY - nozzle.height * 0.22,
                                            width: nozzle.height * 0.44, height: nozzle.height * 0.44)),
                     with: .color(.black.opacity(0.55)))
            ctx.stroke(rounded(nozzle, nozzle.height / 2), with: .color(outlineColor), lineWidth: 0.4)
            ctx.fill(rounded(head, head.height * 0.3), with: metal(head))
            topShine(ctx, head, corner: head.height * 0.3)
            ctx.stroke(rounded(head, head.height * 0.3), with: .color(outlineColor), lineWidth: 0.5)
            let collar = p.collar
            ctx.fill(rounded(collar, collar.width * 0.1), with: metal(collar))
            ridges(ctx, in: collar.insetBy(dx: 1, dy: collar.height * 0.2), spacing: max(1.8, collar.width / 12))
            topShine(ctx, collar, corner: collar.width * 0.1)
            ctx.stroke(rounded(collar, collar.width * 0.1), with: .color(outlineColor), lineWidth: 0.5)

        case .spray:
            let dy = press * h * 0.035
            let head = p.head.offsetBy(dx: 0, dy: dy)
            ctx.fill(rounded(head, head.width * 0.2), with: metal(head))
            // 喷口
            let o = max(1.2, head.width * 0.12)
            ctx.fill(Path(ellipseIn: CGRect(x: head.minX + o * 0.4, y: head.minY + head.height * 0.35 - o / 2, width: o, height: o)),
                     with: .color(.black.opacity(0.6)))
            topShine(ctx, head, corner: head.width * 0.2)
            ctx.stroke(rounded(head, head.width * 0.2), with: .color(outlineColor), lineWidth: 0.5)
            let collar = p.collar
            ctx.fill(rounded(collar, collar.height * 0.25), with: metal(collar))
            // 压接环的横向褶
            var folds = Path()
            for i in 1...2 {
                let y = collar.minY + collar.height * CGFloat(i) / 3
                folds.move(to: CGPoint(x: collar.minX + 1, y: y))
                folds.addLine(to: CGPoint(x: collar.maxX - 1, y: y))
            }
            ctx.stroke(folds, with: .color(style.material.groove), lineWidth: 0.5)
            topShine(ctx, collar, corner: collar.height * 0.25)
            ctx.stroke(rounded(collar, collar.height * 0.25), with: .color(outlineColor), lineWidth: 0.5)

        case .none:
            let lip = p.lip
            ctx.fill(rounded(lip, lip.height * 0.4), with: .color(.white.opacity(dark ? 0.25 : 0.6)))
            ctx.stroke(rounded(lip, lip.height * 0.4), with: .color(outlineColor), lineWidth: 0.5)
        }
    }

    // MARK: 罐

    private func drawJar(_ ctx: GraphicsContext, _ g: ContainerGeometry) {
        let body = g.vesselRect
        if style.finish == .opaque {
            drawOpaqueBody(ctx, g: g)
        } else {
            ctx.fill(g.vessel, with: .color(glassBackColor()))
            drawLiquid(ctx, g: g, viscous: true)
            drawGlassBody(ctx, g: g)
        }
        // 罐口螺纹带
        let thread = CGRect(x: body.minX + g.wall * 0.6, y: body.minY, width: body.width - g.wall * 1.2, height: max(1.5, body.height * 0.07))
        ctx.fill(Path(thread), with: .color(.white.opacity(dark ? 0.12 : 0.35)))
        var tl = Path()
        tl.move(to: CGPoint(x: thread.minX, y: thread.maxY))
        tl.addLine(to: CGPoint(x: thread.maxX, y: thread.maxY))
        ctx.stroke(tl, with: .color(outlineColor), lineWidth: 0.4)
        drawSpecular(ctx, g: g, strength: style.finish == .frosted ? 0.55 : 0.9)
        drawRim(ctx, path: g.vessel, rect: body)

        // 盖子：拧动时刻纹横移，拧开后抬起
        let lid = g.capRect
        let lift = CGFloat(max(0, min(1, pose.lidLift)))
        if lift > 0.01 {
            // 露出的罐口
            let mouth = CGRect(x: body.minX + g.wall, y: body.minY - body.height * 0.04, width: body.width - g.wall * 2, height: body.height * 0.1)
            ctx.fill(Path(ellipseIn: mouth), with: .color(.black.opacity(0.18 * lift)))
        }
        var lc = ctx
        lc.translateBy(x: lid.midX + lift * lid.width * 0.06, y: lid.midY - lift * (body.maxY - lid.minY) * 0.32)
        lc.rotate(by: .degrees(Double(-9 * lift)))
        lc.translateBy(x: -lid.midX, y: -lid.midY)
        let cr = lid.width * 0.07
        lc.fill(rounded(lid, cr), with: metal(lid))
        ridges(lc, in: lid.insetBy(dx: lid.width * 0.02, dy: lid.height * 0.2), spacing: max(1.8, lid.width / 22),
               offset: CGFloat(pose.lidTurn) * lid.width * 0.18)
        topShine(lc, lid, corner: cr)
        lc.stroke(rounded(lid, cr), with: .color(outlineColor), lineWidth: 0.5)
    }

    // MARK: 管

    private func drawTube(_ ctx: GraphicsContext, _ g: ContainerGeometry, _ r: CGRect) {
        let p = g.parts
        let cap = g.capRect
        let squeeze = CGFloat(max(0, min(1, pose.squeeze)))
        let body = ContainerGeometry.tubeBody(top: p.crimp.maxY, bottom: cap.minY + 1, midX: r.midX,
                                              topW: p.tubeTopWidth, botW: p.tubeBottomWidth, squeeze: squeeze)
        let rect = g.vesselRect
        let plastic = liquid.mixed(with: .white, dark ? 0.3 : 0.5)

        // 压封尾部：齿边 + 横向压纹
        let crimp = p.crimp
        let crimpColor = plastic.mixed(with: .black, 0.08)
        var teeth = Path()
        let n = max(6, Int(crimp.width / 3))
        let tw = crimp.width / CGFloat(n)
        teeth.move(to: CGPoint(x: crimp.minX, y: crimp.maxY))
        teeth.addLine(to: CGPoint(x: crimp.minX, y: crimp.minY + tw * 0.5))
        for i in 0..<n {
            let x0 = crimp.minX + CGFloat(i) * tw
            teeth.addLine(to: CGPoint(x: x0 + tw / 2, y: crimp.minY))
            teeth.addLine(to: CGPoint(x: x0 + tw, y: crimp.minY + tw * 0.5))
        }
        teeth.addLine(to: CGPoint(x: crimp.maxX, y: crimp.maxY))
        teeth.closeSubpath()
        ctx.fill(teeth, with: horizontal([.init(color: crimpColor.mixed(with: .black, 0.12), location: 0),
                                          .init(color: crimpColor.mixed(with: .white, 0.3), location: 0.35),
                                          .init(color: crimpColor.mixed(with: .black, 0.15), location: 1)], crimp))
        var lines = Path()
        for i in 1...3 {
            let y = crimp.minY + crimp.height * (0.25 + CGFloat(i) * 0.18)
            lines.move(to: CGPoint(x: crimp.minX + 1, y: y))
            lines.addLine(to: CGPoint(x: crimp.maxX - 1, y: y))
        }
        ctx.stroke(lines, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
        ctx.stroke(teeth, with: .color(outlineColor), lineWidth: 0.5)

        // 管身：扁平软管的明暗（两侧暗、偏左亮、中间一道高光）
        ctx.fill(body, with: horizontal([.init(color: plastic.mixed(with: .black, 0.2), location: 0),
                                         .init(color: plastic.mixed(with: .white, 0.15), location: 0.2),
                                         .init(color: plastic.mixed(with: .white, 0.45), location: 0.36),
                                         .init(color: plastic, location: 0.6),
                                         .init(color: plastic.mixed(with: .black, 0.24), location: 1)], rect))
        var c = ctx
        c.clip(to: body)
        // 捏的时候腰部出现两道褶
        if squeeze > 0.02 {
            let y = rect.minY + rect.height * 0.5
            var crease = Path()
            crease.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: y - rect.height * 0.08))
            crease.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: y - rect.height * 0.08),
                                control: CGPoint(x: rect.midX, y: y))
            c.stroke(crease, with: .color(.black.opacity(0.16 * Double(squeeze))), lineWidth: 0.8)
        }
        // 已经挤空的部分：变白、变扁，压出斜褶
        let edge = LiquidMath.baseY(region: rect, level: level)
        if level < 0.995 {
            let used = CGRect(x: rect.minX - 2, y: rect.minY - 2, width: rect.width + 4, height: edge - rect.minY + 2)
            c.fill(Path(used), with: .color(.white.opacity(dark ? 0.22 : 0.38)))
            var folds = Path()
            var y = rect.minY + rect.height * 0.08
            while y < edge - rect.height * 0.06 {
                folds.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: y))
                folds.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: y + rect.height * 0.05))
                y += rect.height * 0.14
            }
            c.stroke(folds, with: .color(.black.opacity(0.09)), lineWidth: 0.6)
            if level > 0.005 {
                let line = LiquidMath.line(region: rect, level: level, angle: 0, phase: 0.6,
                                           amp: max(0.6, rect.height * 0.012), meniscus: 0)
                c.stroke(line, with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        // 中央高光
        let hl = CGRect(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.05, width: rect.width * 0.08, height: rect.height * 0.8)
        c.fill(rounded(hl, hl.width / 2), with: vertical([.white.opacity(0), .white.opacity(0.45), .white.opacity(0)], hl))
        ctx.stroke(body, with: .color(outlineColor), lineWidth: 0.6)

        // 翻盖
        let cr = cap.width * 0.16
        ctx.fill(rounded(cap, cr), with: metal(cap))
        var seam = Path()
        seam.move(to: CGPoint(x: cap.minX, y: cap.minY + cap.height * 0.34))
        seam.addLine(to: CGPoint(x: cap.maxX, y: cap.minY + cap.height * 0.34))
        ctx.stroke(seam, with: .color(style.material.groove), lineWidth: 0.6)
        let hinge = CGRect(x: cap.maxX - cap.width * 0.06, y: cap.minY + cap.height * 0.22, width: cap.width * 0.08, height: cap.height * 0.24)
        ctx.fill(rounded(hinge, 1), with: .color(style.material.groove))
        topShine(ctx, cap, corner: cr)
        ctx.stroke(rounded(cap, cr), with: .color(outlineColor), lineWidth: 0.5)
    }

    // MARK: 面膜袋

    private func drawSachet(_ ctx: GraphicsContext, _ rect: CGRect, corner: CGFloat, shade: Double, front: Bool) {
        let foil = liquid.mixed(with: .black, shade)
        let path = rounded(rect, corner)
        ctx.fill(path, with: .linearGradient(Gradient(colors: [foil.mixed(with: .white, 0.45), foil, foil.mixed(with: .black, 0.12)]),
                                             startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                             endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        var c = ctx
        c.clip(to: path)
        // 上下压封带 + 竖向压纹
        let sealH = rect.height * 0.08
        for band in [CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: sealH),
                     CGRect(x: rect.minX, y: rect.maxY - sealH, width: rect.width, height: sealH)] {
            c.fill(Path(band), with: .color(.white.opacity(0.18)))
            var ticks = Path()
            var x = band.minX + 1.2
            while x < band.maxX {
                ticks.move(to: CGPoint(x: x, y: band.minY + 0.5))
                ticks.addLine(to: CGPoint(x: x, y: band.maxY - 0.5))
                x += max(1.4, rect.width / 30)
            }
            c.stroke(ticks, with: .color(.black.opacity(0.08)), lineWidth: 0.4)
        }
        if front {
            // 斜向光泽
            var gloss = Path()
            gloss.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.25))
            gloss.addLine(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY))
            gloss.addLine(to: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY))
            gloss.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.42))
            gloss.closeSubpath()
            c.fill(gloss, with: .color(.white.opacity(0.22)))
            // 撕口
            var notch = Path()
            notch.move(to: CGPoint(x: rect.maxX, y: rect.minY + sealH * 1.4))
            notch.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.minY + sealH * 1.7))
            notch.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + sealH * 2.0))
            c.stroke(notch, with: .color(.black.opacity(0.3)), lineWidth: 0.6)
        }
        ctx.stroke(path, with: .color(outlineColor), lineWidth: 0.5)
    }

    private func drawSheets(_ ctx: GraphicsContext, _ g: ContainerGeometry, _ r: CGRect) {
        let front = g.vesselRect
        let w = r.width, h = r.height
        let backs = level >= 0.45 ? 2 : (level > 0.12 ? 1 : 0)
        for k in stride(from: backs, through: 1, by: -1) {
            let rect = front.offsetBy(dx: w * 0.08 * CGFloat(k), dy: -h * 0.05 * CGFloat(k))
            drawSachet(ctx, rect, corner: g.corner, shade: 0.06 * Double(k), front: false)
        }
        guard level > 0.001 || pose.fly > 0 else {
            // 用完了：只剩一个虚线轮廓
            ctx.stroke(rounded(front, g.corner), with: .color(outlineColor), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            return
        }

        let fly = CGFloat(max(0, min(1, pose.fly)))
        var fc = ctx
        if fly > 0 {
            fc.opacity = Double(1 - fly)
            fc.translateBy(x: front.midX + fly * w * 0.9, y: front.midY - fly * h * 0.55)
            fc.rotate(by: .degrees(Double(28 * fly)))
            fc.translateBy(x: -front.midX, y: -front.midY)
        }
        let peel = CGFloat(max(0, min(1, pose.peel)))
        let d = peel * min(front.width, front.height) * 0.85
        if d > 0.5 {
            // 右上角沿 A–B 折下
            let A = CGPoint(x: front.maxX - d, y: front.minY)
            let B = CGPoint(x: front.maxX, y: front.minY + d)
            var corner = Path()
            corner.move(to: A)
            corner.addLine(to: CGPoint(x: front.maxX + 2, y: front.minY - 2))
            corner.addLine(to: B)
            corner.closeSubpath()
            var body = fc
            body.clip(to: corner, options: .inverse)
            drawSachet(body, front, corner: g.corner, shade: 0, front: true)
            // 翻折下来的那片（背面：银色）
            let Cp = CGPoint(x: front.maxX - d, y: front.minY + d)
            var flap = Path()
            flap.move(to: A)
            flap.addLine(to: B)
            flap.addLine(to: Cp)
            flap.closeSubpath()
            var shadow = fc
            shadow.addFilter(.shadow(color: .black.opacity(0.25), radius: 2, x: -1, y: 1))
            shadow.fill(flap, with: .linearGradient(Gradient(colors: [Color(hex: "F4F5F7"), Color(hex: "C9CDD3")]),
                                                    startPoint: A, endPoint: Cp))
            fc.stroke(flap, with: .color(outlineColor), lineWidth: 0.5)
        } else {
            drawSachet(fc, front, corner: g.corner, shade: 0, front: true)
        }
    }

    // MARK: 口红

    private func drawStick(_ ctx: GraphicsContext, _ g: ContainerGeometry, _ r: CGRect) {
        let p = g.parts
        let w = r.width
        let base = g.capRect
        let twist = CGFloat(max(0, min(1, pose.twist)))
        let minLen = p.bulletMaxLength * 0.16
        var len = minLen + (p.bulletMaxLength * 0.78 - minLen) * CGFloat(max(0, min(1, level)))
        len = min(p.bulletMaxLength, len + twist * p.bulletMaxLength * 0.22)
        let bw = p.bulletWidth
        let left = r.midX - bw / 2, right = r.midX + bw / 2
        let bottom = p.bulletBottom
        let top = bottom - len
        let slant = min(bw * 0.75, len * 0.6)
        let tipR = bw * 0.14

        if level > 0.001 || twist > 0 {
            var bullet = Path()
            bullet.move(to: CGPoint(x: left, y: bottom))
            bullet.addLine(to: CGPoint(x: left, y: top + slant))
            bullet.addLine(to: CGPoint(x: right - tipR, y: top))
            bullet.addQuadCurve(to: CGPoint(x: right, y: top + tipR), control: CGPoint(x: right, y: top))
            bullet.addLine(to: CGPoint(x: right, y: bottom))
            bullet.closeSubpath()
            let br = CGRect(x: left, y: top, width: bw, height: len)
            ctx.fill(bullet, with: horizontal([.init(color: liquidDeep, location: 0),
                                               .init(color: liquid.mixed(with: .white, 0.2), location: 0.3),
                                               .init(color: liquid, location: 0.6),
                                               .init(color: liquidDeep.mixed(with: .black, 0.15), location: 1)], br))
            // 斜切面：更亮的一片
            var face = Path()
            face.move(to: CGPoint(x: left, y: top + slant))
            face.addLine(to: CGPoint(x: right - tipR, y: top))
            face.addQuadCurve(to: CGPoint(x: right, y: top + tipR), control: CGPoint(x: right, y: top))
            face.addLine(to: CGPoint(x: left + bw * 0.1, y: top + slant + bw * 0.08))
            face.closeSubpath()
            ctx.fill(face, with: .color(liquidLight.opacity(0.55)))
            let hl = CGRect(x: left + bw * 0.22, y: top + slant * 0.9, width: max(0.8, bw * 0.1), height: max(1, len - slant))
            ctx.fill(rounded(hl, hl.width / 2), with: vertical([.white.opacity(0.4), .white.opacity(0)], hl))
            ctx.stroke(bullet, with: .color(outlineColor), lineWidth: 0.5)
        }

        // 内套筒：旋出时螺旋纹移动
        let sleeve = p.sleeve
        ctx.fill(Path(sleeve), with: metal(sleeve))
        var spiral = Path()
        let phase = twist * sleeve.height * 0.8
        for i in -1...2 {
            let y = sleeve.minY + sleeve.height * CGFloat(i) * 0.45 + phase.truncatingRemainder(dividingBy: sleeve.height * 0.45)
            spiral.move(to: CGPoint(x: sleeve.minX, y: y + sleeve.height * 0.25))
            spiral.addLine(to: CGPoint(x: sleeve.maxX, y: y))
        }
        var sc = ctx
        sc.clip(to: Path(sleeve))
        sc.stroke(spiral, with: .color(style.material.groove), lineWidth: 0.5)
        ctx.stroke(Path(sleeve), with: .color(outlineColor), lineWidth: 0.4)

        let ring = p.ring
        ctx.fill(rounded(ring, 1), with: metal(ring, style.material == .gold ? CapMaterial.gold : CapMaterial.white))
        ctx.stroke(rounded(ring, 1), with: .color(outlineColor), lineWidth: 0.4)

        // 外壳
        let cr = w * 0.06
        ctx.fill(rounded(base, cr), with: metal(base))
        var groove = Path()
        groove.move(to: CGPoint(x: base.minX, y: base.minY + base.height * 0.18))
        groove.addLine(to: CGPoint(x: base.maxX, y: base.minY + base.height * 0.18))
        ctx.stroke(groove, with: .color(style.material.groove), lineWidth: 0.6)
        let shine = CGRect(x: base.minX + base.width * 0.2, y: base.minY + base.height * 0.24, width: max(1, base.width * 0.07), height: base.height * 0.68)
        ctx.fill(rounded(shine, shine.width / 2), with: vertical([.white.opacity(0.0), style.material.shine, .white.opacity(0.0)], shine))
        topShine(ctx, base, corner: cr)
        ctx.stroke(rounded(base, cr), with: .color(outlineColor), lineWidth: 0.5)
    }

    // MARK: 粉盒

    private func drawCompact(_ ctx: GraphicsContext, _ g: ContainerGeometry, _ r: CGRect) {
        let p = g.parts
        let face = p.topFace
        let R = p.lidRadius
        let s = CGFloat(-face.height / max(1, 2 * R)) + (1 + CGFloat(face.height / max(1, 2 * R))) * CGFloat(max(0, min(1, pose.lidOpen)))

        // 镜面盖（打开时立在后面）
        if s >= 0 {
            drawCompactLid(ctx, center: r.midX, hinge: p.hingeY, R: R, scaleY: s, mirror: true)
        }

        // 底座侧面
        let bottomEllipse = CGRect(x: face.minX, y: g.capRect.maxY - face.height, width: face.width, height: face.height)
        var side = Path()
        side.addRect(CGRect(x: face.minX, y: face.midY, width: face.width, height: bottomEllipse.midY - face.midY))
        side.addEllipse(in: bottomEllipse)
        ctx.fill(side, with: metal(face))
        ctx.stroke(Path(ellipseIn: bottomEllipse), with: .color(outlineColor), lineWidth: 0.5)
        // 顶面
        ctx.fill(Path(ellipseIn: face), with: .linearGradient(Gradient(stops: style.material.stops),
                                                             startPoint: CGPoint(x: face.minX, y: face.minY),
                                                             endPoint: CGPoint(x: face.maxX, y: face.maxY)))
        ctx.stroke(Path(ellipseIn: face), with: .color(outlineColor), lineWidth: 0.5)

        // 粉饼：越用中间的"坑"越大，露出金属底盘
        let pan = p.pan
        ctx.fill(Path(ellipseIn: pan.insetBy(dx: -1, dy: -0.6)), with: .color(.black.opacity(0.25)))
        ctx.fill(Path(ellipseIn: pan), with: .radialGradient(Gradient(colors: [liquidLight, liquid, liquidDeep]),
                                                             center: CGPoint(x: pan.midX - pan.width * 0.15, y: pan.midY - pan.height * 0.2),
                                                             startRadius: 0, endRadius: pan.width * 0.6))
        var pc = ctx
        pc.clip(to: Path(ellipseIn: pan))
        for k in 1...3 {
            let rr = pan.insetBy(dx: pan.width * 0.1 * CGFloat(k), dy: pan.height * 0.1 * CGFloat(k))
            pc.stroke(Path(ellipseIn: rr), with: .color(.white.opacity(0.12)), lineWidth: 0.5)
        }
        let worn = CGFloat(1 - max(0, min(1, level)))
        if worn > 0.02 {
            let hole = CGRect(x: pan.midX - pan.width * 0.44 * worn, y: pan.midY - pan.height * 0.4 * worn,
                              width: pan.width * 0.88 * worn, height: pan.height * 0.8 * worn)
            pc.fill(Path(ellipseIn: hole), with: .linearGradient(Gradient(stops: CapMaterial.white.stops),
                                                                startPoint: CGPoint(x: hole.minX, y: hole.minY),
                                                                endPoint: CGPoint(x: hole.maxX, y: hole.maxY)))
            pc.stroke(Path(ellipseIn: hole), with: .color(liquidDeep.opacity(0.5)), lineWidth: 0.8)
        }

        // 盖子合上时盖在顶面上
        if s < 0 {
            drawCompactLid(ctx, center: r.midX, hinge: p.hingeY, R: R, scaleY: s, mirror: false)
        }
        // 铰链
        let hinge = CGRect(x: r.midX - R * 0.35, y: p.hingeY - max(1.5, R * 0.08), width: R * 0.7, height: max(2, R * 0.12))
        ctx.fill(rounded(hinge, hinge.height / 2), with: metal(hinge))
    }

    private func drawCompactLid(_ ctx: GraphicsContext, center: CGFloat, hinge: CGFloat, R: CGFloat, scaleY: CGFloat, mirror: Bool) {
        let hgt = 2 * R * abs(scaleY)
        guard hgt > 0.5 else { return }
        let rect = mirror
            ? CGRect(x: center - R, y: hinge - hgt, width: 2 * R, height: hgt)
            : CGRect(x: center - R, y: hinge, width: 2 * R, height: hgt)
        ctx.fill(Path(ellipseIn: rect), with: metal(rect))
        if mirror {
            let m = rect.insetBy(dx: R * 0.12, dy: hgt * 0.06)
            ctx.fill(Path(ellipseIn: m), with: .linearGradient(Gradient(colors: [Color(hex: "E9EEF3"), Color(hex: "AEB7C1"), Color(hex: "D9DFE6")]),
                                                               startPoint: CGPoint(x: m.minX, y: m.minY),
                                                               endPoint: CGPoint(x: m.maxX, y: m.maxY)))
            // 镜面里映出一点粉的颜色
            ctx.fill(Path(ellipseIn: m), with: .color(liquid.opacity(0.12)))
            var mc = ctx
            mc.clip(to: Path(ellipseIn: m))
            let shift = CGFloat(frame.angle) * m.width * 0.2
            var streak = Path()
            streak.move(to: CGPoint(x: m.minX + m.width * 0.15 + shift, y: m.maxY))
            streak.addLine(to: CGPoint(x: m.minX + m.width * 0.55 + shift, y: m.minY))
            streak.addLine(to: CGPoint(x: m.minX + m.width * 0.72 + shift, y: m.minY))
            streak.addLine(to: CGPoint(x: m.minX + m.width * 0.32 + shift, y: m.maxY))
            streak.closeSubpath()
            mc.fill(streak, with: .color(.white.opacity(0.55)))
            ctx.stroke(Path(ellipseIn: m), with: .color(.black.opacity(0.12)), lineWidth: 0.5)
        } else {
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: R * 0.3, dy: hgt * 0.25)), with: .color(style.material.shine.opacity(0.4)))
        }
        ctx.stroke(Path(ellipseIn: rect), with: .color(outlineColor), lineWidth: 0.5)
    }
}
