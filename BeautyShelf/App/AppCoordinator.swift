import SwiftUI
import SwiftData
import Observation
import WidgetKit

/// 添加 / 编辑表单的目标
enum EditorTarget: Identifiable {
    case new
    case edit(Product)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let p): p.uid.uuidString
        }
    }
}

/// 跨标签页共享的界面状态：表单、"用完了"倒空动画、补货询问、设置。
@Observable
final class AppCoordinator {
    enum Tab: Hashable { case shelf, today, finished, me }

    var tab: Tab = .today
    var editor: EditorTarget? = nil
    /// 正在播放"倒空"动画的产品
    var finishing: Product? = nil
    /// 倒空后询问"要加入补货清单吗？"
    var restockPrompt: Product? = nil
    var showSettings = false
    /// 全屏详情：所有"用一件产品"的入口都打开它，在详情里点"用了一次"才真正记录
    var detail: Product? = nil
    /// 一起记多件时，详情页里排在后面、可以左右滑动的另外几件（第一件是 `detail`）
    var detailPeers: [Product] = []

    /// 当前界面用的 ModelContext（MainTabView 出现 / 切换时设置），用于保存后刷新小组件
    @ObservationIgnored weak var context: ModelContext?
    @ObservationIgnored private var reloadTask: Task<Void, Never>? = nil

    // MARK: 数据变化 → 保存 + 刷新小组件（唯一入口）

    /// 任何会影响小组件的修改之后调用。连续调用会合并成一次（0.6 秒防抖）。
    func dataChanged() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveAndReloadWidgets()
        }
    }

    /// 立刻保存并刷新（例如 App 进入后台时）
    func saveAndReloadWidgets() {
        reloadTask?.cancel()
        reloadTask = nil
        if let context, context.hasChanges { try? context.save() }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 记一次使用；剩余归零时自动进入"用完了"流程
    func logUse(_ p: Product) {
        guard !p.isFinished else { return }
        p.logUse()
        finishIfEmpty(p)
        dataChanged()
    }

    func logRoutine(_ p: Product, _ slot: RoutineSlot) {
        guard !p.isFinished else { return }
        p.logRoutine(slot)
        finishIfEmpty(p)
        dataChanged()
    }

    func undoRoutine(_ p: Product, _ slot: RoutineSlot) {
        p.undoRoutine(slot)
        dataChanged()
    }

    /// 流程顺序存在 App Group 里，小组件按同样顺序显示
    func setOrder(_ products: [Product], for slot: RoutineSlot) {
        SharedStore.setOrder(products.map { $0.uid.uuidString }, for: slot)
        dataChanged()
    }

    /// 打开一件产品的详情（"用一次"的唯一入口）
    func openDetail(_ p: Product) {
        guard !p.isDeleted else { return }
        detailPeers = []
        detail = p
    }

    /// 一起记多件：还是同一个详情页，几件产品像卡片一样左右滑动
    func openDetail(_ p: Product, also peers: [Product]) {
        guard !p.isDeleted else { return }
        detailPeers = peers.filter { !$0.isDeleted && $0.uid != p.uid }
        detail = p
    }

    func closeDetail() {
        detail = nil
        detailPeers = []
    }

    /// 小组件里记到 0 的产品：回到 App 时补上"用完了"流程
    func finishDrainedProducts(_ products: [Product]) {
        guard finishing == nil, restockPrompt == nil else { return }
        if let p = products.first(where: { !$0.isFinished && $0.measureMode != .estimate && $0.remainingAmount <= 0.0001 }) {
            finish(p)
        }
    }

    func finish(_ p: Product) {
        guard finishing == nil, !p.isFinished else { return }
        finishing = p
    }

    /// 倒空动画播完
    func completeFinish(_ p: Product) {
        p.markFinished()
        finishing = nil
        restockPrompt = p
        dataChanged()
    }

    private func finishIfEmpty(_ p: Product) {
        if p.measureMode != .estimate && p.remainingAmount <= 0.0001 {
            finish(p)
        }
    }
}
