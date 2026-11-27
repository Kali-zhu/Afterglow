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
            // 近黑的底：容器按夜间着色画，玻璃在暗底上才有厚度
            .environment(\.colorScheme, .dark)
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
//
// 版式跟着一组"极简金句卡"走：近黑的卡面、上方一大块实物陈列、
// 底部一道渐变压黑，白色无衬线金句左对齐贴底，下面两枚半透明胶囊，
// 最底两个等宽的圆角块（品牌 / 日期）。没有边框、没有衬线、没有装饰线。

struct ShareCardView: View {
    let period: EmptiesPeriod
    let items: [Product]

    // 近黑 + 白：整套只有四个值（卡面、白、半透明白、灰白），颜色全部来自瓶身自己
    private let ink = Color(hex: "0A0A0A")
    private let text = Color.white

    private var maxShown: Int { 12 }
    private var shown: [Product] { Array(items.prefix(maxShown)) }
    private var perRow: Int { shown.count <= 3 ? max(1, shown.count) : 4 }
    private var rows: [[Product]] {
        stride(from: 0, to: shown.count, by: perRow).map { Array(shown[$0..<min($0 + perRow, shown.count)]) }
    }

    /// 上方陈列区占多高（卡高的 72%）：物件底边贴在这一行上，下面压黑放字
    private var stageHeight: CGFloat { ShareCard.canvas.height * 0.72 }
    private var figureHeight: CGFloat {
        switch rows.count {
        case 0, 1: 300
        case 2: 200
        default: 132
        }
    }

    private var totalUses: Int { items.reduce(0) { $0 + $1.useCount } }
    private var totalSpent: Double { items.compactMap(\.price).reduce(0, +) }
    private var pricedUses: Int { items.filter { ($0.price ?? 0) > 0 }.reduce(0) { $0 + $1.useCount } }

    var body: some View {
        ZStack(alignment: .top) {
            ink

            stage
                .frame(height: stageHeight)

            // 底部渐变压黑：让字浮在暗处，瓶子的下半截淡出去
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: ink.opacity(0.45), location: 0.42),
                .init(color: ink.opacity(0.88), location: 0.58),
                .init(color: ink, location: 0.68),
                .init(color: ink, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                bottomStack
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
        }
        .frame(width: ShareCard.canvas.width, height: ShareCard.canvas.height)
        .clipped()
    }

    // MARK: 上方陈列

    private var stage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if shown.isEmpty {
                Text("这段时间还没有空瓶")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.bottom, 60)
            } else {
                VStack(spacing: rows.count >= 3 ? 10 : 18) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        shelfRow(row)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .background {
            // 顶上一盏很淡的暖光，像摄影棚打在暗墙上
            RadialGradient(colors: [Color(hex: "F3DDB4").opacity(0.15), .clear],
                           center: UnitPoint(x: 0.5, y: -0.05), startRadius: 8, endRadius: 360)
        }
    }

    private func shelfRow(_ row: [Product]) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(row) { p in
                ZStack(alignment: .bottom) {
                    // 暗底上唯一的"落地感"：瓶子脚下化开一片它自己的颜色
                    CausticGlow(tint: p.tint, width: figureHeight * 0.42, strength: 1.1)
                    ProductFigure(product: p, maxPixel: 520, level: 0)
                        .frame(height: figureHeight * p.shelfScale)
                }
                .frame(maxWidth: .infinity, maxHeight: figureHeight, alignment: .bottom)
            }
            ForEach(0..<(perRow - row.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, maxHeight: figureHeight)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: 底部：金句 + 胶囊 + 两块

    private var bottomStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(quote)
                .font(.system(size: 17.5, weight: .medium))
                .foregroundStyle(text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            pillRow
                .padding(.top, 12)

            HStack(spacing: 10) {
                block("余香 Afterglow", dark: true)
                block(period.stamp, dark: false)
            }
            .padding(.top, 18)
        }
    }

    /// 这张图想说的那一句
    private var quote: String {
        guard !items.isEmpty else { return "这段时间还没有空瓶。下个月再记一笔。" }
        var s = "\(period.title)，我用完了 \(items.count) 件。"
        if totalUses > 0 {
            s += "它们一共陪了我 \(totalUses) 次"
            if totalSpent > 0, pricedUses > 0 {
                s += "，花掉 \(Fmt.money(totalSpent))，平均每次 \(Fmt.money(totalSpent / Double(pricedUses)))"
            }
            s += "。"
        }
        return s
    }

    private var pillRow: some View {
        HStack(spacing: 8) {
            pill(period.title)
            if !items.isEmpty {
                pill("\(items.count) 件")
                if totalUses > 0 { pill("\(totalUses) 次") }
                if totalSpent > 0 { pill(Fmt.money(totalSpent)) }
                if items.count > shown.count { pill("还有 \(items.count - shown.count) 件") }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func pill(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.16)))
    }

    private func block(_ title: String, dark: Bool) -> some View {
        Text(title)
            .font(.system(size: 14, weight: dark ? .semibold : .regular))
            .foregroundStyle(dark ? ink : Color.white.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous)
                    .fill(dark ? Color.white : Color.white.opacity(0.12))
            }
    }
}
