import SwiftUI
import DesignSystem

struct ContentView: View {
    @Environment(\.colorPalette) private var colors

    var body: some View {
        TabView {
            Tab("チャット", systemImage: "bubble.left.and.text.bubble.right") {
                ChatView()
            }
            Tab("モデル", systemImage: "arrow.down.circle") {
                ModelListView()
            }
            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(colors.primary)
    }
}
