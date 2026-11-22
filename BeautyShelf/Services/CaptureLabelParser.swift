import Foundation

// 包装文字解析：纯函数，不依赖 Vision / UIKit，方便单独测试。
// 输入是 OCR 读到的一行行文字（带相对字高），输出到期日、开封后保质期（PAO）、容量、品牌 / 名称猜测。

/// OCR 读到的一行文字
struct LabelLine: Hashable, Sendable {
    var text: String
    /// 文字框高度（相对整张图，0...1）。用来猜"最大的那行字"= 名称。
    var height: Double = 0.04
    var confidence: Double = 1
}

/// 年 / 月 /（可选）日。只写到月份的到期日按当月 1 日算（宁早不晚）。
struct LabelDate: Hashable, Sendable, Comparable {
    var year: Int
    var month: Int
    var day: Int?

    var date: Date? {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day ?? 1
        return Calendar.current.date(from: c)
    }

    /// "2027年5月" / "2027年5月21日"
    var text: String {
        if let day { return "\(year)年\(month)月\(day)日" }
        return "\(year)年\(month)月"
    }

    static func < (a: LabelDate, b: LabelDate) -> Bool {
        (a.year, a.month, a.day ?? 1) < (b.year, b.month, b.day ?? 1)
    }

    /// 校验年月日是否真实存在（排除 2 月 30 日这类 OCR 误读）
    static func valid(year: Int, month: Int, day: Int?) -> LabelDate? {
        guard (2015...2060).contains(year), (1...12).contains(month) else { return nil }
        if let day {
            guard (1...31).contains(day) else { return nil }
            var c = DateComponents()
            c.year = year; c.month = month; c.day = day
            let cal = Calendar(identifier: .gregorian)
            guard let d = cal.date(from: c),
                  cal.component(.day, from: d) == day,
                  cal.component(.month, from: d) == month else { return nil }
        }
        return LabelDate(year: year, month: month, day: day)
    }

    func adding(months: Int) -> LabelDate {
        let total = (year * 12 + (month - 1)) + months
        let y = total / 12, m = total % 12 + 1
        // 日期超出当月天数时（1 月 31 日 + 1 个月）退回月末
        if let day, LabelDate.valid(year: y, month: m, day: day) == nil {
            return LabelDate(year: y, month: m, day: 28)
        }
        return LabelDate(year: y, month: m, day: day)
    }
}

/// 解析结果。每一项都可能为空：识别不到就让用户自己点胶囊填。
struct LabelReading: Equatable, Sendable {
    enum ExpirySource: Equatable, Sendable {
        /// 包装上标明的 EXP / 有效期至 / 限期使用日期
        case labeled
        /// 生产日期 + 保质期 N 年 推算
        case fromProduction
        /// 没有关键字，只有一个看起来像日期的数字
        case unlabeled
    }

    var expiry: LabelDate? = nil
    var expirySource: ExpirySource? = nil
    var pao: Int? = nil
    var capacity: Double? = nil
    /// "ml" / "g" / "片"
    var unit: String? = nil
    var name: String? = nil
    var brand: String? = nil
    var kindHint: VesselKindHint? = nil
    var categoryHint: CategoryHint? = nil

    var isEmpty: Bool { expiry == nil && pao == nil && capacity == nil && name == nil && brand == nil }
}

/// 与 Models 里的 VesselKind / ProductCategory 一一对应（原始值相同）。
/// 解析器保持零依赖，方便在没有 App 模型的环境里单独跑。
enum VesselKindHint: String, Sendable { case bottle, jar, tube, sheet, stick, compact }
enum CategoryHint: String, Sendable { case skincare = "护肤", makeup = "彩妆", fragrance = "香氛", body = "身体", hair = "头发" }

enum LabelParser {

    // MARK: - 入口

    static func parse(text: String) -> LabelReading {
        parse(text.components(separatedBy: .newlines).map { LabelLine(text: $0) })
    }

