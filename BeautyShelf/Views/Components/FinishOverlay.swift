import SwiftUI

/// "用完了"：容器倾斜、液体倒空，然后移入空瓶墙。
struct FinishOverlay: View {
    let product: Product
    let done: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var level: Double
    @State private var tilt: Double = 0
    @State private var pouring = false
    @State private var showText = false
    @State private var completed = false

    init(product: Product, done: @escaping () -> Void) {
        self.product = product
        self.done = done
        _level = State(initialValue: max(product.level, 0.12))
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack(alignment: .topLeading) {
                    // 倒出的液流
                    Capsule()
                        .fill(product.tint)
                        .frame(width: 8, height: 180)
                        .scaleEffect(x: 1, y: pouring ? 1 : 0, anchor: .top)
                        .opacity(pouring ? 0.85 : 0)
                        .offset(x: -6, y: 40)
                    ContainerView(kind: product.kind, level: level, tint: product.tint,
                                  photo: product.photo, photoKey: product.uid.uuidString,
                                  badge: nil, animated: !reduceMotion)
                        .frame(width: 120, height: 196)
                        .rotationEffect(.degrees(tilt), anchor: .bottomTrailing)
                }
                .frame(width: 160, height: 240)
                .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("用完啦").font(.title2.weight(.bold))
                    Text("「\(product.name)」移入空瓶墙")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showText ? 1 : 0)
                .accessibilityElement(children: .combine)
            }
            .padding(32)
        }
        .sensoryFeedback(.success, trigger: completed)
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            level = 0
            showText = true
            completed = true
            try? await Task.sleep(for: .milliseconds(900))
            done()
            return
        }
        withAnimation(.easeInOut(duration: 0.45)) { tilt = -38 }
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.easeOut(duration: 0.25)) { pouring = true }
        withAnimation(.easeIn(duration: 0.9)) { level = 0 }
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.easeOut(duration: 0.25)) { pouring = false }
        withAnimation(Theme.spring) {
            tilt = 0
            showText = true
        }
        completed = true
        try? await Task.sleep(for: .milliseconds(850))
        done()
    }
}
