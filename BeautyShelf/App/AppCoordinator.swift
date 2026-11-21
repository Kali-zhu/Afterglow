import SwiftUI
import Observation

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
    enum Tab: Hashable { case shelf, today, finished }

    var tab: Tab = .shelf
    var editor: EditorTarget? = nil
    /// 正在播放"倒空"动画的产品
    var finishing: Product? = nil
    /// 倒空后询问"要加入补货清单吗？"
    var restockPrompt: Product? = nil
    var showSettings = false

    /// 记一次使用；剩余归零时自动进入"用完了"流程
    func logUse(_ p: Product) {
        guard !p.isFinished else { return }
        p.logUse()
        finishIfEmpty(p)
    }

    func logRoutine(_ p: Product, _ slot: RoutineSlot) {
        guard !p.isFinished else { return }
        p.logRoutine(slot)
        finishIfEmpty(p)
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
    }

    private func finishIfEmpty(_ p: Product) {
        if p.measureMode != .estimate && p.remainingAmount <= 0.0001 {
            finish(p)
        }
    }
}
