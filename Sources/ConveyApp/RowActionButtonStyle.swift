import SwiftUI

/// A compact button style for clipboard-row actions (convert, save, delete).
/// Lights up on hover with a tinted background + brighter foreground.
struct RowActionButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, tint: tint)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? tint.opacity(0.18) : Color.clear)
                )
                .foregroundStyle(hovering ? tint : Color.secondary)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeInOut(duration: 0.12), value: hovering)
        }
    }
}
