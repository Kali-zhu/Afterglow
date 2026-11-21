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

/// 有厚度的一条架板
struct ShelfPlank: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.shelf)
            .frame(height: 6)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 3)
            .accessibilityHidden(true)
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
