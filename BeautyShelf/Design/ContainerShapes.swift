import SwiftUI

/// 容器家族的几何：每种形状拆成三部分
/// - glass：半透明的附属部分（瓶颈、面膜袋后面那几片、粉盒镜面……），画在最底层
/// - solid：实心部件（瓶盖、罐盖、管盖、口红外壳、粉盒底座）
/// - vessel：装"液体"的那部分，液面在这里面晃动
/// 所有形状都在同一个矩形里按比例绘制，架子上 64×104，详情页 150×244。
struct ContainerGeometry {
    var glass = Path()
    var solid = Path()
    var vessel = Path()
    var vesselRect: CGRect = .zero
    var labelCenter: CGPoint = .zero
    var labelDiameter: CGFloat = 0
    var badgeCenter: CGPoint = .zero

    static func make(_ kind: VesselKind, in r: CGRect) -> ContainerGeometry {
        var g = ContainerGeometry()
        let w = r.width, h = r.height
        guard w > 0, h > 0 else { return g }

        switch kind {
        case .bottle:
            // 瓶盖 + 瓶颈 + 圆角瓶体
            let capH = h * 0.16, capW = w * 0.42, neckH = h * 0.05
            g.solid.addRoundedRect(in: CGRect(x: r.midX - capW / 2, y: r.minY, width: capW, height: capH),
                                   cornerSize: CGSize(width: capW * 0.16, height: capW * 0.16), style: .continuous)
            g.glass.addRect(CGRect(x: r.midX - capW * 0.4, y: r.minY + capH, width: capW * 0.8, height: neckH))
            let body = CGRect(x: r.minX, y: r.minY + capH + neckH, width: w, height: h - capH - neckH)
            g.vessel.addRoundedRect(in: body, cornerSize: CGSize(width: w * 0.22, height: w * 0.22), style: .continuous)
            g.vesselRect = body
            g.labelCenter = CGPoint(x: body.midX, y: body.midY + body.height * 0.06)
            g.labelDiameter = w * 0.6

        case .jar:
            // 宽而矮：厚盖 + 罐身
            let lidH = h * 0.13, bodyH = h * 0.44, gap = h * 0.015
            let body = CGRect(x: r.minX + w * 0.03, y: r.maxY - bodyH, width: w * 0.94, height: bodyH)
            let lid = CGRect(x: r.minX, y: body.minY - gap - lidH, width: w, height: lidH)
            g.solid.addRoundedRect(in: lid, cornerSize: CGSize(width: w * 0.07, height: w * 0.07), style: .continuous)
            g.vessel.addRoundedRect(in: body, cornerSize: CGSize(width: w * 0.16, height: w * 0.16), style: .continuous)
            g.vesselRect = body
            g.labelCenter = CGPoint(x: body.midX, y: body.midY)
            g.labelDiameter = min(bodyH * 0.72, w * 0.55)

        case .tube:
            // 倒立的软管：盖子在下，压封的尾部在上
            let capH = h * 0.12, capW = w * 0.46
            let cap = CGRect(x: r.midX - capW / 2, y: r.maxY - capH, width: capW, height: capH)
            g.solid.addRoundedRect(in: cap, cornerSize: CGSize(width: capW * 0.14, height: capW * 0.14), style: .continuous)
            let topW = w * 0.94, botW = w * 0.5
            let crimp = CGRect(x: r.midX - topW / 2, y: r.minY + h * 0.02, width: topW, height: h * 0.06)
            g.glass.addRoundedRect(in: crimp, cornerSize: CGSize(width: 2, height: 2), style: .continuous)
            let topY = crimp.maxY, botY = cap.minY
            let bend = (botY - topY) * 0.28
            var p = Path()
            p.move(to: CGPoint(x: r.midX - topW / 2, y: topY))
            p.addLine(to: CGPoint(x: r.midX + topW / 2, y: topY))
            p.addQuadCurve(to: CGPoint(x: r.midX + botW / 2, y: botY),
                           control: CGPoint(x: r.midX + topW / 2, y: botY - bend))
            p.addLine(to: CGPoint(x: r.midX - botW / 2, y: botY))
            p.addQuadCurve(to: CGPoint(x: r.midX - topW / 2, y: topY),
                           control: CGPoint(x: r.midX - topW / 2, y: botY - bend))
            p.closeSubpath()
            g.vessel = p
            g.vesselRect = CGRect(x: r.midX - topW / 2, y: topY, width: topW, height: botY - topY)
            g.labelCenter = CGPoint(x: r.midX, y: topY + (botY - topY) * 0.4)
            g.labelDiameter = w * 0.5

        case .sheet:
            // 一叠面膜袋：后面两片是半透明的，前面一片装"液体"，袋上显示剩余片数
            let front = CGRect(x: r.minX, y: r.maxY - h * 0.7, width: w * 0.84, height: h * 0.7)
            let corner = CGSize(width: w * 0.1, height: w * 0.1)
            g.glass.addRoundedRect(in: front.offsetBy(dx: w * 0.16, dy: -h * 0.1), cornerSize: corner, style: .continuous)
            g.glass.addRoundedRect(in: front.offsetBy(dx: w * 0.08, dy: -h * 0.05), cornerSize: corner, style: .continuous)
            g.vessel.addRoundedRect(in: front, cornerSize: corner, style: .continuous)
            // 撕口：袋子顶部一道短横线
            g.solid.addRoundedRect(in: CGRect(x: front.minX + front.width * 0.3, y: front.minY + front.height * 0.07,
                                              width: front.width * 0.4, height: max(1.5, h * 0.012)),
                                   cornerSize: CGSize(width: 1, height: 1))
            g.vesselRect = front
            g.labelCenter = CGPoint(x: front.midX, y: front.minY + front.height * 0.42)
            g.labelDiameter = front.width * 0.56
            g.badgeCenter = CGPoint(x: front.midX, y: front.maxY - front.height * 0.15)
            return g

        case .stick:
            // 口红：外壳 + 金属环 + 斜切膏体
            let baseH = h * 0.4, baseW = w * 0.6
            let base = CGRect(x: r.midX - baseW / 2, y: r.maxY - baseH, width: baseW, height: baseH)
            g.solid.addRoundedRect(in: base, cornerSize: CGSize(width: w * 0.06, height: w * 0.06), style: .continuous)
            let collarH = h * 0.05, collarW = w * 0.52
            let collar = CGRect(x: r.midX - collarW / 2, y: base.minY - collarH, width: collarW, height: collarH)
            g.glass.addRoundedRect(in: collar, cornerSize: CGSize(width: 1.5, height: 1.5))
            let bw = w * 0.38
            let left = r.midX - bw / 2, right = r.midX + bw / 2
            let top = r.minY + h * 0.05, bottom = collar.minY
            let slant = bw * 0.75, tipR = bw * 0.14
            var p = Path()
            p.move(to: CGPoint(x: left, y: bottom))
            p.addLine(to: CGPoint(x: left, y: top + slant))
            p.addLine(to: CGPoint(x: right - tipR, y: top))
            p.addQuadCurve(to: CGPoint(x: right, y: top + tipR), control: CGPoint(x: right, y: top))
            p.addLine(to: CGPoint(x: right, y: bottom))
            p.closeSubpath()
            g.vessel = p
            g.vesselRect = CGRect(x: left, y: top, width: bw, height: bottom - top)
            g.labelCenter = CGPoint(x: base.midX, y: base.midY)
            g.labelDiameter = min(baseW * 0.72, baseH * 0.62)

        case .compact:
            // 打开的粉盒：镜面盖 + 铰链 + 底座里的粉
            let baseH = h * 0.36
            let base = CGRect(x: r.minX, y: r.maxY - baseH, width: w, height: baseH)
            let hinge = CGRect(x: r.midX - w * 0.2, y: base.minY - h * 0.035, width: w * 0.4, height: h * 0.035)
            let lid = CGRect(x: r.minX + w * 0.05, y: hinge.minY - h * 0.4, width: w * 0.9, height: h * 0.4)
            g.glass.addRoundedRect(in: lid, cornerSize: CGSize(width: w * 0.14, height: w * 0.14), style: .continuous)
            g.solid.addRoundedRect(in: base, cornerSize: CGSize(width: w * 0.16, height: w * 0.16), style: .continuous)
            g.solid.addRect(hinge)
            let pan = base.insetBy(dx: w * 0.12, dy: baseH * 0.17)
            g.vessel.addRoundedRect(in: pan, cornerSize: CGSize(width: w * 0.1, height: w * 0.1), style: .continuous)
            g.vesselRect = pan
            g.labelCenter = CGPoint(x: lid.midX, y: lid.midY)
            g.labelDiameter = min(lid.height * 0.74, lid.width * 0.6)
        }

        g.badgeCenter = CGPoint(x: g.vesselRect.midX, y: g.vesselRect.maxY - g.vesselRect.height * 0.2)
        return g
    }
}

