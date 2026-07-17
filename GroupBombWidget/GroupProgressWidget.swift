import SwiftUI
import WidgetKit

struct GroupProgressEntry: TimelineEntry {
    let date: Date
    let groupName: String
    let progress: Int
    let deadline: Date
}

struct GroupProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> GroupProgressEntry {
        sampleEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (GroupProgressEntry) -> Void) {
        completion(currentEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GroupProgressEntry>) -> Void) {
        let entry = currentEntry
        let refreshDate = min(entry.deadline, Date.now.addingTimeInterval(15 * 60))
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private var currentEntry: GroupProgressEntry {
        guard let snapshot = WidgetSnapshotStore.current else { return sampleEntry }
        return GroupProgressEntry(
            date: .now,
            groupName: snapshot.groupName,
            progress: snapshot.progress,
            deadline: snapshot.deadline
        )
    }

    private var sampleEntry: GroupProgressEntry {
        GroupProgressEntry(
            date: .now,
            groupName: "期末報告拆彈小隊",
            progress: 52,
            deadline: .now.addingTimeInterval(48 * 60 * 60)
        )
    }
}

/// Home Screen widget showing the current group's deadline and project progress.
struct GroupProgressWidget: Widget {
    let kind = "GroupProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GroupProgressProvider()) { entry in
            GroupProgressWidgetView(entry: entry)
        }
        .configurationDisplayName("拆彈進度")
        .description("快速查看小組報告的倒數與整體進度。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

/// Widget presentation only. Keep the data and timeline policy in GroupProgressProvider.
private struct GroupProgressWidgetView: View {
    let entry: GroupProgressEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                Text("GROUP BOMB")
                    .font(.caption.weight(.black))
                Spacer()
                Text("LIVE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.red)
            }

            Text(entry.groupName)
                .font(.headline.weight(.black))
                .lineLimit(1)

            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(entry.progress)%")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Spacer()
                    Label(remainingTime(at: context.date), systemImage: "timer")
                        .font(.caption.weight(.bold))
                        .labelStyle(.titleAndIcon)
                }
            }

            ProgressView(value: Double(entry.progress), total: 100)
                .tint(.yellow)
        }
        .padding(18)
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            Color(red: 0.08, green: 0.08, blue: 0.07)
        }
    }

    private func remainingTime(at date: Date) -> String {
        let remaining = max(0, Int(entry.deadline.timeIntervalSince(date)))
        let days = remaining / 86_400
        let hours = remaining % 86_400 / 3_600

        if remaining == 0 {
            return "已截止"
        }

        if days > 0 {
            return "剩 \(days) 天"
        }

        return "剩 \(hours) 小時"
    }
}
