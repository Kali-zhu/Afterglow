import Foundation
import SwiftData

/// "先看看示例"：一张真实感的梳妆台。全部标记为 isSample，可在设置里一键清除。
enum SampleData {
    static func insert(into context: ModelContext) {
        let cal = Calendar.current
        let now = Date.now

        func ago(days: Int = 0, months: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(month: -months, day: -days), to: now) ?? now
        }
        func ahead(days: Int = 0, months: Int = 0, years: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(year: years, month: months, day: days), to: now) ?? now
        }
        /// 过去 14 天里的使用记录（跳过一些天，看起来像真人）
        func fillLog(_ p: Product, hour: Int, skipEvery: Int, extraUses: Int) {
            var log: [Date] = []
            for d in stride(from: 13, through: 1, by: -1) where d % skipEvery != 0 {
                let day = ago(days: d)
                log.append(cal.date(bySettingHour: hour, minute: 10, second: 0, of: day) ?? day)
            }
            p.useLog = log
            p.useCount = log.count + extraUses
        }

        var items: [Product] = []

        // 1. 精华：早晚都用
        let serum = Product(name: "小棕瓶精华", brand: "雅诗兰黛", category: .skincare, kind: .bottle,
                            total: 50, remaining: 31, amountPerUse: 0.5,
                            expiryDate: ahead(years: 2), openedDate: ago(months: 3), paoMonths: 6,
                            tintHex: "E7B873")
        serum.price = 780
        serum.inEvening = true
        fillLog(serum, hour: 22, skipEvery: 4, extraUses: 30)
        items.append(serum)

        // 2. 化妆水
        let toner = Product(name: "护肤精华露 神仙水", brand: "SK-II", category: .skincare, kind: .bottle,
                            total: 230, remaining: 142, amountPerUse: 3,
                            expiryDate: ahead(years: 2, months: 6), openedDate: ago(months: 2), paoMonths: 12,
                            tintHex: "BFD7EA")
        toner.price = 1540
        toner.inMorning = true
        toner.inEvening = true
        fillLog(toner, hour: 8, skipEvery: 6, extraUses: 18)
        items.append(toner)

        // 3. 洁面
        let cleanser = Product(name: "氨基酸洁面乳", brand: "芙丽芳丝", category: .skincare, kind: .tube,
                               total: 100, unit: "g", amountPerUse: 1,
                               expiryDate: ahead(years: 2), openedDate: ago(days: 40), paoMonths: 12,
                               tintHex: "C8E0CC")
        cleanser.remainingAmount = 58
        cleanser.price = 118
        cleanser.inMorning = true
        cleanser.inEvening = true
        fillLog(cleanser, hour: 8, skipEvery: 7, extraUses: 30)
        items.append(cleanser)

        // 4. 防晒
        let sunscreen = Product(name: "水感防晒精华", brand: "碧柔", category: .skincare, kind: .tube,
                                total: 50, remaining: 41, unit: "g", amountPerUse: 1,
                                expiryDate: ahead(years: 1, months: 8), openedDate: ago(days: 12), paoMonths: 12,
                                tintHex: "F1E6D8")
        sunscreen.price = 79
        sunscreen.inMorning = true
        fillLog(sunscreen, hour: 8, skipEvery: 5, extraUses: 0)
        items.append(sunscreen)

        // 5. 面霜
        let cream = Product(name: "高保湿面霜", brand: "科颜氏", category: .skincare, kind: .jar,
                            total: 50, remaining: 22, unit: "g", amountPerUse: 0.8,
                            expiryDate: ahead(years: 2), openedDate: ago(months: 4), paoMonths: 12,
                            tintHex: "F1E6D8")
        cream.price = 320
        cream.inEvening = true
        fillLog(cream, hour: 22, skipEvery: 5, extraUses: 25)
        items.append(cream)

        // 6. 面膜：剩 7 / 共 10 片
        let masks = Product(name: "补水修护面膜", brand: "敷尔佳", category: .skincare, kind: .sheet,
                            total: 10, remaining: 7,
                            expiryDate: ahead(months: 14), openedDate: ago(days: 10), paoMonths: nil,
                            tintHex: "BFD7EA")
        masks.price = 99
        masks.useLog = [ago(days: 9), ago(days: 6), ago(days: 2)]
        masks.useCount = 3
        items.append(masks)

        // 7. 口红：估算剩余
        let lipstick = Product(name: "烈艳蓝金唇膏 999", brand: "Dior 迪奥", category: .makeup, kind: .stick,
                               remaining: 65,
                               expiryDate: ahead(years: 2), openedDate: ago(months: 8), paoMonths: 24,
                               tintHex: "C9505C")
        lipstick.price = 350
        lipstick.useCount = 46
        lipstick.useLog = [ago(days: 11), ago(days: 8), ago(days: 5), ago(days: 3), ago(days: 1)]
        items.append(lipstick)

        // 8. 眼影盘：估算剩余
        let palette = Product(name: "四色眼影盘 裸杏", brand: "3CE", category: .makeup, kind: .compact,
                              remaining: 80,
                              expiryDate: ahead(years: 2, months: 6), openedDate: ago(months: 2), paoMonths: 24,
                              tintHex: "E9A07A")
        palette.price = 189
        palette.useCount = 21
        palette.useLog = [ago(days: 12), ago(days: 7), ago(days: 4)]
        items.append(palette)

        // 9. 已过期：粉底液开封 13 个月，PAO 12M
        let foundation = Product(name: "DW 持妆粉底液", brand: "雅诗兰黛", category: .makeup, kind: .bottle,
                                 total: 30, remaining: 3.5, amountPerUse: 0.4,
                                 expiryDate: ahead(years: 1), openedDate: ago(months: 13), paoMonths: 12,
                                 tintHex: "D9B38C")
        foundation.price = 420
        foundation.useCount = 66
        items.append(foundation)

        // 10. 快到期：还没开封的眼霜，包装到期日 18 天后
        let eyeCream = Product(name: "抗蓝光眼霜", brand: "雅诗兰黛", category: .skincare, kind: .jar,
                               total: 15, unit: "ml", amountPerUse: 0.2,
                               expiryDate: ahead(days: 18), openedDate: nil, paoMonths: 12,
                               tintHex: "F2C4C9")
        eyeCream.price = 520
        items.append(eyeCream)

        // 11. 香水
        let perfume = Product(name: "英国梨与小苍兰", brand: "祖玛珑", category: .fragrance, kind: .bottle,
                              total: 100, remaining: 78, amountPerUse: 0.3,
                              expiryDate: ahead(years: 3), openedDate: ago(months: 6), paoMonths: 36,
                              tintHex: "D5C6E8")
        perfume.price = 1150
        perfume.useCount = 73
        items.append(perfume)

        // 12、13. 空瓶
        let emptySerum = Product(name: "玻尿酸 B5 精华", brand: "The Ordinary", category: .skincare, kind: .bottle,
                                 total: 30, remaining: 0, amountPerUse: 0.5,
                                 expiryDate: ahead(years: 1), openedDate: ago(days: 110), paoMonths: 6,
                                 tintHex: "BFD7EA")
        emptySerum.price = 69
        emptySerum.useCount = 58
        emptySerum.finishedDate = ago(days: 20)
        emptySerum.needsRestock = true
        items.append(emptySerum)

        let handCream = Product(name: "乳木果护手霜", brand: "欧舒丹", category: .body, kind: .tube,
                                total: 30, remaining: 0, unit: "ml", amountPerUse: 0.7,
                                expiryDate: ahead(years: 1), openedDate: ago(months: 5), paoMonths: 12,
                                tintHex: "F1E6D8")
        handCream.price = 85
        handCream.useCount = 41
        handCream.finishedDate = ago(months: 2)
        items.append(handCream)

        for p in items {
            p.isSample = true
            context.insert(p)
        }
        try? context.save()
    }

    static func clear(from context: ModelContext, products: [Product]) {
        for p in products where p.isSample {
            context.delete(p)
        }
        try? context.save()
    }
}
