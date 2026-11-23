import SwiftUI
import SwiftData

/// 底部三个标签：妆台 / 今日 / 空瓶
struct MainTabView: View {
    let startWithAdd: Bool

    @State private var coordinator = AppCoordinator()
    @Query private var products: [Product]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.onboarded) private var onboarded = false

    init(startWithAdd: Bool = false) {
        self.startWithAdd = startWithAdd
    }

    var body: some View {
        TabView(selection: $coordinator.tab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max") }
                .tag(AppCoordinator.Tab.today)
            ShelfView()
                .tabItem { Label("藏品", systemImage: "square.stack.3d.up") }
                .tag(AppCoordinator.Tab.shelf)
            FinishedView()
                .tabItem { Label("空瓶", systemImage: "archivebox") }
                .tag(AppCoordinator.Tab.finished)
        }
        .environment(coordinator)
        .overlay {
            if let p = coordinator.finishing {
                FinishOverlay(product: p) {
                    withAnimation(Theme.spring) { coordinator.completeFinish(p) }
                    NotificationService.reschedule(products: products)
                }
                .transition(.opacity)
            }
        }
        .sheet(item: $coordinator.editor) { target in
            ProductEditorView(target: target)
                .environment(coordinator)
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView()
                .environment(coordinator)
        }
        .alert("要加入补货清单吗？", isPresented: restockBinding, presenting: coordinator.restockPrompt) { p in
            Button("加入补货清单") { p.needsRestock = true }
            if p.backupStock > 0 {
                Button("开一瓶备用的（还有 \(p.backupStock) 件）") { openBackup(of: p) }
            }
            Button("不用了", role: .cancel) {}
        } message: { p in
            Text("「\(p.name)」已移入空瓶，用了 \(p.useCount) 次。")
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                NotificationService.reschedule(products: products)
                coordinator.saveAndReloadWidgets()
            case .active:
                coordinator.finishDrainedProducts(products)
            default:
                break
            }
        }
        // 任何页面（妆台、详情、表单、设置）改了会影响小组件的数据 → 防抖保存并刷新小组件
        .onChange(of: widgetSignature) { coordinator.dataChanged() }
        .onChange(of: ObjectIdentifier(context)) {
            // 小组件改过数据、换了新上下文：记到 0 的产品补上"用完了"
            coordinator.context = context
            coordinator.finishDrainedProducts(products)
        }
        .task {
            coordinator.context = context
            SampleData.attachMissingCutouts(in: context)
            SharedStore.consumeExternalChange()
            coordinator.finishDrainedProducts(products)
            onboarded = true
            NotificationService.reschedule(products: products)
            if startWithAdd {
                try? await Task.sleep(for: .milliseconds(450))
                coordinator.editor = .new
            }
        }
    }

    /// 小组件会显示的字段的指纹：变了就刷新小组件
    private var widgetSignature: Int {
        var h = Hasher()
        for p in products {
            h.combine(p.uid)
            h.combine(p.name)
            h.combine(p.remainingAmount)
            h.combine(p.useCount)
            h.combine(p.finishedDate)
            h.combine(p.inMorning)
            h.combine(p.inEvening)
            h.combine(p.expiryDate)
            h.combine(p.openedDate)
            h.combine(p.paoMonths)
            h.combine(p.tintHex)
            h.combine(p.kindRaw)
        }
        return h.finalize()
    }

    private var restockBinding: Binding<Bool> {
        Binding(get: { coordinator.restockPrompt != nil },
                set: { if !$0 { coordinator.restockPrompt = nil } })
    }

    /// 用完后直接开一瓶备用的：新建一件今天开封的同款，备用库存减一
    private func openBackup(of p: Product) {
        let fresh = p.makeFreshCopy(openNow: true)
        fresh.backupStock = max(0, p.backupStock - 1)
        p.backupStock = 0
        withAnimation(Theme.spring) { context.insert(fresh) }
        coordinator.dataChanged()
    }
}
