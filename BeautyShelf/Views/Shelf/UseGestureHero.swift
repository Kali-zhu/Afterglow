import SwiftUI

/// 详情页的"实物"：按形状用真实的动作记一次使用。
/// - 瓶（泵 / 滴管 / 喷头）：按下盖子，盖子压缩，出一滴或一团喷雾
/// - 管：左右捏（或双指捏合）管身，松手弹回
/// - 罐：旋转手势或画圈拧开盖子，盖子抬起再落回
/// - 面膜：从右上角往下拖，揭起最上一片，它飞走
/// - 口红：向上拖，旋出膏体
/// - 粉盒：轻点，盖子"啪"地合上再打开，扬起一点粉
/// - 有抠图（或其他瓶盖）时：按住压扁 + 一滴
/// 每个动作都会记一次使用并触感反馈；同时保留"用了一次"按钮与 VoiceOver 的自定义操作。
struct UseGestureHero: View {
    let product: Product
    let size: CGSize
    /// 记录使用后液面晃一下
    var slosh: Int
    /// 外部（"用了一次"按钮）触发时自动演示一遍动作，不重复记录
    var demoTrigger: Int
    /// 手势完成一次使用
    var onUse: () -> Void

    enum Mode { case capPress, press, squeeze, unscrew, peel, twist, tapLid }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pose = VesselPose.rest
    @State private var emits = 0
    @State private var isDown = false
    @State private var turn: Double = 0
    @State private var lastAngle: Double? = nil
    @State private var unscrewed = false
    @State private var busy = false

    /// 粒子画布比容器大一圈，让液滴能落到容器外
    private let pad = CGSize(width: 90, height: 110)

    var mode: Mode { Self.mode(for: product) }
    var hint: String { Self.hint(for: product) }

    static func mode(for product: Product) -> Mode {
        if product.cutout != nil { return .press }
        switch product.kind {
        case .bottle:
            switch product.capStyle {
            case .pump, .dropper, .spray: return .capPress
            default: return .press
            }
        case .tube: return .squeeze
        case .jar: return .unscrew
        case .sheet: return .peel
        case .stick: return .twist
        case .compact: return .tapLid
        }
    }

    /// 给用户的一句提示
    static func hint(for product: Product) -> String {
        switch mode(for: product) {
        case .capPress:
            switch product.capStyle {
            case .dropper: return "捏一下滴管，记一次"
            case .spray: return "按一下喷头，记一次"
            default: return "按一下泵头，记一次"
            }
        case .press: return "按住它，记一次"
        case .squeeze: return "左右捏一下管身，记一次"
        case .unscrew: return "画圈拧开盖子，记一次"
        case .peel: return "从右上角往下揭一片，记一次"
        case .twist: return "向上拖，旋出膏体"
        case .tapLid: return "轻点粉盒，记一次"
        }
    }

    var body: some View {
        let emit = ContainerView.emitPoint(for: product, in: size)
        ZStack {
            // 详情页大图用实物模式：整张抠图，液面画在实物上
            ContainerView(product: product, slosh: slosh, pose: pose, wholeCutout: true)
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)
            UseEmission(kind: emissionKind, tint: product.tint, trigger: emits,
                        origin: CGPoint(x: emit.point.x + pad.width, y: emit.point.y + pad.height),
                        direction: emit.direction,
                        fall: fallDistance(from: emit.point),
                        scale: max(0.8, size.width / 150))
                .frame(width: size.width + pad.width * 2, height: size.height + pad.height * 2)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(gesture, including: product.isFinished ? .subviews : .all)
        .onChange(of: demoTrigger) { demo() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(product.name)
        .accessibilityValue(product.remainingText)
        .accessibilityHint(hint)
        .accessibilityAction(named: "用了一次") { if !product.isFinished { onUse() } }
    }

    private var emissionKind: UseEmission.Kind {
        switch mode {
        case .capPress: return product.capStyle == .spray ? .mist : .drop
        case .press, .squeeze: return .drop
        case .tapLid: return .puff
        case .unscrew, .peel, .twist: return .none
        }
    }

    private func fallDistance(from p: CGPoint) -> CGFloat {
        if mode == .capPress, product.capStyle == .dropper, product.cutout == nil {
            // 滴进瓶里：落到液面
            let g = ContainerGeometry.make(product.kind, cap: product.capStyle, in: CGRect(origin: .zero, size: size))
            return max(10, LiquidMath.baseY(region: g.liquidRect, level: product.level) - p.y)
        }
        if mode == .press { return size.height * 0.5 }
        return size.height * 0.4
    }

    // MARK: 动画

    private var spring: Animation? { reduceMotion ? .easeInOut(duration: 0.15) : Theme.springBack }
    private var press: Animation? { reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.22, dampingFraction: 0.7) }

