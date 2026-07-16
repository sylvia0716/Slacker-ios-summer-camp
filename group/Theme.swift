import SwiftUI

enum BombTheme {
    static let yellow = Color(red: 1, green: 0.79, blue: 0.05)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
    static let paper = Color(red: 0.96, green: 0.92, blue: 0.79)
    static let red = Color(red: 0.86, green: 0.17, blue: 0.12)
    static let green = Color(red: 0.16, green: 0.55, blue: 0.32)
}

struct ComicCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).background(BombTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BombTheme.ink, lineWidth: 3))
            .shadow(color: BombTheme.ink, radius: 0, x: 5, y: 5)
    }
}

extension View { func comicCard() -> some View { modifier(ComicCard()) } }

struct HazardStripe: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { index in
                Rectangle().fill(index.isMultiple(of: 2) ? BombTheme.yellow : BombTheme.ink)
            }
        }.frame(height: 10)
    }
}
