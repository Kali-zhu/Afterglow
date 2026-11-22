import WidgetKit
import SwiftUI

/// 妆台的小组件：今晚该用（可勾选）、快过期（含锁屏）
@main
struct BeautyShelfWidgets: WidgetBundle {
    var body: some Widget {
        RoutineWidget()
        ExpiryWidget()
    }
}
