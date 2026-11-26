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
            // 深色展柜：容器按夜间着色画，玻璃在深底上才有厚度
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
// 一版"海报"，不是一张浅色清单：
// 深色展柜的底 + 顶上一盏暖灯 + 黄铜细线 + 衬线大标题 + 账单式小字 + 一句人话。
// 内容逻辑（月份 / 年份、每件用了几次、¥/次）沿用原来的，只重排版式。

struct ShareCardView: View {
    let period: EmptiesPeriod
    let items: [Product]

    // 深色展柜的配色：夜绿、象牙、黄铜、灰绿
    private let nightTop = Color(hex: "0B1210")
    private let nightBottom = Color(hex: "18241E")
    private let ivory = Color(hex: "F7F2E8")
    private let dim = Color(hex: "9CAC9F")
    private let brass = Color(hex: "CBA36A")

    private var maxShown: Int { 12 }
    private var shown: [Product] { Array(items.prefix(maxShown)) }
    private var perRow: Int { shown.count <= 3 ? max(1, shown.count) : 4 }
    private var rows: [[Product]] {
        stride(from: 0, to: shown.count, by: perRow).map { Array(shown[$0..<min($0 + perRow, shown.count)]) }
    }
    private var figureHeight: CGFloat {
        switch rows.count {
        case 0, 1: 190
        case 2: 128
        default: 92
        }
    }
    private var compactLabels: Bool { rows.count >= 3 }

    private var totalUses: Int { items.reduce(0) { $0 + $1.useCount } }
    private var totalSpent: Double { items.compactMap(\.price).reduce(0, +) }
    private var pricedUses: Int { items.filter { ($0.price ?? 0) > 0 }.reduce(0) { $0 + $1.useCount } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 42)
                titleBlock
                    .padding(.top, 18)
                ornament
                    .padding(.vertical, 18)
                if shown.isEmpty {
                    Text("这段时间还没有空瓶")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(dim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    showcase
                }
                Spacer(minLength: 18)
                footer
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 38)
            .frame(width: ShareCard.canvas.width, height: ShareCard.canvas.height, alignment: .topLeading)

            frameOutline
        }
        .frame(width: ShareCard.canvas.width, height: ShareCard.canvas.height)
        .clipped()
    }

    // MARK: 展柜的底：夜绿渐变 + 顶上一盏暖灯 + 左下一团冷光

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: [nightTop, nightBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: "F0D7A8").opacity(0.26), .clear],
                           center: UnitPoint(x: 0.5, y: 0.0), startRadius: 6, endRadius: 340)
            RadialGradient(colors: [Color(hex: "5E9277").opacity(0.18), .clear],
                           center: UnitPoint(x: 0.12, y: 1.0), startRadius: 4, endRadius: 300)
        }
    }

    private var frameOutline: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.hairline, style: .continuous)
            .strokeBorder(ivory.opacity(0.14), lineWidth: 0.8)
            .padding(16)
    }

    // MARK: 抬头

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("AFTERGLOW")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(3)
                .foregroundStyle(brass)
            Rectangle()
                .fill(brass.opacity(0.45))
                .frame(width: 20, height: 0.8)
            Text("空瓶记")
                .font(.system(size: 10.5, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(dim)
            Spacer(minLength: 8)
            Text(period.stamp)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .tracking(1.2)
                .monospacedDigit()
                .foregroundStyle(dim)
        }
    }

    // MARK: 标题：衬线大字 + 一行"账目"

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(period.title)
                .font(.system(size: 58, weight: .semibold, design: .serif))
                .foregroundStyle(ivory)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(items.count) 件")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(brass)
                specLine
            }
        }
    }

    private var specLine: some View {
        HStack(spacing: 8) {
            Text("\(totalUses) 次使用")
                .font(.system(size: 11.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(dim)
            if totalSpent > 0 {
                dot
                Text("花了 \(Fmt.money(totalSpent))")
                    .font(.system(size: 11.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(dim)
                if pricedUses > 0 {
                    dot
                    Text("平均 \(Fmt.money(totalSpent / Double(pricedUses)))/次")
                        .font(.system(size: 11.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(dim)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var dot: some View {
        Circle().fill(brass.opacity(0.6)).frame(width: 2.5, height: 2.5)
    }

    private var ornament: some View {
        HStack(spacing: 8) {
            Rectangle().fill(brass.opacity(0.4)).frame(height: 0.7)
            Rectangle().fill(brass).frame(width: 4, height: 4).rotationEffect(.degrees(45))
            Rectangle().fill(brass.opacity(0.4)).frame(height: 0.7)
        }
    }

    // MARK: 陈列：空的容器站在黄铜架板上

    private var showcase: some View {
        VStack(spacing: rows.count >= 3 ? 14 : 22) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                shelfRow(row)
            }
        }
        .padding(.top, 2)
    }

    private func shelfRow(_ row: [Product]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(row) { p in
                    let glowWidth = figureHeight * 0.42
                    ZStack(alignment: .bottom) {
                        CausticGlow(tint: p.tint, width: glowWidth, strength: 1.15)
                        ContactShadow(width: glowWidth * 1.05)
                        ProductFigure(product: p, maxPixel: 520, level: 0)
                            .frame(height: figureHeight * p.shelfScale)
                    }
                    .frame(maxWidth: .infinity, maxHeight: figureHeight, alignment: .bottom)
                }
                ForEach(0..<(perRow - row.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: figureHeight)
                }
            }
            .padding(.horizontal, 4)

            // 黄铜架板：一道细线、一线暖高光，下面一点点投影
            VStack(spacing: 0) {
                LinearGradient(colors: [brass.opacity(0.95), brass.opacity(0.45)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                LinearGradient(colors: [brass.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 9)
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(row) { p in
                    label(p).frame(maxWidth: .infinity)
                }
                ForEach(0..<(perRow - row.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 9)
        }
    }

    private func label(_ p: Product) -> some View {
        VStack(spacing: 2) {
            Text(p.name)
                .font(.system(size: compactLabels ? 10 : 12, weight: .semibold))
                .foregroundStyle(ivory)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(p.useCount) 次")
                .font(.system(size: compactLabels ? 9 : 10.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(dim)
                .lineLimit(1)
            if let c = p.costPerUse {
                Text("\(Fmt.money(c))/次")
                    .font(.system(size: compactLabels ? 9 : 10.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(brass)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: 落款

    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            if items.count > shown.count {
                Text("还有 \(items.count - shown.count) 件没摆下")
                    .font(.system(size: 10))
                    .foregroundStyle(dim.opacity(0.8))
            }
            Text(narrative)
                .font(.system(size: 12.5))
                .foregroundStyle(dim)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

            HStack(alignment: .lastTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(brass)
                    Text("余香")
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(ivory)
                    Text("AFTERGLOW")
                        .font(.system(size: 8, weight: .medium))
                        .tracking(1.6)
                        .foregroundStyle(dim)
                }
                Spacer(minLength: 8)
                Text("把梳妆台搬进手机")
                    .font(.system(size: 9.5))
                    .foregroundStyle(dim.opacity(0.75))
            }
        }
    }

    /// 一句人话：这张图想说的是"我用完了多少、用得值不值"
    private var narrative: String {
        var parts = ["这段时间用完了 \(items.count) 件，一共用了 \(totalUses) 次"]
        if totalSpent > 0, pricedUses > 0 {
            parts.append("花了 \(Fmt.money(totalSpent))，平均每次 \(Fmt.money(totalSpent / Double(pricedUses)))")
        }
        return parts.joined(separator: "；") + "。"
    }
}
