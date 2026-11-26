import SwiftUI

/// 会自动换行的胶囊排布（支持动态字体放大后换行）
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: maxW.isFinite ? maxW : nil, height: nil))
            if x > 0 && x + size.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? maxW : widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

/// 单选胶囊（分类、容量、日期……），≥ 44pt 高
struct ChoiceChip: View {
    let title: String
    var systemImage: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .foregroundStyle(isOn ? Color(uiColor: .systemBackground) : Color.primary)
            .background(Capsule().fill(isOn ? Color.primary : Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 记录使用时从上方落下的一滴液体
struct FallingDrop: View {
    let tint: Color
    let trigger: Int
    var distance: CGFloat = 40
    var size: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var y: CGFloat = 0
    @State var visible = false

    var body: some View {
        DropShape()
            .fill(tint)
            .frame(width: size, height: size * 1.35)
            .offset(y: y)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: trigger) {
                guard !reduceMotion else { return }
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) {
                    y = 0
                    visible = true
                }
                withAnimation(.easeIn(duration: 0.42)) {
                    y = distance
                } completion: {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) {
                        visible = false
                        y = 0
                    }
                }
            }
    }
}

/// 今日进度环：全部完成时合拢并出现对勾
struct ProgressRing: View {
    let progress: Double
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(Theme.sage, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress >= 1 {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.sage)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .animation(Theme.spring, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress >= 1 ? "今日流程全部完成" : "今日进度 \(Int((progress * 100).rounded()))%")
    }
}

/// v1.0 架板：浅色磨砂玻璃。顶面亮、细细一道高光边，正面带一点玻璃断面的青绿，下方一层柔和的投影。
/// 光从左上来（`Theme.Light`）：前缘高光偏暖，投影往下偏右一点点。
struct ShelfPlank: View {
    @Environment(\.colorScheme) private var scheme
    static let height: CGFloat = 12
    /// 顶面（物件站立的那一面）的深度
    static let surface: CGFloat = 5

