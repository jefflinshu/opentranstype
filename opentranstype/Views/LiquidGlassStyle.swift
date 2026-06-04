import SwiftUI

extension View {
    func liquidGlassWindowPanel(cornerRadius: CGFloat = 18) -> some View {
        modifier(LiquidGlassWindowPanelModifier(cornerRadius: cornerRadius))
    }

    func liquidGlassPanel(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius))
    }
}

private struct LiquidGlassWindowPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(windowFill)
                    .overlay { shape.fill(.ultraThinMaterial) }
            }
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(borderGradient, lineWidth: 1)
            }
            .clipShape(shape)
    }

    private var windowFill: Color {
        Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.82 : 0.92)
    }

    private var borderGradient: LinearGradient {
        LiquidGlassColors.borderGradient(for: colorScheme)
    }
}

private struct LiquidGlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(.ultraThinMaterial, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(LiquidGlassColors.borderGradient(for: colorScheme), lineWidth: 1)
            }
            .clipShape(shape)
    }
}

private enum LiquidGlassColors {
    static func borderGradient(for colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color]

        if colorScheme == .dark {
            colors = [
                .white.opacity(0.24),
                .white.opacity(0.10),
                .black.opacity(0.20)
            ]
        } else {
            colors = [
                .white.opacity(0.72),
                .white.opacity(0.26),
                .primary.opacity(0.10)
            ]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
