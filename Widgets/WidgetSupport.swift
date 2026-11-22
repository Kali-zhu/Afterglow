import WidgetKit
import SwiftUI
import SwiftData

/// 小组件里用的产品快照（不把 SwiftData 对象带出 Provider）
struct WidgetItem: Identifiable {
    let id: String
    let name: String
    let brand: String
    let tintHex: String
    let thumb: UIImage?
    let done: Bool
    let daysLeft: Int
    let remainingText: String

    var state: ExpiryState { Product.state(forDays: daysLeft) }
    var tint: Color { Color(hex: tintHex) }

    var daysText: String {
        if daysLeft < 0 { return "过期 \(-daysLeft) 天" }
        if daysLeft == 0 { return "今天到期" }
        return "\(daysLeft) 天"
    }

    var accessibilityExpiry: String {
        if daysLeft < 0 { return "已过期 \(-daysLeft) 天" }
        if daysLeft == 0 { return "今天过期" }
        return "\(daysLeft) 天后过期"
    }

    static let placeholders: [WidgetItem] = [
        WidgetItem(id: "a", name: "洁面乳", brand: "", tintHex: "F1E6D8", thumb: nil, done: true, daysLeft: 120, remainingText: "剩 80 ml"),
        WidgetItem(id: "b", name: "修护精华", brand: "", tintHex: "E7B873", thumb: nil, done: false, daysLeft: 12, remainingText: "剩 18 ml"),
        WidgetItem(id: "c", name: "保湿面霜", brand: "", tintHex: "BFD7EA", thumb: nil, done: false, daysLeft: 45, remainingText: "剩 30 g"),
        WidgetItem(id: "d", name: "眼霜", brand: "", tintHex: "D5C6E8", thumb: nil, done: false, daysLeft: -3, remainingText: "剩 8 g")
    ]
}

enum WidgetData {
    /// 每条时间线的刷新点：现在、今天 15:00（早晚切换）、明天 0:00
    static func timelineDates(now: Date = .now, includeAfternoon: Bool) -> [Date] {
        let cal = Calendar.current
        var dates = [now]
        if includeAfternoon,
           let three = cal.date(bySettingHour: 15, minute: 0, second: 0, of: now), three > now {
            dates.append(three)
        }
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            dates.append(midnight)
        }
        return dates
    }

    static func daysLeft(_ p: Product, at date: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: p.effectiveExpiry)).day ?? 0
    }

    static func thumb(_ p: Product, maxPixel: Int = 160) -> UIImage? {
        guard let data = p.cutout else { return nil }
        return SharedStore.thumbnail(data, key: p.uid.uuidString, maxPixel: maxPixel)
    }

    static func item(_ p: Product, at date: Date, slot: RoutineSlot?, thumb: UIImage?) -> WidgetItem {
        WidgetItem(id: p.uid.uuidString,
                   name: p.name,
                   brand: p.brand,
                   tintHex: p.tintHex,
                   thumb: thumb,
                   done: slot.map { SharedStore.isDone(p, $0, on: date) } ?? false,
                   daysLeft: daysLeft(p, at: date),
                   remainingText: p.remainingText)
    }
}

/// 抠图缩略图；没有抠图时是一个液体色的小胶囊
struct WidgetThumb: View {
    let item: WidgetItem
    var height: CGFloat

    var body: some View {
        Group {
            if let image = item.thumb {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Capsule(style: .continuous)
                    .fill(item.tint.gradient)
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .frame(width: height * 0.42)
            }
        }
        .frame(width: height * 0.7, height: height)
        .accessibilityHidden(true)
    }
}

/// 小组件里的进度环
struct WidgetRing: View {
    let done: Int
    let total: Int
    var lineWidth: CGFloat = 5

    private var progress: Double { total == 0 ? 0 : Double(done) / Double(total) }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Theme.sage, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if total > 0 && done >= total {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.sage)
            } else {
                Text("\(done)/\(total)")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(total > 0 && done >= total ? "全部完成" : "已完成 \(done) 步，共 \(total) 步")
    }
}
