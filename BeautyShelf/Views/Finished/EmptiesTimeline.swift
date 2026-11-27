import SwiftUI

/// 空瓶时间线：把"用完了"按时间排成一条竖线，最近用完的在最上面，按月分段。
///
/// 墙回答"我用空了哪些"，时间线回答"我什么时候用空的、每一件陪了我多久"：
/// 每个节点是一张小玻璃卡，卡里一条细细的"陪伴时长"条（和这一批里最久的那件比），
/// 线上的点取产品自己的液体色。点任意一件打开它的详情（那里可以分享空瓶）。
struct EmptiesTimelineView: View {
    /// 已排好序：最近用完的在前
    let finished: [Product]

    @Environment(AppCoordinator.self) private var coordinator

    /// 一个月一段
    private struct Month: Identifiable {
        let id: String
        let title: String
        let items: [Product]
    }

    private var months: [Month] {
        let cal = Calendar.current
        let nowYear = cal.component(.year, from: .now)
        var result: [Month] = []
        for p in finished {
            guard let d = p.finishedDate else { continue }
            let c = cal.dateComponents([.year, .month], from: d)
            let key = "\(c.year ?? 0)-\(c.month ?? 0)"
            let title = (c.year ?? nowYear) == nowYear ? "\(c.month ?? 0) 月" : "\(c.year ?? 0) 年 \(c.month ?? 0) 月"
            if let last = result.last, last.id == key {
                result[result.count - 1] = Month(id: key, title: title, items: last.items + [p])
            } else {
                result.append(Month(id: key, title: title, items: [p]))
            }
        }
        return result
    }

    /// 这一批里最长的使用天数，陪伴时长条按它归一（只算有开封日期的，和分享卡的口径一致）
    private var longestDays: Int {
        max(1, finished.filter { $0.openedDate != nil }.map(\.usageDays).max() ?? 1)
    }

    var body: some View {
        let sections = months
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { sIndex, month in
                monthHeader(month, isFirst: sIndex == 0)
                ForEach(Array(month.items.enumerated()), id: \.element.uid) { index, p in
                    let isLast = sIndex == sections.count - 1 && index == month.items.count - 1
                    entry(p, isLast: isLast)
                }
            }
        }
    }

    // MARK: 月份标题

    private func monthHeader(_ month: Month, isFirst: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                rail(showAbove: !isFirst, showBelow: true)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.55), lineWidth: 2)
                    .background(Circle().fill(Theme.porcelain))
                    .frame(width: 12, height: 12)
            }
            .frame(width: 14)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(month.title).font(.title3.weight(.semibold))
                Text("\(month.items.count) 件")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40)
        .padding(.top, isFirst ? 0 : 6)
    }

    // MARK: 一个节点

    private func entry(_ p: Product, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                // 最后一件：线只走到它的圆点，不再往下拖一截
                if isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 1.5, height: 28)
                        .accessibilityHidden(true)
                } else {
                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
                Circle()
                    .fill(p.tint.mixed(with: .black, 0.1))
                    .overlay(Circle().strokeBorder(Theme.porcelain, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .padding(.top, 22)
            }
            .frame(width: 14)

            Button { coordinator.openDetail(p) } label: {
                card(p)
            }
            .buttonStyle(ShelfPressStyle())
            .padding(.bottom, 12)
        }
    }

    /// 竖线：穿过整行高度；起点 / 终点那一截可以收掉
    private func rail(showAbove: Bool, showBelow: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(showAbove ? 0.14 : 0))
                .frame(width: 1.5)
            Rectangle()
                .fill(Color.primary.opacity(showBelow ? 0.14 : 0))
                .frame(width: 1.5)
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func card(_ p: Product) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ProductFigure(product: p, maxPixel: 240, level: 0)
                .frame(width: 44, height: 64)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(p.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if let stance = p.repurchase { stanceTag(stance) }
                }

                Text(subtitle(p))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if p.openedDate != nil {
                    durationBar(p)
                }

                Text(detail(p))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: Theme.Radius.control, tint: p.tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(p))
        .accessibilityHint("打开详情")
    }

    /// 品牌 · 用完的日期
    private func subtitle(_ p: Product) -> String {
        var parts: [String] = []
        if !p.brand.isEmpty { parts.append(p.brand) }
        if let d = p.finishedDate { parts.append("\(Fmt.shortDay(d))用完") }
        return parts.joined(separator: " · ")
    }

    /// 陪伴时长条：和这一批里最久的那件比
    private func durationBar(_ p: Product) -> some View {
        let fraction = min(1, Double(p.usageDays) / Double(longestDays))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(p.tint.mixed(with: .black, 0.12))
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    /// 68 天 · 41 次 · ¥2.1/次（没开封日期就不写天数，没价格就不写每次）
    private func detail(_ p: Product) -> String {
        var parts: [String] = []
        if p.openedDate != nil { parts.append(durationText(p.usageDays)) }
        if p.useCount > 0 { parts.append("\(p.useCount) 次") }
        if let cost = p.costPerUse { parts.append("\(Fmt.money(cost))/次") }
        return parts.isEmpty ? "还没有使用记录" : parts.joined(separator: " · ")
    }

    private func durationText(_ days: Int) -> String {
        days >= 60 ? "\(max(1, Int((Double(days) / 30).rounded()))) 个月" : "\(days) 天"
    }

    private func stanceTag(_ stance: RepurchaseStance) -> some View {
        Text(stance.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(hex: "BE3223"))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color(hex: "BE3223").opacity(0.7), lineWidth: 1))
            .fixedSize()
    }

    private func spoken(_ p: Product) -> String {
        var s = p.name
        if let d = p.finishedDate { s += "，\(Fmt.shortDay(d))用完" }
        if p.openedDate != nil { s += "，用了 \(p.usageDays) 天" }
        if p.useCount > 0 { s += "，\(p.useCount) 次" }
        if let stance = p.repurchase { s += "，\(stance.title)" }
        return s
    }
}
