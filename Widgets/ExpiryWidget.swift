import WidgetKit
import SwiftUI
import SwiftData

// MARK: - 快过期：最快过期的几件，按状态着色；含锁屏

struct ExpiryEntry: TimelineEntry {
    let date: Date
    let items: [WidgetItem]

    static let placeholder = ExpiryEntry(date: .now,
                                         items: WidgetItem.placeholders.sorted { $0.daysLeft < $1.daysLeft })
}

struct ExpiryProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExpiryEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ExpiryEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(entries(dates: [.now]).first ?? .placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExpiryEntry>) -> Void) {
        // 天数只在午夜变化：现在一条 + 明天 0:00 一条
        let list = entries(dates: WidgetData.timelineDates(includeAfternoon: false))
        completion(Timeline(entries: list, policy: .atEnd))
    }

    private func entries(dates: [Date]) -> [ExpiryEntry] {
        let context = ModelContext(SharedStore.container)
        let all = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let soonest = all.filter { !$0.isFinished }
            .sorted { $0.effectiveExpiry < $1.effectiveExpiry }
            .prefix(4)
        let thumbs: [String: UIImage?] = Dictionary(soonest.map { ($0.uid.uuidString, WidgetData.thumb($0)) },
                                                     uniquingKeysWith: { first, _ in first })
        return dates.map { date in
            ExpiryEntry(date: date, items: soonest.map {
                WidgetData.item($0, at: date, slot: nil, thumb: thumbs[$0.uid.uuidString] ?? nil)
            })
        }
    }
}

struct ExpiryWidget: Widget {
    let kind = "ExpiryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExpiryProvider()) { entry in
            ExpiryWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.porcelain }
        }
        .configurationDisplayName("快过期")
        .description("最快过期的几件，记得先用掉。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct ExpiryWidgetView: View {
    let entry: ExpiryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "hourglass")
                .font(.caption.weight(.semibold))
            Text("快过期")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("妆台上还没有产品")
                .font(.subheadline.weight(.semibold))
            Text("添加后这里会显示最快过期的几件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // 小：最快过期的一件放大，下面两行
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let first = entry.items.first {
                HStack(alignment: .bottom, spacing: 8) {
                    WidgetThumb(item: first, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(first.daysText)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(first.state.color)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(first.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(first.name)，\(first.accessibilityExpiry)")
                Spacer(minLength: 0)
                ForEach(entry.items.dropFirst().prefix(2)) { item in
                    ExpiryLine(item: item, compact: true)
                }
            } else {
                Spacer(minLength: 0)
                emptyText
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 中：四件横排，像架子上的小瓶子
    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                emptyText
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(entry.items) { item in
                        VStack(spacing: 4) {
                            WidgetThumb(item: item, height: 48)
                            Text(item.name)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                            Text(item.daysText)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(item.state.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.name)，\(item.accessibilityExpiry)")
                    }
                    if entry.items.count < 4 {
                        ForEach(0..<(4 - entry.items.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.shelf)
                    .frame(height: 4)
                    .accessibilityHidden(true)
            }
        }
    }

    // 锁屏长条：标题 + 最快的两件
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("快过期", systemImage: "hourglass")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if entry.items.isEmpty {
                Text("还没有产品").font(.caption)
            } else {
                ForEach(entry.items.prefix(2)) { item in
                    HStack(spacing: 4) {
                        Text(item.name).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(item.daysText)
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.name)，\(item.accessibilityExpiry)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 锁屏圆形：最快过期那件还剩几天（30 天内的进度）
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let first = entry.items.first {
                Gauge(value: Double(max(0, min(30, first.daysLeft))), in: 0...30) {
                    Image(systemName: "hourglass")
                } currentValueLabel: {
                    Text(first.daysLeft < 0 ? "过期" : "\(first.daysLeft)")
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityLabel("\(first.name)，\(first.accessibilityExpiry)")
            } else {
                Image(systemName: "hourglass")
                    .accessibilityLabel("还没有产品")
            }
        }
    }
}

/// 一行：缩略图 + 名称 + 天数（按状态着色）
struct ExpiryLine: View {
    let item: WidgetItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            WidgetThumb(item: item, height: compact ? 18 : 24)
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(item.daysText)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(item.state.color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name)，\(item.accessibilityExpiry)")
    }
}

#Preview(as: .systemSmall) {
    ExpiryWidget()
} timeline: {
    ExpiryEntry.placeholder
}
