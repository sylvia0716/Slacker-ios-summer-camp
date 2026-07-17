import SwiftUI
import WidgetKit

/// Snapshot of the minimum group information a Home Screen widget needs to display.
/// Future work: read this value from an App Group shared by the main app and widget extension.
struct GroupProgressEntry: TimelineEntry {
    let date: Date
    let groupName: String
    let progress: Int
    let deadline: Date
}

/// Supplies mock timeline data for the MVP widget.
/// Future work: replace the hard-coded snapshot with a shared WidgetSnapshot service.
struct GroupProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> GroupProgressEntry {
        sampleEntry
    }

    func getSnapshot(in context: Context, completion: @escaping (GroupProgressEntry) -> Void) {
        completion(sampleEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GroupProgressEntry>) -> Void) {
        let entry = sampleEntry
        let refreshDate = Date.now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
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

            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.progress)%")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                Spacer()
                Text(entry.deadline, style: .timer)
                    .font(.caption.weight(.bold))
                    .multilineTextAlignment(.trailing)
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
}
