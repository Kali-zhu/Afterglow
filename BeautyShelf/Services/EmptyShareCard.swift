import SwiftUI
import UIKit

// MARK: - 空瓶分享卡：文案
//
// 一张卡上的字全部来自「这一条记录」：
// - 标题的量词只看包装形式（面膜还要看这一条记录的范围），确认不了就不猜，退回「又用完了一件。」；
// - 规格、使用时长、用完日期、累计用量都是有才显示，没有就整块收起来；
// - 复购态度是用户自己选的，没选就不盖印章。

enum EmptyCardCopy {
    /// 「这一瓶，用完了。」「这一片，敷完了。」
    static func title(for p: Product) -> String {
        guard let noun = quantifier(for: p) else { return "又用完了一件。" }
        let verb = (p.kind == .sheet && noun == "片") ? "敷完了" : "用完了"
        return "这一\(noun)，\(verb)。"
    }

    /// 量词。面膜按记录范围分：一片 → 「片」，一整盒（包装规格 ≥ 2 片）→ 「盒」。
    /// 包装规格都没填的面膜分不清是一片还是一盒，返回 nil，交给通用那句。
    static func quantifier(for p: Product) -> String? {
        switch p.kind {
        case .sheet:
            guard p.totalAmount > 0 else { return nil }
            return p.totalAmount.rounded() <= 1 ? "片" : "盒"
        case .tube, .stick: return "支"
        case .jar: return "罐"
        case .bottle: return "瓶"
        case .compact: return "盘"
        }
    }

    /// 原始规格：50 mL / 30 g / 10 片。保留用户填的单位（ml 印成 mL）。
    static func spec(for p: Product) -> String? {
        switch p.measureMode {
        case .volume:
            guard p.totalAmount > 0, !p.unit.isEmpty else { return nil }
            let unit = p.unit.lowercased() == "ml" ? "mL" : p.unit
            return "\(Fmt.amount(p.totalAmount)) \(unit)"
        case .count:
            guard p.totalAmount > 0 else { return nil }
            return "\(Int(p.totalAmount.rounded())) 片"
        case .estimate:
            // 口红、粉盒没有可靠的包装规格，不硬写一个数字
            return nil
        }
    }

    /// 使用记录那两行
    struct Record: Equatable {
        var label: String = ""
        var value: String = ""
        /// 第二行：用完日期 / 累计用量
        var detail: String? = nil
        var isEmpty: Bool { value.isEmpty }
    }

    static func record(for p: Product) -> Record {
        // 使用时长只在两端都有可靠日期时算：开封 → 用完。
        // 没有开封日期就退回用完日期，不拿"添加时间"凑一个天数出来。
        var duration: String?
        if p.openedDate != nil, p.finishedDate != nil {
            let days = p.usageDays
            if days >= 1 { duration = "\(days) 天" }
        }
        let finished = p.finishedDate.map(dayText)
        let uses = p.useCount > 0 ? "\(p.useCount) 次" : nil

        var record = Record()
        var detail: [String] = []
        if let duration {
            record.label = "使用时长"
            record.value = duration
            if let finished { detail.append("用完 \(finished)") }
            if let uses { detail.append("共 \(uses)") }
        } else if let finished {
            record.label = "用完日期"
            record.value = finished
            if let uses { detail.append("共 \(uses)") }
        } else if let uses {
            record.label = "累计用量"
            record.value = uses
        }
        record.detail = detail.isEmpty ? nil : detail.joined(separator: " · ")
        return record
    }

    /// 今年的只写月和日，往年的带上年份
    static func dayText(_ date: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: .now)
        return sameYear ? Fmt.shortDay(date) : Fmt.day(date)
    }
}

// MARK: - 字体
//
// 卡上是纸的质感，字要有笔画：标题、产品名、心得、印章用中文衬线（iOS 自带的宋体）。
// 取不到这个名字就退回系统字体——排版不依赖某个字体是否装在这台机器上。

