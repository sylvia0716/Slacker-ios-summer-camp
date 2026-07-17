import SwiftUI
import UIKit

/// Renders either the selected profile photo or the current fallback SF Symbol.
struct ProfileAvatarImage: View {
    let data: Data?
    let fallbackSymbol: String

    @ViewBuilder
    var body: some View {
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            ZStack {
                BombTheme.ink
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(.white)
            }
            .clipped()
        }
    }
}