    private func setDirect(_ change: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, change)
    }

    private func didUse() {
        onUse()
        emits += 1
    }

    // MARK: 手势

    private var gesture: AnyGesture<Void> {
        switch mode {
        case .capPress, .press: return pressGesture
        case .squeeze: return squeezeGesture
        case .unscrew: return unscrewGesture
        case .peel: return peelGesture
        case .twist: return twistGesture
        case .tapLid: return AnyGesture(TapGesture().onEnded { tapLid(log: true) })
        }
    }

    /// 按下：盖子 / 整体压下去；松手：弹回 + 记一次（拖得太远视为取消）
    private var pressGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDown else { return }
                    isDown = true
                    withAnimation(press) { pose.capPress = 1 }
                }
                .onEnded { v in
                    isDown = false
                    withAnimation(spring) { pose.capPress = 0 }
                    if hypot(v.translation.width, v.translation.height) < 30 { didUse() }
                }
                .map { _ in () }
        )
    }

    private var squeezeGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 4)
                .simultaneously(with: MagnifyGesture())
                .onChanged { v in
                    var s: Double = 0
                    if let d = v.first { s = max(s, Double(abs(d.translation.width) / (size.width * 0.45))) }
                    if let m = v.second { s = max(s, Double((1 - m.magnification) * 2.5)) }
                    let clamped = max(0, min(1, s))
                    setDirect { pose.squeeze = clamped }
                }
                .onEnded { _ in
                    let used = pose.squeeze > 0.35
                    withAnimation(spring) { pose.squeeze = 0 }
                    if used { didUse() }
                }
                .map { _ in () }
        )
    }

    private var unscrewGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 2)
                .simultaneously(with: RotateGesture())
                .onChanged { v in
                    guard !unscrewed else { return }
                    if let r = v.second {
                        turn = r.rotation.radians
                    } else if let d = v.first {
                        let c = CGPoint(x: size.width / 2, y: size.height * 0.6)
                        let a = atan2(Double(d.location.y - c.y), Double(d.location.x - c.x))
                        if let last = lastAngle {
                            var delta = a - last
                            if delta > .pi { delta -= 2 * .pi }
                            if delta < -.pi { delta += 2 * .pi }
                            turn += delta
                        }
                        lastAngle = a
                    }
                    let t = turn
                    setDirect { pose.lidTurn = t }
                    if abs(turn) > 2.1 { liftLid(log: true) }
                }
                .onEnded { _ in
                    lastAngle = nil
                    if !unscrewed {
                        turn = 0
                        withAnimation(spring) { pose.lidTurn = 0 }
                    }
                }
                .map { _ in () }
        )
    }

    private var peelGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    guard !busy else { return }
                    let p = max(0, min(1, Double((v.translation.height - v.translation.width * 0.5) / (size.height * 0.5))))
                    setDirect { pose.peel = p }
                }
                .onEnded { _ in
                    guard !busy else { return }
                    if pose.peel > 0.45 {
                        flySheet(log: true)
                    } else {
                        withAnimation(spring) { pose.peel = 0 }
                    }
                }
                .map { _ in () }
        )
    }

    private var twistGesture: AnyGesture<Void> {
        AnyGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    let t = max(0, min(1, Double(-v.translation.height / (size.height * 0.35))))
                    setDirect { pose.twist = t }
                }
                .onEnded { _ in
                    let used = pose.twist > 0.5
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.8)) {
                        pose.twist = 0
                    }
                    if used { didUse() }
                }
                .map { _ in () }
        )
    }

    // MARK: 组合动作

    private func liftLid(log: Bool) {
        guard !unscrewed else { return }
        unscrewed = true
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.62)) {
            pose.lidLift = 1
        }
        if log { didUse() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.75)) {
                pose.lidLift = 0
                pose.lidTurn = 0
            }
            turn = 0
            unscrewed = false
        }
    }

    private func flySheet(log: Bool) {
        busy = true
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .easeIn(duration: 0.38)) {
            pose.peel = 1
            pose.fly = 1
        } completion: {
            if log { didUse() }
            setDirect {
                pose.peel = 0
                pose.fly = 0
            }
            busy = false
        }
    }

    private func tapLid(log: Bool) {
        guard !busy else { return }
        busy = true
        withAnimation(reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.22, dampingFraction: 0.9)) {
            pose.lidOpen = 0
        } completion: {
            if log { didUse() } else { emits += 1 }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.62)) {
                pose.lidOpen = 1
            } completion: {
                busy = false
            }
        }
    }

    /// "用了一次"按钮：把这个形状的动作演示一遍（已经记过了，不再记录）
    private func demo() {
        switch mode {
        case .capPress, .press:
            withAnimation(press) { pose.capPress = 1 } completion: {
                withAnimation(spring) { pose.capPress = 0 }
                emits += 1
            }
        case .squeeze:
            withAnimation(press) { pose.squeeze = 0.7 } completion: {
                withAnimation(spring) { pose.squeeze = 0 }
                emits += 1
            }
        case .unscrew:
            withAnimation(.easeInOut(duration: 0.35)) { pose.lidTurn = 2.2 } completion: {
                liftLid(log: false)
            }
        case .peel:
            guard !busy else { return }
            flySheet(log: false)
        case .twist:
            withAnimation(.easeOut(duration: 0.3)) { pose.twist = 0.8 } completion: {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { pose.twist = 0 }
            }
        case .tapLid:
            tapLid(log: false)
        }
    }
}
