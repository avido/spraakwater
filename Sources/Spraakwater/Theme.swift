import SwiftUI

/// Brand colors taken from the artwork: the red of the microphone, warm ink and the cream of the speech bubble.
enum Theme {
    static let red = Color(red: 0.86, green: 0.15, blue: 0.17)
    static let ink = Color(red: 0.075, green: 0.063, blue: 0.055)
    static let cream = Color(red: 0.965, green: 0.94, blue: 0.894)

    /// Mixes cream toward red, used for the spectrum bars so loud moments glow.
    static func heat(_ amount: Double) -> Color {
        let t = max(0, min(1, amount))
        return Color(
            red: 0.965 + (0.86 - 0.965) * t,
            green: 0.94 + (0.15 - 0.94) * t,
            blue: 0.894 + (0.17 - 0.894) * t
        )
    }
}

/// One keycap, used to show the dictation shortcut.
struct KeyCap: View {
    let symbol: String
    var large = false

    var body: some View {
        Text(symbol)
            .font(.system(size: large ? 15 : 11, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, large ? 9 : 6)
            .frame(minWidth: large ? 30 : 22, minHeight: large ? 28 : 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
    }
}

extension AppController.Phase {
    var title: String {
        switch self {
        case .idle: "Klaar"
        case .recording: "Aan het opnemen"
        case .processing: "Bezig met transcriberen"
        }
    }
}