private enum CardFont {
    private static func installed(_ names: [String], _ size: CGFloat) -> String? {
        names.first { UIFont(name: $0, size: size) != nil }
    }

    static func serif(_ size: CGFloat, bold: Bool = true) -> Font {
        let names = bold
            ? ["STSongti-SC-Bold", "Songti SC Bold", "STSongti-SC-Regular", "Songti SC"]
            : ["STSongti-SC-Regular", "Songti SC Regular", "STSongti-SC-Light", "Songti SC"]
        if let name = installed(names, size) { return .custom(name, size: size) }
        return .system(size: size, weight: bold ? .bold : .regular)
    }
}

// MARK: - 渲染

/// 空瓶分享卡：1080 × 1440（3:4 竖图，发小红书刚好），用 ImageRenderer 生成。
/// 预览和导出走的是同一个 `EmptyShareCardView`，所见即所得。
@MainActor
enum EmptyShareCard {
    /// 以 pt 排版，@2x 输出 1080 × 1440
    static let canvas = CGSize(width: 540, height: 720)

    /// 个人空瓶序号：这条记录在全部空瓶里排第几件（按用完日期从早到晚）。
    /// 没有用完日期就没有序号。
    static func sequence(of product: Product, among all: [Product]) -> Int? {
        guard product.finishedDate != nil else { return nil }
        let ordered = all
            .filter { $0.finishedDate != nil }
            .sorted { ($0.finishedDate ?? .distantPast) < ($1.finishedDate ?? .distantPast) }
        guard let index = ordered.firstIndex(where: { $0.uid == product.uid }) else { return nil }
        return index + 1
    }

    static func render(product: Product, sequence: Int?) -> UIImage? {
        let content = EmptyShareCardView(product: product, sequence: sequence)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// 写成临时 PNG，交给 ShareLink（存相册 / 发小红书都认）
    static func writePNG(_ image: UIImage, product: Product) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileStem(for: product) + ".png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func fileStem(for product: Product) -> String {
        let cleaned = product.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = cleaned.isEmpty ? "空瓶" : String(cleaned.prefix(24))
        return "BeautyShelf-empty-\(stem)"
    }
}

// MARK: - 卡片本体
//
// 版式是一张"纸上的手记"：暖米白的纸、左上角一盏很淡的暖光、墨黑的字。
// 页眉一条细线把「空瓶手记」和序号分开，标题是一句衬线大字，中间是这条记录的主图，
// 下面依次是产品名 + 原始规格、使用记录、用后感；复购态度是一枚朱红色的椭圆印章，
// 压在图片右下角、探到产品名上方。没有照片时变成一张以产品名和心得为主的文字卡。

struct EmptyShareCardView: View {
    let product: Product
    /// 这是第几件用空的；没有用完日期时为 nil（页眉只留一条线）
    let sequence: Int?

    // 纸、墨、印：整套版式只有这三个颜色，其余全是透明度
    private let paper = Color(hex: "F2ECE1")
    private let ink = Color(hex: "1B1712")
    private let seal = Color(hex: "BE3223")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            titleText.layoutPriority(1)

