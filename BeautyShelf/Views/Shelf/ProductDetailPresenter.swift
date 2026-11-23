import SwiftUI
import SwiftData

/// "用一件产品"的唯一入口：不管从首页、藏品、空瓶还是近期记录点开，
/// 都由这里全屏呈现同一个 `ProductDetailView`。
/// iOS 18 用系统缩放转场：卡片里的产品图放大成详情页的大图；更早的系统直接全屏。
struct ProductDetailPresenter: ViewModifier {
    let coordinator: AppCoordinator
    let detail: Binding<Product?>
    let ns: Namespace.ID

    @Environment(\.modelContext) private var context

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            content.fullScreenCover(item: detail) { p in
                scene(p)
                    .navigationTransition(.zoom(sourceID: p.uid, in: ns))
            }
        } else {
            fullCover(content)
        }
        #else
        fullCover(content)
        #endif
    }

    private func fullCover(_ content: Content) -> some View {
        content.fullScreenCover(item: detail) { p in
            scene(p)
        }
    }

    private func scene(_ p: Product) -> some View {
        ProductDetailView(product: p) { detail.wrappedValue = nil }
            .environment(coordinator)
            .modelContext(context)
    }
}

// MARK: - 共享元素：卡片里的产品图 → 详情页大图

private struct DetailNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// 由根视图提供，所有能打开详情页的卡片的共享元素都用它
    var detailNamespace: Namespace.ID? {
        get { self[DetailNamespaceKey.self] }
        set { self[DetailNamespaceKey.self] = newValue }
    }
}

struct DetailTransitionSource: ViewModifier {
    let id: UUID
    @Environment(\.detailNamespace) private var ns

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let ns {
            content.matchedTransitionSource(id: id, in: ns)
        } else {
            content
        }
    }
}

extension View {
    /// 标记"这张卡片里的产品图会放大成详情页的大图"（iOS 18 缩放转场）
    func detailTransitionSource(id: UUID) -> some View {
        modifier(DetailTransitionSource(id: id))
    }
}
