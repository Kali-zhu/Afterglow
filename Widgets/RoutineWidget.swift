import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - 今晚该用：当前流程（15:00 前早间，之后晚间），可直接勾选

struct RoutineEntry: TimelineEntry {
    let date: Date
    let slot: RoutineSlot
    let items: [WidgetItem]

    var doneCount: Int { items.filter { $0.done }.count }
    var allDone: Bool { !items.isEmpty && doneCount == items.count }

    var title: String { slot == .evening ? "今晚该用" : "今早该用" }
    var completionLine: String { slot == .evening ? "晚间护肤完成，晚安" : "早间护肤完成，出门吧" }

    static let placeholder = RoutineEntry(date: .now, slot: .evening, items: WidgetItem.placeholders)
}

struct RoutineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (RoutineEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(entries(dates: [.now]).first ?? .placeholder)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineEntry>) -> Void) {
        let list = entries(dates: WidgetData.timelineDates(includeAfternoon: true))
        completion(Timeline(entries: list, policy: .atEnd))
    }

    private func entries(dates: [Date]) -> [RoutineEntry] {
        let context = ModelContext(SharedStore.container)
        var thumbs: [String: UIImage] = [:]
        return dates.map { date in
            let slot = SharedStore.currentSlot(at: date)
            let products = SharedStore.routine(slot, in: context)
            let items = products.map { p -> WidgetItem in
                let key = p.uid.uuidString
                if thumbs[key] == nil, let t = WidgetData.thumb(p) { thumbs[key] = t }
                return WidgetData.item(p, at: date, slot: slot, thumb: thumbs[key])
            }
            return RoutineEntry(date: date, slot: slot, items: items)
        }
    }
}

struct RoutineWidget: Widget {
    let kind = "RoutineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RoutineProvider()) { entry in
            RoutineWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.porcelain }
        }
        .configurationDisplayName("今晚该用")
        .description("当前的早间 / 晚间流程，点一下就记好了。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RoutineWidgetView: View {
    let entry: RoutineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.items.isEmpty {
            empty
        } else if family == .systemMedium {
            medium
        } else {
            small
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.slot.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            Text("还没有\(entry.slot.title)流程")
                .font(.subheadline.weight(.semibold))
            Text("在「今日」里把产品排进来")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.slot == .evening ? "moon.stars.fill" : "sun.max.fill")
                .font(.title3)
                .foregroundStyle(entry.slot == .evening ? Color(hex: "B9A6DA") : Theme.honey)
                .accessibilityHidden(true)
            Text(entry.completionLine)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(entry.items.count) 步都做完了")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // 小：标题 + 环，下面是接下来的 3 件
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                header
                WidgetRing(done: entry.doneCount, total: entry.items.count, lineWidth: 4)
                    .frame(width: 30, height: 30)
            }
            Spacer(minLength: 0)
            if entry.allDone {
                completion
            } else {
                let pending = entry.items.filter { !$0.done }
                ForEach(pending.prefix(3)) { item in
                    RoutineCheckRow(item: item, slot: entry.slot, compact: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 中：左边环和完成情况，右边按顺序 4 件（已用的打勾，可再点撤销）
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Spacer(minLength: 0)
                WidgetRing(done: entry.doneCount, total: entry.items.count, lineWidth: 6)
                    .frame(width: 54, height: 54)
                if entry.allDone {
                    Text(entry.completionLine)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("还剩 \(entry.items.count - entry.doneCount) 步")
                        .font(.caption.weight(.semibold))
                }
            }
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleMediumItems) { item in
                    RoutineCheckRow(item: item, slot: entry.slot, compact: false)
                }
                if entry.items.count > visibleMediumItems.count {
                    Text("还有 \(entry.items.count - visibleMediumItems.count) 件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 优先显示没用的；不够 4 件再补已用的（保持原顺序）
    private var visibleMediumItems: [WidgetItem] {
        let limit = 4
        if entry.items.count <= limit { return entry.items }
        let pendingIDs = Set(entry.items.filter { !$0.done }.prefix(limit).map { $0.id })
        var chosen = entry.items.filter { pendingIDs.contains($0.id) }
        if chosen.count < limit {
            chosen += entry.items.filter { $0.done }.prefix(limit - chosen.count)
            let order: [String: Int] = Dictionary(entry.items.enumerated().map { ($1.id, $0) },
                                                 uniquingKeysWith: { first, _ in first })
            chosen.sort { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        }
        return chosen
    }
}

/// 一行：缩略图 + 名称 + 勾选圆圈；整行是一个 AppIntent 按钮
struct RoutineCheckRow: View {
    let item: WidgetItem
    let slot: RoutineSlot
    let compact: Bool

    var body: some View {
        Button(intent: LogRoutineIntent(productID: item.id, slot: slot)) {
            HStack(spacing: 8) {
                WidgetThumb(item: item, height: compact ? 22 : 26)
                Text(item.name)
                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    .strikethrough(item.done, color: .secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ZStack {
                    Circle()
                        .strokeBorder(item.done ? Color.clear : Color.secondary.opacity(0.6), lineWidth: 1.5)
                    if item.done {
                        Circle().fill(Theme.sage)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: compact ? 18 : 20, height: compact ? 18 : 20)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.done ? "今天已用" : "未用")
        .accessibilityHint(item.done ? "轻点撤销" : "轻点记一次使用")
    }
}

#Preview(as: .systemMedium) {
    RoutineWidget()
} timeline: {
    RoutineEntry.placeholder
}