            if hasFigure {
                // 字先拿到它需要的高度，主图拿剩下的（图片可以缩，字不能被挤掉）
                figure
                productLine(emphasis: false).layoutPriority(1)
                recordLine.layoutPriority(1)
                noteText.layoutPriority(1)
            } else {
                // 文字版：产品名当主角，上下各留一段白，心得落在纸的下半部分
                Spacer(minLength: 16)
                HStack(alignment: .top, spacing: 14) {
                    productLine(emphasis: true).layoutPriority(1)
                    if let stance = product.repurchase { stamp(stance) }
                }
                Spacer(minLength: 16)
                recordLine
                noteText
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 26)
        .frame(width: EmptyShareCard.canvas.width, height: EmptyShareCard.canvas.height, alignment: .topLeading)
        .background {
            ZStack {
                paper
                // 和 App 里同一盏灯：左上一片很淡的暖光，纸才像被照着
                RadialGradient(colors: [Color.white.opacity(0.5), .clear],
                               center: UnitPoint(x: 0.16, y: -0.08), startRadius: 8, endRadius: 620)
            }
        }
        .clipped()
        .environment(\.colorScheme, .light)
    }

    // MARK: 页眉

    private var header: some View {
        HStack(spacing: 12) {
            Text("空瓶手记")
                .font(.system(size: 12.5, weight: .medium))
            Rectangle()
                .fill(ink.opacity(0.42))
                .frame(height: 0.8)
            if let sequence {
                Text(String(format: "NO. %03d", sequence))
                    .font(.system(size: 11.5))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(ink.opacity(0.85))
        .accessibilityHidden(true)
    }

    // MARK: 标题

    private var titleText: some View {
        Text(EmptyCardCopy.title(for: product))
            .font(CardFont.serif(50))
            .foregroundStyle(ink)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 16)
    }

    // MARK: 主图

    /// 这条记录的空瓶实拍优先，其次是产品已有的抠图。
    /// 一律 scaledToFit：包装比例不能变形，主体要完整，剩下的留白就是纸。
    private var photoImage: UIImage? {
        product.photo.flatMap {
            SharedStore.thumbnail($0, key: product.uid.uuidString + "-photo", maxPixel: 1600)
        }
    }

    private var cutoutImage: UIImage? {
        product.cutout.flatMap {
            SharedStore.thumbnail($0, key: product.uid.uuidString, maxPixel: 1600)
        }
    }

    /// 主图真的解码出来了才算有（照片数据坏了就退回文字版，不留一块空白）
    private var hasFigure: Bool { photoImage != nil || cutoutImage != nil }

    private var figure: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = photoImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hairline, style: .continuous))
                } else if let image = cutoutImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
            .frame(maxWidth: .infinity)

            if let stance = product.repurchase {
                stamp(stance).offset(x: 2, y: 26)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 44)
        .accessibilityHidden(true)
    }

    // MARK: 产品名 + 原始规格

    private func productLine(emphasis: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(product.name)
                .font(CardFont.serif(emphasis ? 33 : 26))
                .foregroundStyle(ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let spec = EmptyCardCopy.spec(for: product) {
                Text(spec)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(ink.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 使用记录

    @ViewBuilder
    private var recordLine: some View {
        let record = EmptyCardCopy.record(for: product)
        if !record.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Text(record.label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(ink.opacity(0.6))
                    Text(record.value)
                        .font(.system(size: 15.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    Rectangle()
                        .fill(ink.opacity(0.24))
                        .frame(height: 0.8)
                }
                if let detail = record.detail {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(ink.opacity(0.58))
                }
            }
            .padding(.top, 14)
        }
    }

    // MARK: 用后感

    @ViewBuilder
    private var noteText: some View {
        if let note = product.trimmedNote {
            // 长心得在卡上节选（末尾省略号），原记录一个字都不改
            Text(note)
                .font(CardFont.serif(16, bold: false))
                .foregroundStyle(ink.opacity(0.88))
                .lineSpacing(8)
                .lineLimit(hasFigure ? 3 : 5)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
    }

    // MARK: 复购印章

    private func stamp(_ stance: RepurchaseStance) -> some View {
        Text(stance.title)
            .font(CardFont.serif(23))
            .tracking(1.5)
            .foregroundStyle(seal)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .overlay {
                Ellipse().strokeBorder(seal, lineWidth: 2.4)
            }
            .overlay {
                Ellipse().strokeBorder(seal.opacity(0.5), lineWidth: 0.9).padding(4)
            }
            .rotationEffect(.degrees(-7))
            .opacity(0.93)
            .fixedSize()
            .accessibilityHidden(true)
    }
}
