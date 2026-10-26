import SwiftUI
import UIKit

struct ExplosionMemeOverlay: View {
    let groupName: String
    let progress: Int
    let incompleteTaskCount: Int
    let onDismiss: () -> Void
    @State private var shareImage: Image?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BombTheme.ink.opacity(0.6)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(.title, weight: .black))
                                .foregroundStyle(BombTheme.red)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.text("任務爆炸"))
                                    .font(.system(.title, design: .rounded, weight: .black))
                                Text(L10n.text("截止時間已到"))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            BombCloseButton(label: L10n.text("關閉梗圖"), action: onDismiss)
                        }

                        FailureMemeImage(
                            groupName: groupName,
                            progress: progress,
                            incompleteTaskCount: incompleteTaskCount
                        )
                            .frame(
                                width: min(340, proxy.size.width - 64),
                                height: min(340, proxy.size.width - 64)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: BombRadius.panel))
                            .overlay(
                                RoundedRectangle(cornerRadius: BombRadius.panel)
                                    .stroke(BombTheme.ink, lineWidth: 2)
                            )
                            .accessibilityLabel(L10n.text("爆炸專案梗圖"))

                        VStack(spacing: 9) {
                            Text(groupName)
                                .font(.system(.title3, design: .rounded, weight: .black))
                                .multilineTextAlignment(.center)

                            HStack(spacing: 12) {
                                Text(L10n.format("完成率 {0}%", String(describing: progress)))
                                Text("｜")
                                    .foregroundStyle(.secondary)
                                Text(L10n.format("未完成任務 {0} 項", String(describing: incompleteTaskCount)))
                            }
                            .font(.subheadline.weight(.black))
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(BombTheme.yellow.opacity(0.32))
                        .clipShape(RoundedRectangle(cornerRadius: BombRadius.control))
                        .overlay(RoundedRectangle(cornerRadius: BombRadius.control).stroke(BombTheme.ink, lineWidth: 2))

                        Text(L10n.text("本次任務未能如期完成，\n請查看團隊戰報並完成匿名隊員互評。"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.76))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if let shareImage {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview(L10n.format("{0} 任務結算", String(describing: groupName)), image: shareImage)
                            ) {
                                Label(L10n.text("分享梗圖"), systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(BombTheme.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BombTheme.yellow)
                                    .clipShape(.capsule)
                                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }

                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .background(BombTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: BombRadius.panel))
                .overlay(RoundedRectangle(cornerRadius: BombRadius.panel).stroke(BombTheme.ink, lineWidth: 3))
                .frame(maxWidth: 560)
                .frame(maxHeight: max(320, proxy.size.height - 64))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .task {
            shareImage = renderedShareImage
        }
    }

    @MainActor
    private var renderedShareImage: Image? {
        let renderer = ImageRenderer(
            content: FailureMemeImage(
                groupName: groupName,
                progress: progress,
                incompleteTaskCount: incompleteTaskCount
            )
            .frame(width: 340, height: 340)
        )

        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}

struct FailureMemeImage: View {
    let groupName: String
    let progress: Int
    let incompleteTaskCount: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("ExplosionMemeProject")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: 0) {
                    MemeCaption(text: groupName, fontSize: proxy.size.width * 0.08)
                        .frame(width: proxy.size.width * 0.70)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: 30)
                    Spacer()
                    MemeCaption(
                        text: L10n.text("已讀不回的組員"),
                        fontSize: proxy.size.width * 0.05
                    )
                    // Keep this caption to the right of the person's face.
                    .frame(width: proxy.size.width * 0.50)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: 15)
                    Spacer()
                    MemeCaption(text: L10n.text("我要放暑假了！"), fontSize: proxy.size.width * 0.07)
                        .frame(width: proxy.size.width * 0.64)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: -20)
                }
                .padding(.vertical, proxy.size.height * 0.08)
                .padding(.horizontal, proxy.size.width * 0.06)
            }
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(L10n.format("{0} 的任務爆炸梗圖，完成率 {1}%，尚有 {2} 項任務未完成", String(describing: groupName), String(describing: progress), String(describing: incompleteTaskCount)))
    }
}

struct SuccessMemeOverlay: View {
    let groupName: String
    let onDismiss: () -> Void
    @State private var shareImage: Image?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                BombTheme.ink.opacity(0.6)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(.title, weight: .black))
                                .foregroundStyle(BombTheme.green)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.text("成功拆彈"))
                                    .font(.system(.title, design: .rounded, weight: .black))
                                Text(L10n.text("任務已全數完成"))
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            BombCloseButton(label: L10n.text("關閉梗圖"), action: onDismiss)
                        }

                        SuccessMemeImage(groupName: groupName)
                            .frame(maxWidth: min(260, proxy.size.width - 64))
                            .accessibilityLabel(L10n.text("成功拆彈梗圖"))

                        Text(L10n.text("這次任務如期完成，\n請完成匿名隊員互評。"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BombTheme.ink.opacity(0.76))
                            .multilineTextAlignment(.center)

                        if let shareImage {
                            ShareLink(
                                item: shareImage,
                                preview: SharePreview(L10n.format("{0} 成功拆彈", String(describing: groupName)), image: shareImage)
                            ) {
                                Label(L10n.text("分享梗圖"), systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.black))
                                    .foregroundStyle(BombTheme.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BombTheme.yellow)
                                    .clipShape(.capsule)
                                    .overlay(Capsule().stroke(BombTheme.ink, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }

                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
                .background(BombTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: BombRadius.panel))
                .overlay(RoundedRectangle(cornerRadius: BombRadius.panel).stroke(BombTheme.ink, lineWidth: 3))
                .frame(maxWidth: 560)
                .frame(maxHeight: max(320, proxy.size.height - 64))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .task {
            shareImage = renderedShareImage
        }
    }

    @MainActor
    private var renderedShareImage: Image? {
        let renderer = ImageRenderer(
            content: SuccessMemeImage(groupName: groupName)
                .frame(width: 260, height: 425.1)
        )

        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}

struct SuccessMemeImage: View {
    let groupName: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("SuccessMemeProject")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                VStack(spacing: 0) {
                    MemeCaption(text: L10n.text("你有多猛"), fontSize: proxy.size.width * 0.09)
                        .offset(y: 140)
                    Spacer()
                    MemeCaption(
                        text: L10n.format("我完成了{0}", String(describing: groupName)),
                        fontSize: proxy.size.width * 0.075
                    )
                    .offset(y: 30)
                }
                .padding(.vertical, proxy.size.height * 0.1)
                .padding(.horizontal, proxy.size.width * 0.06)
            }
            .clipped()
        }
        .aspectRatio(600.0 / 981.0, contentMode: .fit)
        .accessibilityLabel(L10n.format("{0} 的成功拆彈梗圖", String(describing: groupName)))
    }
}

struct MemeCaption: View {
    let text: String
    let fontSize: CGFloat

    private let outlineOffsets: [CGFloat] = [-2, 0, 2]

    var body: some View {
        ZStack {
            ForEach(outlineOffsets, id: \.self) { horizontalOffset in
                ForEach(outlineOffsets, id: \.self) { verticalOffset in
                    if horizontalOffset != 0 || verticalOffset != 0 {
                        caption
                            .foregroundStyle(.black)
                            .offset(x: horizontalOffset, y: verticalOffset)
                    }
                }
            }

            caption
                .foregroundStyle(.white)
        }
        .padding(.horizontal, fontSize * 0.18)
    }

    private var caption: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .lineLimit(2)
    }
}
