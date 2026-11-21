import SwiftUI

/// 瓶身轮廓：瓶盖 + 瓶肩 + 圆角瓶体。整个 App 唯一"大胆"的元素就是它。
struct BottleShape: Shape {
    var capRatio: CGFloat = 0.16
    func path(in r: CGRect) -> Path {
        var p = Path()
        let capH = r.height * capRatio
        let capW = r.width * 0.42
        let neckH = r.height * 0.05
        p.addRoundedRect(in: CGRect(x: r.midX - capW / 2, y: r.minY, width: capW, height: capH),
                         cornerSize: CGSize(width: 5, height: 5), style: .continuous)
        p.addRoundedRect(in: CGRect(x: r.midX - capW * 0.4, y: r.minY + capH, width: capW * 0.8, height: neckH),
                         cornerSize: .zero)
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY + capH + neckH, width: r.width,
                                    height: r.height - capH - neckH),
                         cornerSize: CGSize(width: r.width * 0.22, height: r.width * 0.22), style: .continuous)
        return p
    }
    /// 只有瓶体（用来装液体）
    static func body(in r: CGRect, capRatio: CGFloat = 0.16) -> CGRect {
        let top = r.height * capRatio + r.height * 0.05
        return CGRect(x: r.minX, y: r.minY + top, width: r.width, height: r.height - top)
    }
}

struct WaveShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { .init(level, phase) }
        set { level = newValue.first; phase = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.height * (1 - level)
        p.move(to: CGPoint(x: 0, y: y))
        for x in stride(from: 0, through: rect.width, by: 2) {
            p.addLine(to: CGPoint(x: x, y: y + sin(x / rect.width * .pi * 2 + phase) * amplitude))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// 玻璃瓶 + 晃动液面。液面高度 = 剩余量。
/// `slosh` 每变化一次，液面会被"晃"一下（用于记录使用后的反馈）。
struct LiquidBottle: View {
    let level: Double
    let tint: Color
    var slosh: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var energy: Double = 0

    var body: some View {
        GeometryReader { geo in
            let full = CGRect(origin: .zero, size: geo.size)
            let bodyRect = BottleShape.body(in: full)
            TimelineView(.animation(paused: reduceMotion)) { tl in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    BottleShape().fill(.ultraThinMaterial)
                    ZStack {
                        WaveShape(level: level, phase: t * 1.4, amplitude: 2 + energy * 6)
                            .fill(tint.opacity(0.5))
                        WaveShape(level: level, phase: t * 1.9 + 1.2, amplitude: 1.5 + energy * 4)
                            .fill(tint)
                    }
                    .frame(width: bodyRect.width, height: bodyRect.height)
                    .offset(y: bodyRect.minY)
                    .clipShape(BottleShape())
                    // 玻璃的竖向反光：静止，不做循环扫光
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: max(3, geo.size.width * 0.06), height: bodyRect.height * 0.5)
                        .offset(x: geo.size.width * 0.14, y: bodyRect.minY + bodyRect.height * 0.15)
                        .blendMode(.plusLighter)
                    BottleShape().stroke(.white.opacity(0.55), lineWidth: 1)
                }
            }
        }
        .animation(Theme.spring, value: level)
        .onChange(of: slosh) {
            guard !reduceMotion else { return }
            energy = 1
            withAnimation(.easeOut(duration: 1.4)) { energy = 0 }
        }
        .accessibilityElement()
        .accessibilityLabel("剩余 \(Int(level * 100))%")
    }
}
