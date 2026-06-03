import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            Text("OpenTransType")
                .font(.title2.weight(.semibold))

            Text("在任意 App 的文本框中右键，开启边写边译。选择目标语言后继续输入，按 ↓ 用译文覆盖原文。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 360)
    }
}

#Preview {
    ContentView()
}
