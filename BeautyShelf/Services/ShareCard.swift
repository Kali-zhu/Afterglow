import SwiftUI
import UIKit

// MARK: - 空瓶记的时间段

enum EmptiesPeriod: Hashable, Identifiable {
    case month(year: Int, month: Int)
    case year(Int)

    var id: String {
        switch self {
        case .month(let y, let m): "m-\(y)-\(m)"
        case .year(let y): "y-\(y)"
        }
    }

    var isMonth: Bool { if case .month = self { return true } else { return false } }

    private static var currentYear: Int { Calendar.current.component(.year, from: .now) }

    /// "11 月空瓶"、跨年时 "2025 年 11 月空瓶"、"2026 年空瓶"
    var title: String {
        switch self {
        case .month(let y, let m): y == Self.currentYear ? "\(m) 月空瓶" : "\(y) 年 \(m) 月空瓶"
        case .year(let y): "\(y) 年空瓶"
        }
    }

    /// 选择器里的名字
    var pickerTitle: String {
        switch self {
        case .month(let y, let m): "\(y) 年 \(m) 月"
        case .year(let y): "\(y) 年"
        }
    }

    /// 分享图角落的日期：2026.11 / 2026
    var stamp: String {
        switch self {
        case .month(let y, let m): String(format: "%d.%02d", y, m)
        case .year(let y): "\(y)"
        }
    }

    var fileStem: String {
        switch self {
        case .month(let y, let m): String(format: "BeautyShelf-empties-%d-%02d", y, m)
        case .year(let y): "BeautyShelf-empties-\(y)"
        }
    }

    func contains(_ date: Date) -> Bool {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        switch self {
        case .month(let y, let m): return c.year == y && c.month == m
        case .year(let y): return c.year == y
        }
    }

    static func of(_ date: Date, monthly: Bool) -> EmptiesPeriod {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return monthly ? .month(year: c.year ?? 0, month: c.month ?? 1) : .year(c.year ?? 0)
    }

    /// 有空瓶的月份 / 年份，从近到远
    static func available(in finished: [Product], monthly: Bool) -> [EmptiesPeriod] {
        var seen = Set<EmptiesPeriod>()
        var result: [EmptiesPeriod] = []
        for d in finished.compactMap(\.finishedDate).sorted(by: >) {
            let p = of(d, monthly: monthly)
            if seen.insert(p).inserted { result.append(p) }
        }
        return result
    }
}

// MARK: - 渲染

/// 空瓶记分享图：1080 × 1440（3:4，适合小红书），用 ImageRenderer 生成。
@MainActor
enum ShareCard {
    /// 以 pt 排版，@2x 输出 1080 × 1440
    static let canvas = CGSize(width: 540, height: 720)

    static func items(for period: EmptiesPeriod, in products: [Product]) -> [Product] {
        products.filter { p in p.finishedDate.map(period.contains) ?? false }
            .sorted { ($0.finishedDate ?? .distantPast) < ($1.finishedDate ?? .distantPast) }
    }

    static func render(period: EmptiesPeriod, products: [Product]) -> UIImage? {
        let content = ShareCardView(period: period, items: items(for: period, in: products))
            .frame(width: canvas.width, height: canvas.height)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// 写成临时 PNG，交给 ShareLink（存相册 / 发小红书都认）
    static func writePNG(_ image: UIImage, period: EmptiesPeriod) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(period.fileStem + ".png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - 分享图本体

struct ShareCardView: View {
    let period: EmptiesPeriod
    let items: [Product]

    private let ink = Color(hex: "1C1C1E")
    private let soft = Color(hex: "6B7078")
    private let plank = Color(hex: "D9DEE4")

    private var maxShown: Int { 12 }
    private var shown: [Product] { Array(items.prefix(maxShown)) }
    private var perRow: Int { shown.count <= 3 ? max(1, shown.count) : 4 }
    private var rows: [[Product]] {
        stride(from: 0, to: shown.count, by: perRow).map { Array(shown[$0..<min($0 + perRow, shown.count)]) }
    }
    private var figureHeight: CGFloat {
        switch rows.count {
        case 0, 1: 210
        case 2: 140
        default: 96
        }
    }

    private var totalUses: Int { items.reduce(0) { $0 + $1.useCount } }
    private var totalSpent: Double { items.compactMap(\.price).reduce(0, +) }
    private var pricedUses: Int { items.filter { ($0.price ?? 0) > 0 }.reduce(0) { $0 + $1.useCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
                .padding(.top, 44)
            Spacer(minLength: 16)
            if shown.isEmpty {
                Text("这段时间还没有空瓶")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(soft)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 16)
            } else {
                VStack(spacing: rows.count >= 3 ? 14 : 22) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        shelfRow(row)
                    }
                }
                if items.count > shown.count {
                    Text("还有 \(items.count - shown.count) 件没摆下")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(soft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
                Spacer(minLength: 16)
            }
            footer
                .padding(.bottom, 30)
        }
        .padding(.horizontal, 36)
        .frame(width: ShareCard.canvas.width, height: ShareCard.canvas.height)
        .background(
            LinearGradient(colors: [Color(hex: "F6F7F9"), Color(hex: "E9EDF1")], startPoint: .top, endPoint: .bottom)
        )
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(period.title)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("· \(items.count) 件")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(soft)
            }
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            HStack(spacing: 14) {
                stat("\(totalUses)", "次使用")
                if totalSpent > 0 {
                    stat(Fmt.money(totalSpent), "花费")
                    if pricedUses > 0 {
                        stat(Fmt.money(totalSpent / Double(pricedUses)), "平均每次")
                    }
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(ink)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(soft)
        }
    }

    private func shelfRow(_ row: [Product]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(row) { p in
                    ProductFigure(product: p, maxPixel: 520, level: 0)
                        .frame(height: figureHeight * p.shelfScale)
                        .frame(maxWidth: .infinity, maxHeight: figureHeight, alignment: .bottom)
                }
                ForEach(0..<(perRow - row.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: figureHeight)
                }
            }
            .padding(.horizontal, 8)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(plank)
                .frame(height: 7)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 3)
            HStack(alignment: .top, spacing: 12) {
                ForEach(row) { p in
                    label(p).frame(maxWidth: .infinity)
                }
                ForEach(0..<(perRow - row.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
    }

    private func label(_ p: Product) -> some View {
        VStack(spacing: 2) {
            Text(p.name)
                .font(.system(size: rows.count >= 3 ? 11 : 13, weight: .semibold))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(perUseLine(p))
                .font(.system(size: rows.count >= 3 ? 10 : 11, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(soft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .multilineTextAlignment(.center)
    }

    private func perUseLine(_ p: Product) -> String {
        if let c = p.costPerUse { return "\(p.useCount) 次 · \(Fmt.money(c))/次" }
        return "用了 \(p.useCount) 次"
    }

    private var footer: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "E7B873"))
                Text("余香")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                Text("Afterglow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(soft)
            }
            Spacer()
            Text(period.stamp)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(soft)
        }
    }
}
