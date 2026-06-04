import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "text.bubble")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            Text("Transtype")
                .font(.title2.weight(.semibold))

            Text("Right-click inside any app text field to translate as you type. Pick a target language, keep typing, then press ↓ to replace the original text with the translation.")
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
