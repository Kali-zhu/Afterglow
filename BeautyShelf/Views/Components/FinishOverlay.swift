import SwiftUI
import UIKit

/// "用完了"：实物倾倒，剩余量流干（抠图上磨砂区域一路漫到底），
/// 扶正后显示"用完啦"，然后缩小飘向底部「空瓶」标签。
struct FinishOverlay: View {
    let product: Product
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var level: Double
    @State private var tilt: Double = 0
    @State private var slosh = 0
    @State private var showText = false
    @State private var travel = false
    @State private var dim: Double = 0
    @State private var completed = false

    init(product: Product, done: @escaping () -> Void) {
        self.product = product
        self.done = done
        _level = State(initialValue: max(product.level, 0.14))
    }

    private var heroSize: CGSize {
        product.cutout != nil ? CGSize(width: 190, height: 220) : CGSize(width: 124, height: 202)
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.42)
            let target = tabTarget(in: geo.size)
            ZStack {
                Rectangle().fill(.regularMaterial)
                    .opacity(dim)

                ContainerView(product: product, level: level, slosh: slosh, animated: !reduceMotion)
                    .frame(width: heroSize.width, height: heroSize.height)
                    .rotationEffect(.degrees(tilt), anchor: .bottomLeading)
                    .scaleEffect(travel ? 0.14 : 1)
                    .opacity(travel ? 0 : 1)
                    .position(travel ? target : center)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("用完啦").font(.title2.weight(.bold))
                    Text("「\(product.name)」移入空瓶")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .opacity(showText ? 1 : 0)
                .position(x: center.x, y: center.y + heroSize.height / 2 + 56)
                .accessibilityElement(children: .combine)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(!travel)
        .sensoryFeedback(.success, trigger: completed)
        .task { await run() }
    }

    /// 底部标签栏上「空瓶」图标的大致位置（第三个标签）
    private func tabTarget(in size: CGSize) -> CGPoint {
        let bottomInset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
        let y = size.height - bottomInset - 49 + 18
        if sizeClass == .regular {
            // iPad 的标签挤在中间
            return CGPoint(x: size.width / 2 + 110, y: y)
        }
        return CGPoint(x: size.width * 5 / 6, y: y)
    }

    private func run() async {
        if reduceMotion {
            dim = 1
            level = 0
            showText = true
            completed = true
            try? await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeOut(duration: 0.25)) {
                travel = true
                dim = 0
                showText = false
            }
            try? await Task.sleep(for: .milliseconds(250))
            done()
            return
        }
        withAnimation(.easeOut(duration: 0.25)) { dim = 1 }
        try? await Task.sleep(for: .milliseconds(150))
        // 倾倒：略带回弹地倒向一侧
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { tilt = -68 }
        slosh += 1
        try? await Task.sleep(for: .milliseconds(260))
        // 流干：磨砂 / 空的部分一路漫到底
        withAnimation(.easeIn(duration: 1.0)) { level = 0 }
        try? await Task.sleep(for: .milliseconds(1050))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            tilt = 0
            showText = true
        }
        completed = true
        try? await Task.sleep(for: .milliseconds(800))
        // 飘向「空瓶」标签
        withAnimation(.easeInOut(duration: 0.62)) {
            travel = true
            showText = false
            dim = 0
        }
        try? await Task.sleep(for: .milliseconds(640))
        done()
    }
}