/// 把几何里的某一部分当成 SwiftUI Shape 使用
struct ContainerPart: Shape {
    enum Part { case glass, solid, vessel }
    var kind: VesselKind
    var part: Part

    func path(in rect: CGRect) -> Path {
        let g = ContainerGeometry.make(kind, in: rect)
        switch part {
        case .glass: return g.glass
        case .solid: return g.solid
        case .vessel: return g.vessel
        }
    }
}

/// 晃动的液面。level 可动画（剩余量变化时液面平滑升降）。
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
        var p = Path()
        let lv = min(max(level, 0), 1)
        guard lv > 0.001, region.width > 0 else { return p }
        let y = region.maxY - region.height * CGFloat(lv)
        let amp = CGFloat(amplitude)
        let ph = CGFloat(phase)
        let start = region.minX - 2, end = region.maxX + 2
        func waveY(_ x: CGFloat) -> CGFloat {
            y + sin((x - region.minX) / region.width * .pi * 2 + ph) * amp
        }
        p.move(to: CGPoint(x: start, y: waveY(start)))
        var x = start
        while x <= end {
            p.addLine(to: CGPoint(x: x, y: waveY(x)))
            x += 2
        }
        p.addLine(to: CGPoint(x: end, y: region.maxY + 2))
        p.addLine(to: CGPoint(x: start, y: region.maxY + 2))
        p.closeSubpath()
        return p
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
