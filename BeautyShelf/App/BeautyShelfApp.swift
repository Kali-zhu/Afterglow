import SwiftUI
import SwiftData

@main
struct BeautyShelfApp: App {
    var body: some Scene {
        WindowGroup {
            ShelfView()
        }
        .modelContainer(for: Product.self)
    }
}
