import SwiftUI
import UIKit

/// 第 2 步："浮起来"。照片铺在那里，识别完成后主体从背景里升起（放大 1.05 + 投影），背景淡出、变模糊。
struct LiftingStageView: View {
    let photo: UIImage?
    let cutout: ProductCutout?
    /// 主体已经浮起
    let lifted: Bool
    /// 还在识别
    let analyzing: Bool
    let namespace: Namespace.ID
    var matchEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let area = CGRect(x: 20, y: 24, width: max(1, geo.size.width - 40), height: max(1, geo.size.height - 140))
            ZStack(alignment: .topLeading) {
                if let photo {
                    let fit = Self.aspectFit(photo.size, in: area)
                    Image(uiImage: photo)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .blur(radius: lifted ? 18 : 0)
                        .opacity(lifted ? 0.25 : 1)
                        .scaleEffect(lifted && !reduceMotion ? 0.96 : 1)
                        .position(x: fit.midX, y: fit.midY)
                        .accessibilityHidden(true)

                    if analyzing && !reduceMotion {
                        scanLine(in: fit)
                    }

                    if let c = cutout {
                        let r = CGRect(x: fit.minX + c.rect.minX * fit.width,
                                       y: fit.minY + c.rect.minY * fit.height,
                                       width: c.rect.width * fit.width,
                                       height: c.rect.height * fit.height)
                        Image(uiImage: c.image)
                            .resizable()
                            .frame(width: r.width, height: r.height)
                            .subjectMatch(namespace, enabled: matchEnabled && !reduceMotion)
                            .scaleEffect(lifted && !reduceMotion ? 1.05 : 1)
                            .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: lifted ? 24 : 0, y: lifted ? 18 : 0)
                            .offset(y: lifted && !reduceMotion ? -12 : 0)
                            .position(x: r.midX, y: r.midY)
                            .accessibilityHidden(true)
                    }
                }

                caption
                    .frame(width: geo.size.width)
                    .position(x: geo.size.width / 2, y: geo.size.height - 70)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { scanPhase = 1 }
        }
    }

    private var caption: some View {
        let text: String
        if analyzing {
            text = "正在把它从背景里拿出来…"
        } else if cutout != nil {
            text = "拿出来了"
        } else {
            text = "没找到清楚的主体，先用整张照片"
        }
        return HStack(spacing: 8) {
            if analyzing { ProgressView() }
            Text(text).font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .contentTransition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// 识别中：一条柔和的光带上下扫过照片
    private func scanLine(in fit: CGRect) -> some View {
        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .frame(width: fit.width, height: 90)
            .position(x: fit.midX, y: fit.minY + 45 + (fit.height - 90) * scanPhase)
            .blendMode(.plusLighter)
            .mask(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    static func aspectFit(_ size: CGSize, in area: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return area }
        let s = min(area.width / size.width, area.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }
}

extension View {
    /// 主体在"浮起来"和确认卡之间平滑飞过去；减弱动态效果时不做位移，只淡入淡出
    @ViewBuilder
    func subjectMatch(_ ns: Namespace.ID, enabled: Bool) -> some View {
        if enabled {
            matchedGeometryEffect(id: "editor.subject", in: ns)
        } else {
            self
        }
    }
}