    static func parse(_ lines: [LabelLine], now: Date = .now) -> LabelReading {
        let cleaned = lines
            .map { LabelLine(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), height: $0.height, confidence: $0.confidence) }
            .filter { !$0.text.isEmpty }
        let norm = cleaned.map { normalize($0.text) }
        let all = norm.joined(separator: "\n")

        var r = LabelReading()
        if let (d, src) = expiry(in: norm, now: now) {
            r.expiry = d
            r.expirySource = src
        }
        r.pao = pao(in: norm)
        if let (v, u) = capacity(in: norm) {
            r.capacity = v
            r.unit = u
        }
        let (brand, name) = brandAndName(cleaned, normalized: norm)
        r.brand = brand
        r.name = name
        r.kindHint = kindHint(all)
        r.categoryHint = categoryHint(all)
        return r
    }

    // MARK: - 规范化

    /// 全角转半角、统一大写、统一标点，方便正则
    static func normalize(_ s: String) -> String {
        var t = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        let map: [String: String] = ["。": ".", "，": ",", "：": ":", "／": "/", "－": "-", "—": "-", "–": "-",
                                     "（": "(", "）": ")", "ｍ": "m", "ｌ": "l", "\u{00A0}": " "]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
        t = t.uppercased()
        // OCR 常把 mL 读成 ML / M1 / MI，这里只修 "数字 + M1/MI" 这一种
        t = replace(t, #"(?<=\d)\s?M[1I](?![A-Z0-9])"#, with: "ML")
        t = replace(t, #"\s+"#, with: " ")
        return t
    }

    // MARK: - 到期日

    private static let expiryKeywords = [
        "EXP", "EXPIRY", "EXPIRES", "EXPIRATION", "BEST BEFORE", "BEST BY", "USE BY", "USE BEFORE", "BBE", "BB:",
        "有效期至", "有效期限至", "有效日期", "限期使用日期", "限用日期", "限期使用", "保质期至", "失效日期", "到期日", "使用期限", "有效期"
    ]
    private static let productionKeywords = ["MFG", "MFD", "PRD", "PROD", "MANUFACTURE", "生产日期", "制造日期", "生产批号", "批号", "LOT"]

    private struct FoundDate {
        var date: LabelDate
        var range: NSRange
    }

    static func expiry(in lines: [String], now: Date = .now) -> (LabelDate, LabelReading.ExpirySource)? {
        var labeled: [LabelDate] = []
        var unlabeled: [LabelDate] = []
        var production: [LabelDate] = []
        var shelfLifeMonths: Int? = nil

        for (i, line) in lines.enumerated() {
            if shelfLifeMonths == nil { shelfLifeMonths = shelfLife(in: line) }

            let expKW = keywordEnd(in: line, keywords: expiryKeywords)
            let prdKW = keywordEnd(in: line, keywords: productionKeywords)
            // 关键字在上一行、日期在下一行（"EXP" 换行 "2027.05"）
            let prev = i > 0 ? lines[i - 1] : ""
            let prevIsExpLabel = keywordEnd(in: prev, keywords: expiryKeywords) != nil && dates(in: prev, keywordOnly: true).isEmpty
            let prevIsPrdLabel = keywordEnd(in: prev, keywords: productionKeywords) != nil && dates(in: prev, keywordOnly: true).isEmpty

            let hasLabel = expKW != nil || prdKW != nil || prevIsExpLabel || prevIsPrdLabel
            for f in dates(in: line, keywordOnly: hasLabel) {
                // 同一行里两个关键字时，看日期离哪个关键字更近（取日期前面最后出现的那个）
                let kind = classify(dateStart: f.range.location, line: line,
                                    prevExp: prevIsExpLabel, prevPrd: prevIsPrdLabel)
                switch kind {
                case .exp: labeled.append(f.date)
                case .prd: production.append(f.date)
                case .none: unlabeled.append(f.date)
                }
            }
        }

        if let d = labeled.max() { return (d, .labeled) }
        if let p = production.max(), let m = shelfLifeMonths { return (p.adding(months: m), .fromProduction) }
        // 没有关键字：取晚于（今天 - 1 年）里最晚的那个；生产日期一般早于今天
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: now)
        let candidates = unlabeled.filter { $0.year >= y - 1 }
        if let d = candidates.max(), production.isEmpty || candidates.count == 1 || d > (production.max() ?? d) {
            return (d, .unlabeled)
        }
        return nil
    }

    private enum DateKind { case exp, prd, none }

    private static func classify(dateStart: Int, line: String, prevExp: Bool, prevPrd: Bool) -> DateKind {
        let ns = line as NSString
        let before = ns.substring(to: min(dateStart, ns.length))
        let e = lastKeywordPosition(in: before, keywords: expiryKeywords)
        let p = lastKeywordPosition(in: before, keywords: productionKeywords)
        switch (e, p) {
        case let (e?, p?): return e > p ? .exp : .prd
        case (_?, nil): return .exp
        case (nil, _?): return .prd
        default: break
        }
        // 关键字在日期后面（"2027.05.21 前使用"）
        if line.contains("前使用") || line.contains("之前使用") { return .exp }
        if prevExp { return .exp }
        if prevPrd { return .prd }
        return .none
    }

    /// 保质期 3 年 / 保质期:36个月 / SHELF LIFE 3 YEARS
    static func shelfLife(in line: String) -> Int? {
        if let m = firstMatch(line, #"(?:保质期|有效期)\s*[:]?\s*(\d{1,2})\s*(年|个月|月|M(?![A-Z]))"#) {
            guard let n = Int(m[1]), n > 0 else { return nil }
            return m[2] == "年" ? n * 12 : n
        }
        if let m = firstMatch(line, #"SHELF\s*LIFE\s*[:]?\s*(\d{1,2})\s*(YEARS?|MONTHS?|Y|M)\b"#) {
            guard let n = Int(m[1]), n > 0 else { return nil }
            return m[2].hasPrefix("Y") ? n * 12 : n
        }
        return nil
    }

    private static let monthNames = ["JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
                                     "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12]

    /// 一行里所有像日期的片段。`keywordOnly` 为真时也接受容易误判的写法（20270521、05/27）。
    private static func dates(in line: String, keywordOnly: Bool) -> [FoundDate] {
        var found: [FoundDate] = []
        func overlaps(_ r: NSRange) -> Bool { found.contains { NSIntersectionRange($0.range, r).length > 0 } }
        func add(_ d: LabelDate?, _ r: NSRange) {
            guard let d, !overlaps(r) else { return }
            found.append(FoundDate(date: d, range: r))
        }

        // 1) 日-月-年：21.05.2027 / 21/05/2027（前两位 > 12 时按 月/日 交换）
        for m in matches(line, #"(?<![\d.])(\d{1,2})\s?[./\-]\s?(\d{1,2})\s?[./\-]\s?(20\d{2})(?!\d)"#) {
            guard let a = Int(m.groups[1]), let b = Int(m.groups[2]), let y = Int(m.groups[3]) else { continue }
            let d = (b > 12 && a <= 12) ? LabelDate.valid(year: y, month: a, day: b) : LabelDate.valid(year: y, month: b, day: a)
            add(d, m.range)
        }
        // 2) 年-月(-日)：2027-05-21 / 2027.05 / 2027年05月21日 / 2027/5
        for m in matches(line, #"(?<!\d)(20\d{2})\s?[./\-年]\s?(\d{1,2})(?:\s?[./\-月]\s?(\d{1,2})\s?日?|\s?月)?(?![\d])"#) {
            guard let y = Int(m.groups[0 + 1]), let mo = Int(m.groups[2]) else { continue }
            let day = m.groups[3].isEmpty ? nil : Int(m.groups[3])
            add(LabelDate.valid(year: y, month: mo, day: day), m.range)
        }
        // 3) 月-年：05/2027 / 5.2027 / 05-2027 / 05 2027
        for m in matches(line, #"(?<![\d./\-])(\d{1,2})\s?[./\- ]\s?(20\d{2})(?!\d)"#) {
            guard let mo = Int(m.groups[1]), let y = Int(m.groups[2]) else { continue }
            add(LabelDate.valid(year: y, month: mo, day: nil), m.range)
        }
        // 4) 英文月份：MAY 2027 / 21 MAY 2027 / 21-MAY-2027
        for m in matches(line, #"(?<!\d)(?:(\d{1,2})\s?[\- ]?\s?)?(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[A-Z]*\.?\s?[\-/ ]?\s?(20\d{2})(?!\d)"#) {
            guard let mo = monthNames[m.groups[2]], let y = Int(m.groups[3]) else { continue }
            let day = m.groups[1].isEmpty ? nil : Int(m.groups[1])
            add(LabelDate.valid(year: y, month: mo, day: day), m.range)
        }
        if keywordOnly {
            // 5) 紧凑数字：20270521 / 202705
            for m in matches(line, #"(?<!\d)(20\d{2})(0[1-9]|1[0-2])([0-3]\d)?(?!\d)"#) {
                guard let y = Int(m.groups[1]), let mo = Int(m.groups[2]) else { continue }
                let day = m.groups[3].isEmpty ? nil : Int(m.groups[3])
                add(LabelDate.valid(year: y, month: mo, day: day), m.range)
            }
            // 6) 两位年份：EXP 05/27（月/年）
            for m in matches(line, #"(?<![\d./\-])(0?[1-9]|1[0-2])\s?[/.\-]\s?(\d{2})(?![\d./\-])"#) {
                guard let mo = Int(m.groups[1]), let yy = Int(m.groups[2]) else { continue }
                add(LabelDate.valid(year: 2000 + yy, month: mo, day: nil), m.range)
            }
        }
        return found
    }

    // MARK: - 开封后保质期 PAO

    private static let paoValues: Set<Int> = [3, 6, 9, 12, 18, 24, 30, 36, 48]

    static func pao(in lines: [String]) -> Int? {
        let joined = lines.joined(separator: " ")
        // 中文写法最明确：开封后 12 个月内使用
        if let m = firstMatch(joined, #"开[封启盖瓶罐]后[^\d]{0,8}(\d{1,2})\s?个?月"#), let n = Int(m[1]), (1...60).contains(n) {
            return n
        }
        if let m = firstMatch(joined, #"(\d{1,2})\s?MONTHS?\s?AFTER\s?OPEN"#), let n = Int(m[1]), (1...60).contains(n) {
            return n
        }
        if let m = firstMatch(joined, #"PAO\s?[:]?\s?(\d{1,2})\s?M?"#), let n = Int(m[1]), paoValues.contains(n) {
            return n
        }
        // 开罐图标上的 12M：不跟在小数点或数字后面，后面不是字母（排除 50ML）
        for line in lines {
            // 保质期 36M / SHELF LIFE 36M 不是 PAO
            if line.contains("保质期") || line.contains("SHELF") { continue }
            for m in matches(line, #"(?<![\d.A-Z])(\d{1,2})\s?M(?![A-Z0-9])"#) {
                if let n = Int(m.groups[1]), paoValues.contains(n) { return n }
            }
        }
        return nil
    }

    // MARK: - 容量

    static func capacity(in lines: [String]) -> (Double, String)? {
        struct Cand { var value: Double; var unit: String; var score: Int }
        var cands: [Cand] = []
        let pattern = #"(?<![\d.,])(\d{1,4}(?:[.,]\d{1,2})?)\s?(ML|毫升|FL\.?\s?OZ|OZ|GR|G|克|片|PCS|PIECES|SHEETS?)(?![A-Z])"#
        for line in lines {
            let context = line.contains("净含量") || line.contains("NET") || line.contains("容量") || line.contains("规格") || line.contains("净重")
            for m in matches(line, pattern) {
                guard let v = Double(m.groups[1].replacingOccurrences(of: ",", with: ".")), v > 0 else { continue }
                let raw = m.groups[2].replacingOccurrences(of: " ", with: "")
                var unit: String
                var value = v
                var score = context ? 2 : 0
                switch raw {
                case "ML", "毫升":
                    unit = "ml"; score += 3
                    guard (1...1000).contains(v) else { continue }
                case "G", "GR", "克":
                    unit = "g"; score += 3
                    guard (0.5...1000).contains(v) else { continue }
                case "片", "PCS", "PIECES", "SHEET", "SHEETS":
                    unit = "片"; score += 5
                    guard (1...100).contains(v), v == v.rounded() else { continue }
                case "FLOZ", "FL.OZ":
                    unit = "ml"; value = (v * 29.5735).rounded()
                    guard (1...1000).contains(value) else { continue }
                default: // OZ：净重
                    unit = "g"; value = (v * 28.3495).rounded()
                    guard (1...1000).contains(value) else { continue }
                }
                cands.append(Cand(value: value, unit: unit, score: score))
            }
        }
        // 同分取先出现的
        guard let best = cands.enumerated().max(by: { a, b in
            a.element.score != b.element.score ? a.element.score < b.element.score : a.offset > b.offset
        })?.element else { return nil }
        return (best.value, best.unit)
    }

    // MARK: - 品牌 / 名称

    /// 常见品牌（匹配时忽略大小写、空格、标点）。前面是规范写法。
    static let knownBrands: [(String, [String])] = [
        ("雅诗兰黛", ["雅诗兰黛", "ESTEELAUDER", "ESTÉELAUDER"]),
        ("兰蔻", ["兰蔻", "LANCOME", "LANCÔME"]),
        ("SK-II", ["SKII", "SK2"]),
        ("资生堂", ["资生堂", "SHISEIDO"]),
        ("肌肤之钥", ["肌肤之钥", "CLEDEPEAU"]),
        ("欧莱雅", ["欧莱雅", "LOREAL", "L'OREAL"]),
        ("海蓝之谜", ["海蓝之谜", "LAMER"]),
        ("科颜氏", ["科颜氏", "KIEHLS", "KIEHL'S"]),
        ("倩碧", ["倩碧", "CLINIQUE"]),
        ("修丽可", ["修丽可", "SKINCEUTICALS"]),
        ("理肤泉", ["理肤泉", "LAROCHEPOSAY"]),
        ("雅漾", ["雅漾", "AVENE", "AVÈNE"]),
        ("适乐肤", ["适乐肤", "CERAVE"]),
        ("薇诺娜", ["薇诺娜", "WINONA"]),
        ("珀莱雅", ["珀莱雅", "PROYA"]),
        ("玉泽", ["玉泽"]),
        ("自然堂", ["自然堂", "CHANDO"]),
        ("百雀羚", ["百雀羚"]),
        ("花西子", ["花西子", "FLORASIS"]),
        ("完美日记", ["完美日记", "PERFECTDIARY"]),
        ("毛戈平", ["毛戈平", "MAOGEPING"]),
        ("娇韵诗", ["娇韵诗", "CLARINS"]),
        ("赫莲娜", ["赫莲娜", "HELENARUBINSTEIN"]),
        ("黛珂", ["黛珂", "DECORTE", "DECORTÉ"]),
        ("雪花秀", ["雪花秀", "SULWHASOO"]),
        ("兰芝", ["兰芝", "LANEIGE"]),
        ("玉兰油", ["玉兰油", "OLAY"]),
        ("安热沙", ["安热沙", "ANESSA"]),
        ("珂润", ["珂润", "CUREL", "CURÉL"]),
        ("芙丽芳丝", ["芙丽芳丝", "FREEPLUS"]),
        ("迪奥", ["迪奥", "DIOR"]),
        ("香奈儿", ["香奈儿", "CHANEL"]),
        ("圣罗兰", ["圣罗兰", "YSL", "YVESSAINTLAURENT"]),
        ("阿玛尼", ["阿玛尼", "ARMANI"]),
        ("汤姆福特", ["汤姆福特", "TOMFORD"]),
        ("娇兰", ["娇兰", "GUERLAIN"]),
        ("纪梵希", ["纪梵希", "GIVENCHY"]),
        ("NARS", ["NARS"]),
        ("MAC", ["MAC"]),
        ("芭比波朗", ["芭比波朗", "BOBBIBROWN"]),
        ("3CE", ["3CE"]),
        ("祖玛珑", ["祖玛珑", "JOMALONE"]),
        ("Le Labo", ["LELABO"]),
        ("Diptyque", ["DIPTYQUE"]),
        ("伊索", ["伊索", "AESOP"]),
        ("The Ordinary", ["THEORDINARY"]),
        ("Fresh", ["FRESH馥蕾诗", "馥蕾诗"]),
        ("悦木之源", ["悦木之源", "ORIGINS"]),
        ("碧欧泉", ["碧欧泉", "BIOTHERM"]),
        ("怡思丁", ["怡思丁", "ISDIN"]),
        ("妮维雅", ["妮维雅", "NIVEA"]),
    ]

    private static func squash(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func knownBrand(in lines: [String]) -> (brand: String, lineIndex: Int)? {
        for (i, line) in lines.enumerated() {
            let sq = squash(line)
            for (canon, aliases) in knownBrands {
                for a in aliases {
                    let qa = squash(a)
                    // 很短的拉丁缩写（MAC / YSL / 3CE）要求整行就是它，避免误中 "MACADAMIA"
                    if qa.count <= 4 && qa.allSatisfy({ $0.isASCII }) {
                        if sq == qa { return (canon, i) }
                    } else if sq.contains(qa) {
                        return (canon, i)
                    }
                }
            }
        }
        return nil
    }

    /// 不像名称的行：日期、批号、成分、地址、网址……
    private static let noiseWords = ["EXP", "LOT", "BATCH", "MFG", "MFD", "PAO", "批号", "生产", "有效期", "限期", "保质期", "净含量", "NET",
                                     "WT", "INGREDIENT", "成分", "地址", "电话", "WWW", "HTTP", ".COM", "制造", "MADE IN", "产地",
                                     "使用方法", "注意", "备案", "许可证", "执行标准", "条形码", "委托", "经销", "进口", "SPF", "PA+"]

    static func brandAndName(_ lines: [LabelLine], normalized: [String]) -> (brand: String?, name: String?) {
        let known = knownBrand(in: normalized)
        var cands: [(text: String, norm: String, height: Double, index: Int)] = []
        for (i, line) in lines.enumerated() {
            let n = normalized[i]
            let t = line.text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard t.count >= 2, t.count <= 32, line.confidence >= 0.3 else { continue }
            let digits = t.filter { $0.isNumber }.count
            guard Double(digits) / Double(t.count) < 0.3 else { continue }
            guard t.contains(where: { $0.isLetter }) else { continue }
            if noiseWords.contains(where: { n.contains($0) }) { continue }
            if capacity(in: [n]) != nil && t.count <= 20 { continue }
            if i == known?.lineIndex { continue }
            cands.append((t, n, line.height, i))
        }
        cands.sort { $0.height != $1.height ? $0.height > $1.height : $0.index < $1.index }

        var brand = known?.brand
        var name = cands.first?.text
        if brand == nil, cands.count >= 2 {
            // 最大的一行是纯大写拉丁短词（logo），第二行更像名称 → 前者当品牌
            let top = cands[0], second = cands[1]
            let topIsLogo = top.text.allSatisfy { $0.isASCII } && top.text == top.text.uppercased() && top.text.count <= 14
            if topIsLogo && (second.text.count > top.text.count || second.text.contains(where: { !$0.isASCII })) {
                brand = prettify(top.text)
                name = second.text
            }
        }
        // 中文名称往往是贴纸上的小字，但更好认：大写拉丁名称的同时，候选里有中文且字号不小于最大行的一半时用中文
        if let current = name, current.allSatisfy({ $0.isASCII }),
           let topH = cands.first?.height,
           let cjk = cands.first(where: { c in c.text.contains(where: isCJK) && c.height >= topH * 0.5 && c.text != brand }) {
            name = cjk.text
        }
        return (brand, name.map(prettify))
    }

    private static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// 全大写英文转成首字母大写：ADVANCED NIGHT REPAIR → Advanced Night Repair
    static func prettify(_ s: String) -> String {
        let letters = s.filter { $0.isLetter }
        guard letters.count > 3, letters.allSatisfy({ $0.isASCII }), s == s.uppercased() else { return s }
        return s.capitalized
    }

    // MARK: - 形状 / 分类提示

    static func kindHint(_ all: String) -> VesselKindHint? {
        func has(_ words: [String]) -> Bool { words.contains { all.contains($0) } }
        if has(["口红", "唇膏", "LIPSTICK", "LIP BALM", "ROUGE A LEVRES", "唇釉笔"]) { return .stick }
        if has(["眼影", "腮红", "粉饼", "修容", "高光", "气垫", "PALETTE", "EYESHADOW", "BLUSH", "PRESSED POWDER", "CUSHION", "COMPACT"]) { return .compact }
        if has(["面膜", "眼膜", "MASK", "SHEET"]) && !has(["睡眠", "SLEEPING", "涂抹", "泥膜", "CLAY"]) { return .sheet }
        if has(["香水", "PARFUM", "EAU DE", "COLOGNE", "TOILETTE", "粉底液", "FOUNDATION", "精华", "SERUM", "ESSENCE", "AMPOULE", "安瓶", "原液", "化妆水", "爽肤水", "TONER", "精华水", "喷雾", "MIST", "精油", " OIL"]) { return .bottle }
        if has(["洁面", "洗面", "CLEANSER", "CLEANSING FOAM", "防晒", "SUNSCREEN", "SUN CREAM", "隔离", "护手", "HAND CREAM", "牙膏", "啫喱", "GEL"]) { return .tube }
        if has(["面霜", "眼霜", "霜", "CREAM", "BALM", "膏", "BUTTER", "泥膜", "SLEEPING"]) { return .jar }
        if has(["乳液", "LOTION", "EMULSION", "MILK", "乳"]) { return .bottle }
        return nil
    }

    static func categoryHint(_ all: String) -> CategoryHint? {
        func has(_ words: [String]) -> Bool { words.contains { all.contains($0) } }
        if has(["香水", "PARFUM", "EAU DE", "COLOGNE", "TOILETTE", "香氛", "FRAGRANCE"]) { return .fragrance }
        if has(["洗发", "护发", "发膜", "SHAMPOO", "CONDITIONER", "HAIR"]) { return .hair }
        if has(["口红", "唇", "LIPSTICK", "粉底", "FOUNDATION", "眼影", "腮红", "粉饼", "睫毛", "MASCARA", "眉", "BROW", "遮瑕", "CONCEALER", "气垫", "CUSHION", "PALETTE", "BLUSH", "妆前", "PRIMER", "散粉", "定妆"]) { return .makeup }
        if has(["身体", "BODY", "护手", "HAND CREAM", "沐浴", "SHOWER"]) { return .body }
        return nil
    }

    // MARK: - 正则小工具

    struct Match { var range: NSRange; var groups: [String] }

    static func matches(_ s: String, _ pattern: String) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            var g: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                g.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            return Match(range: m.range, groups: g)
        }
    }

    static func firstMatch(_ s: String, _ pattern: String) -> [String]? {
        matches(s, pattern).first?.groups
    }

    static func replace(_ s: String, _ pattern: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    /// 关键字（取最后一个）在行内的结束位置
    private static func keywordEnd(in line: String, keywords: [String]) -> Int? {
        lastKeywordPosition(in: line, keywords: keywords)
    }

    private static func lastKeywordPosition(in s: String, keywords: [String]) -> Int? {
        let ns = s as NSString
        var best: Int? = nil
        for k in keywords {
            var search = NSRange(location: 0, length: ns.length)
            while true {
                let r = ns.range(of: k, options: [], range: search)
                if r.location == NSNotFound { break }
                // 拉丁关键字要求左侧不是字母（避免 "PRODUCT" 里的 "PROD" 之类误中在单词中间）
                let leftOK = r.location == 0 || !isLatinLetter(ns.character(at: r.location - 1))
                let end = r.location + r.length
                let isLatinKW = k.unicodeScalars.first.map { $0.isASCII } ?? false
                let rightOK = !isLatinKW || end >= ns.length || !isLatinLetter(ns.character(at: end))
                if leftOK && rightOK { best = max(best ?? 0, end) }
                search = NSRange(location: end, length: ns.length - end)
            }
        }
        return best
    }

    private static func isLatinLetter(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    }
}

#if DEBUG
// MARK: - 样例（像单元测试一样跑：LabelParser.runExamples() 返回失败列表，空 = 全部通过）

extension LabelParser {
    struct Example {
        var text: String
        var expiry: LabelDate? = nil
        var pao: Int? = nil
        var capacity: Double? = nil
        var unit: String? = nil
        var brand: String? = nil
        var name: String? = nil
    }

    static let examples: [Example] = [
        Example(text: "ESTĒE LAUDER\nAdvanced Night Repair\n50ml / 1.7 FL.OZ.\nEXP 2027.05\n12M",
                expiry: LabelDate(year: 2027, month: 5), pao: 12, capacity: 50, unit: "ml", brand: "雅诗兰黛"),
        Example(text: "EXP:05/2027 LOT 3K21", expiry: LabelDate(year: 2027, month: 5)),
        Example(text: "限期使用日期 2027年05月21日\n净含量：30mL", expiry: LabelDate(year: 2027, month: 5, day: 21), capacity: 30, unit: "ml"),
        Example(text: "有效期至：2026-11-03\n生产日期：2023-11-04", expiry: LabelDate(year: 2026, month: 11, day: 3)),
        Example(text: "生产日期 20240310\n保质期3年", expiry: LabelDate(year: 2027, month: 3, day: 10)),
        Example(text: "2027-05-21", expiry: LabelDate(year: 2027, month: 5, day: 21)),
        Example(text: "BEST BEFORE 21.08.2028\n100 g e", expiry: LabelDate(year: 2028, month: 8, day: 21), capacity: 100, unit: "g"),
        Example(text: "EXP\n2028/02", expiry: LabelDate(year: 2028, month: 2)),
        Example(text: "EXP 03/28", expiry: LabelDate(year: 2028, month: 3)),
        Example(text: "EXP 20270915", expiry: LabelDate(year: 2027, month: 9, day: 15)),
        Example(text: "补水保湿面膜\n25ml×10片", capacity: 10, unit: "片"),
        Example(text: "开封后12个月内使用完毕", pao: 12),
        Example(text: "6 M  50 ML", pao: 6, capacity: 50, unit: "ml"),
        Example(text: "SPF50+ PA++++ 防晒乳 60ml", pao: nil, capacity: 60, unit: "ml"),
        Example(text: "MAY 2027", expiry: LabelDate(year: 2027, month: 5)),
        Example(text: "Ｅｘｐ：２０２７．０５", expiry: LabelDate(year: 2027, month: 5)),
        Example(text: "保质期 36M\n生产日期 2025.01.10", expiry: LabelDate(year: 2028, month: 1, day: 10), pao: nil),
    ]

    @discardableResult
    static func runExamples() -> [String] {
        var failures: [String] = []
        let now = LabelDate(year: 2026, month: 11, day: 22).date ?? .now
        for (i, ex) in examples.enumerated() {
            let r = parse(ex.text.components(separatedBy: "\n").map { LabelLine(text: $0) }, now: now)
            func check<T: Equatable>(_ label: String, _ want: T?, _ got: T?) {
                if let want, want != got { failures.append("#\(i) \(label): 期望 \(want)，得到 \(String(describing: got))  «\(ex.text)»") }
            }
            check("到期", ex.expiry, r.expiry)
            check("PAO", ex.pao, r.pao)
            check("容量", ex.capacity, r.capacity)
            check("单位", ex.unit, r.unit)
            check("品牌", ex.brand, r.brand)
            check("名称", ex.name, r.name)
            // 明确不该有 PAO 的样例
            if ex.pao == nil, (ex.text.contains("防晒") || ex.text.contains("保质期 36M")), r.pao != nil {
                failures.append("#\(i) PAO 误识别为 \(r.pao!)")
            }
        }
        return failures
    }
}
#endif