    var body: some View {
        let dark = scheme == .dark
        VStack(spacing: 0) {
            // 顶面：从上往下看到的那一条
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(LinearGradient(colors: [Theme.plankSurface.opacity(dark ? 0.18 : 0.75),
                                                 Theme.plankSurface.opacity(dark ? 0.08 : 0.35)],
                                        startPoint: .top, endPoint: .bottom))
                .frame(height: Self.surface)
            // 前缘高光线：暖白，不是死白
            Rectangle()
                .fill(Theme.Light.highlight.opacity(dark ? 0.4 : 0.95))
                .frame(height: 0.75)
            // 正面：玻璃断面
            Rectangle()
                .fill(.thinMaterial)
                .overlay(LinearGradient(colors: [Theme.plankEdge.opacity(dark ? 0.55 : 0.7),
                                                 Theme.plankEdge.opacity(dark ? 0.25 : 0.35)],
                                        startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(dark ? 0.4 : 0.08)).frame(height: 0.5)
                }
                .frame(height: Self.height - Self.surface - 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        .background(alignment: .top) {
            // 架板下方的深度投影：往右下偏一点，和接触阴影同方向
            LinearGradient(colors: [Theme.plankShadow.opacity(dark ? 0.55 : 0.13), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
                .blur(radius: 3)
                .offset(x: 3, y: Self.height + 1)
                .padding(.horizontal, 6)
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

/// 物件和架子之间的接触阴影：一层紧贴的深影 + 一层柔和的环境影。
/// 影子往右下偏（光从左上来），这两层是"物件真的站在架板上"的关键。
struct ContactShadow: View {
    var width: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Ellipse()
                .fill(Theme.Light.contactCore.opacity(dark ? Theme.Light.contactAmbientOpacityDark
                                                           : Theme.Light.contactAmbientOpacity))
                .frame(width: width * 1.15, height: 10)
                .blur(radius: 5)
            Ellipse()
                .fill(Theme.Light.contactCore.opacity(dark ? Theme.Light.contactCoreOpacityDark
                                                           : Theme.Light.contactCoreOpacity))
                .frame(width: width * 0.78, height: 4)
                .blur(radius: 1.8)
                .offset(x: width * Theme.Light.shadowShift)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 透明有色玻璃在架板上投下的彩色焦散光：光穿过瓶子后往右折出去，落在影子边上
struct CausticGlow: View {
    var tint: Color
    var width: CGFloat
    var strength: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Ellipse()
            .fill(RadialGradient(colors: [tint.opacity(0.9), tint.opacity(0.35), tint.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: width * 0.6))
            .frame(width: width * 1.2, height: 12)
            .scaleEffect(x: 1, y: 0.8)
            .offset(x: width * Theme.Light.causticShift)
            .opacity((scheme == .dark ? 0.55 : 0.45) * strength)
            .blendMode(scheme == .dark ? .plusLighter : .normal)
            .blur(radius: 1.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 名字前的小圆点：只在快到期 / 已过期 / 剩余不多时出现
enum ShelfStatus {
    case expired, soon, low

    static func of(_ p: Product) -> ShelfStatus? {
        switch p.expiryState {
        case .expired: return .expired
        case .soon: return .soon
        case .fresh: return p.isLow ? .low : nil
        }
    }

    var color: Color {
        switch self {
        case .expired: Theme.rouge
        case .soon: Theme.honey
        case .low: Theme.low
        }
    }

    var spoken: String {
        switch self {
        case .expired: "已过期"
        case .soon: "快到期"
        case .low: "快用完了"
        }
    }
}

struct StatusDot: View {
    let status: ShelfStatus
    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 用一次时的粒子反馈：液滴（下落）、喷雾（向外扩散）、粉雾（向上飘散）
struct UseEmission: View {
    enum Kind { case drop, mist, puff, none }
    var kind: Kind
    var tint: Color
    var trigger: Int
    /// 发射点（本视图坐标系）
    var origin: CGPoint
    var direction: CGVector = CGVector(dx: 0, dy: 1)
    /// 液滴落下的距离
    var fall: CGFloat = 80
    var scale: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date? = nil

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            Canvas { ctx, _ in
                guard let start else { return }
                let t = tl.date.timeIntervalSince(start)
                draw(ctx, t: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            guard !reduceMotion, kind != .none else { return }
            let now = Date.now
            start = now
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1000))
                if start == now { start = nil }
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, t: Double) {
        let T = CGFloat(t)
        switch kind {
        case .drop:
            guard t < 0.75 else { return }
            let dur: CGFloat = 0.6
            let k = min(1, T / dur)
            let s = 7 * scale
            let x = origin.x + direction.dx * 14 * scale * k
            let y = origin.y + direction.dy * 6 * scale * k + fall * k * k
            let a = Double(1 - max(0, (T - dur) / 0.15))
            var c = ctx
            c.opacity = a
            let rect = CGRect(x: x - s / 2, y: y - s * 0.35, width: s, height: s * 1.35)
            c.fill(DropShape().path(in: rect), with: .color(tint))
            c.fill(Path(ellipseIn: CGRect(x: rect.minX + s * 0.25, y: rect.minY + s * 0.55, width: s * 0.22, height: s * 0.3)),
                   with: .color(.white.opacity(0.7)))
        case .mist:
            guard t < 0.9 else { return }
            for i in 0..<14 {
                let seed = Double(i) * 1.618
                let spread = (seed.truncatingRemainder(dividingBy: 1) - 0.5) * 0.9
                let speed = 50 + 40 * ((seed * 3.1).truncatingRemainder(dividingBy: 1))
                let ang = atan2(Double(direction.dy), Double(direction.dx)) + spread
                let d = CGFloat(speed * t) * scale
                let p = CGPoint(x: origin.x + CGFloat(cos(ang)) * d, y: origin.y + CGFloat(sin(ang)) * d - CGFloat(t * t * 10))
                let r = (1.2 + T * 5) * scale
                var c = ctx
                c.opacity = max(0, 0.55 - t * 0.6)
                c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                       with: .color(tint.mixed(with: .white, 0.6)))
            }
        case .puff:
            guard t < 1.0 else { return }
            for i in 0..<12 {
                let seed = Double(i) * 2.399
                let ang = -Double.pi / 2 + sin(seed) * 1.2
                let d = CGFloat(20 + 30 * t) * scale * CGFloat(0.6 + 0.4 * abs(cos(seed)))
                let p = CGPoint(x: origin.x + CGFloat(cos(ang)) * d, y: origin.y + CGFloat(sin(ang)) * d)
                let r = (2 + T * 7) * scale
                var c = ctx
                c.opacity = max(0, 0.45 - t * 0.45)
                c.addFilter(.blur(radius: 2))
                c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(tint))
            }
        case .none:
            break
        }
    }
}

/// 各标签页导航栏上的设置按钮
struct SettingsButton: View {
    @Environment(AppCoordinator.self) var coordinator
    var body: some View {
        Button { coordinator.showSettings = true } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("设置")
    }
}

/// 保质期状态的小圆点
struct ExpiryDot: View {
    let state: ExpiryState
    var body: some View {
        if state != .fresh {
            Circle().fill(state.color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Theme.porcelain, lineWidth: 2))
                .accessibilityHidden(true)
        }
    }
}
