import SwiftUI

enum Brand {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0, green: 0.83, blue: 1, alpha: 1) : UIColor(red: 0, green: 0.467, blue: 0.80, alpha: 1)
    })
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.02, green: 0.05, blue: 0.12, alpha: 1) : UIColor(red: 0.933, green: 0.949, blue: 0.980, alpha: 1)
    })
    static let input = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.28) : UIColor.white.withAlphaComponent(0.95)
    })
    static func ui(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        let face = weight == .heavy ? "ExtraBold" : weight == .bold ? "Bold" : weight == .semibold ? "SemiBold" : "Regular"
        return .custom("Outfit-" + face, size: size(style), relativeTo: style)
    }
    static func number(_ style: Font.TextStyle = .body) -> Font { .custom("JetBrainsMono-Regular", size: size(style), relativeTo: style) }
    private static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style { case .largeTitle: 34; case .title: 28; case .title2: 22; case .title3: 20; case .caption: 12; case .subheadline: 15; default: 17 }
    }
}

struct MoneyLabel: View {
    let cents: Int
    var style: Font.TextStyle = .body
    var body: some View { Text(Money.text(cents)).font(Brand.number(style)).monospacedDigit().fixedSize(horizontal: false, vertical: true) }
}

struct TabCard: View {
    let tab: TabSnapshot
    let open: () -> Void
    @State private var icon = "🧾"
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Menu {
                ForEach(["🧾", "✈️", "🍕", "🏠", "🎉", "🥂", "🏖️", "🍽️", "🚗", "⛺️", "🎿", "💸"], id: \.self) { emoji in
                    Button(emoji) { icon = emoji; UserDefaults.standard.set(emoji, forKey: "icon-\(tab.id)") }
                }
            } label: {
                Text(icon).font(.title2).frame(width: 44, height: 44)
                    .background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }.accessibilityLabel("Change tab icon")
            Button(action: open) {
                HStack {
                VStack(alignment: .leading, spacing: 5) {
                Text(tab.name).font(Brand.ui(.subheadline, weight: .semibold))
                Text("\(tab.people.count) people · \(tab.expenses.count) expenses").font(Brand.ui(.caption)).foregroundStyle(.secondary)
                MoneyLabel(cents: tab.total, style: .subheadline).foregroundStyle(Brand.accent)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.onAppear { icon = UserDefaults.standard.string(forKey: "icon-\(tab.id)") ?? "🧾" }
    }
}


struct WebCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.10)))
    }
}

extension View {
    func webCard() -> some View { modifier(WebCard()) }
    func webInput() -> some View {
        padding(12).background(Brand.input, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct WebButton: ButtonStyle {
    var primary = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Brand.ui(.subheadline, weight: .semibold))
            .padding(.horizontal, 16).frame(minHeight: 46)
            .foregroundStyle(primary ? Color(red: 0.02, green: 0.05, blue: 0.12) : Brand.accent)
            .background(primary ? Brand.accent : Brand.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct BrandHeader: View {
    @AppStorage("appearance") private var appearance = "Dark"
    let home: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button(action: home) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up").font(.system(size: 23, weight: .heavy))
                        .foregroundStyle(Brand.background).frame(width: 36, height: 36)
                        .background(Brand.accent, in: RoundedRectangle(cornerRadius: 10))
                    (Text("Settling").foregroundStyle(Color.primary) + Text("Up").foregroundStyle(Brand.accent))
                        .font(Brand.ui(.title2, weight: .bold))
                }
            }.buttonStyle(.plain).accessibilityLabel("SettlingUp home")
            Spacer()
            Button { appearance = appearance == "Light" ? "Dark" : "Light" } label: {
                Image(systemName: appearance == "Light" ? "sun.max" : "moon").frame(width: 44, height: 44)
            }.accessibilityLabel("Switch theme")
        }
    }
}

struct StepProgress: View {
    let step: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { index in
                Capsule().fill(index <= step ? Brand.accent : Color.primary.opacity(0.12)).frame(height: 3).opacity(index == step ? 0.55 : 1)
            }
        }.accessibilityLabel("Step \(step + 1) of 4")
    }
}

struct PersonPill: View {
    let name: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(String(name.prefix(1)).uppercased()).font(Brand.ui(.caption, weight: .bold))
                    .frame(width: 24, height: 24).background(Brand.accent.opacity(0.15), in: Circle())
                Text(name).font(Brand.ui(.subheadline))
                if selected { Image(systemName: "checkmark").font(.caption) }
            }.frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8)
                .background(selected ? Brand.accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.12)))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}


struct WebSegment: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Brand.ui(.subheadline, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? Brand.accent : Color.secondary)
            .background(selected ? Brand.accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.10)))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
