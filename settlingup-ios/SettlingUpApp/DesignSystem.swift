import SwiftUI

enum Brand {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0, green: 0.83, blue: 1, alpha: 1) : UIColor(red: 0, green: 0.40, blue: 0.68, alpha: 1)
    })
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.02, green: 0.05, blue: 0.12, alpha: 1) : .systemGroupedBackground
    })
    static func ui(_ style: Font.TextStyle = .body) -> Font { .custom("Outfit-Regular", size: size(style), relativeTo: style) }
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
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.2.fill").font(.title2).foregroundStyle(Brand.accent)
                .frame(width: 48, height: 48).background(Brand.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(tab.name).font(Brand.ui(.title3).weight(.semibold))
                Text("\(tab.people.count) people · \(tab.expenses.count) expenses").font(Brand.ui(.subheadline)).foregroundStyle(.secondary)
                MoneyLabel(cents: tab.total).foregroundStyle(Brand.accent)
            }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
