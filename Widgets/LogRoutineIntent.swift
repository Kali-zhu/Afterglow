import AppIntents
import SwiftData
import WidgetKit

/// 小组件里的勾选按钮：记一次流程使用（已记过则撤销）。
/// 在小组件进程里直接写 App Group 里的共享数据库。
struct LogRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "记一次护肤"
    static var description: IntentDescription = IntentDescription("在小组件里勾掉流程中的一件产品。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "产品")
    var productID: String

    @Parameter(title: "时段")
    var slotRaw: String

    init() {}

    init(productID: String, slot: RoutineSlot) {
        self.productID = productID
        self.slotRaw = slot.rawValue
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let uid = UUID(uuidString: productID) else { return .result() }
        let slot = RoutineSlot(rawValue: slotRaw) ?? SharedStore.currentSlot()
        let context = SharedStore.container.mainContext
        var descriptor = FetchDescriptor<Product>(predicate: #Predicate<Product> { $0.uid == uid })
        descriptor.fetchLimit = 1
        guard let product = try context.fetch(descriptor).first, !product.isFinished else { return .result() }

        if SharedStore.isDone(product, slot) {
            product.undoRoutine(slot)
        } else {
            // 记到 0 时不在这里移进空瓶：回到 App 时会播放"用完了"并询问补货
            product.logRoutine(slot)
        }
        try context.save()
        SharedStore.noteExternalChange()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
