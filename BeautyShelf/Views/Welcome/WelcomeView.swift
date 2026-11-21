import SwiftUI

/// 首次打开：一个瓶子缓缓注满，"把梳妆台搬进手机"。
struct WelcomeView: View {
    var onAddFirst: () -> Void
    var onSamples: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var level: Double = 0
    @State var showText = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            ContainerView(kind: .bottle, level: level, tint: Color(hex: Theme.liquids[0]))
                .frame(width: 120, height: 196)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("把梳妆台搬进手机")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("每一瓶还剩多少、什么时候过期，一眼就知道。\n每天点一下，就记好了。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(showText ? 1 : 0)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                Button(action: onAddFirst) {
                    Text("添加第一件")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))

                Button(action: onSamples) {
                    Text("先看看示例")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityHint("放入一些示例产品，之后可在设置里一键清除")
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.porcelain.ignoresSafeArea())
        .onAppear {
            if reduceMotion {
                level = 0.72
                showText = true
            } else {
                withAnimation(.easeInOut(duration: 2.4)) { level = 0.72 }
                withAnimation(.easeOut(duration: 0.6).delay(0.5)) { showText = true }
            }
        }
    }
}
