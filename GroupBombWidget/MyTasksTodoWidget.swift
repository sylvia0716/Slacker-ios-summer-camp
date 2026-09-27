import SwiftUI
import WidgetKit

struct MyTasksTodoEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetTodoSnapshot
}

struct MyTasksTodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> MyTasksTodoEntry {
        MyTasksTodoEntry(date: .now, snapshot: WidgetTodoSnapshot(count: 0, items: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (MyTasksTodoEntry) -> Void) {
        completion(currentEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MyTasksTodoEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private var currentEntry: MyTasksTodoEntry {
        MyTasksTodoEntry(
            date: .now,
            snapshot: WidgetSnapshotStore.currentTodo ?? WidgetTodoSnapshot(count: 0, items: [])
        )
    }
}

struct MyTasksTodoWidget: Widget {
    let kind = "MyTasksTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MyTasksTodoProvider()) { entry in
            MyTasksTodoWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(WidgetLanguage.text("我的待辦", "My To-Dos")))
        .description(Text(WidgetLanguage.text("查看我的任務中尚未完成的子任務。", "See unfinished items from My Tasks.")))
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

private struct MyTasksTodoWidgetView: View {
    let entry: MyTasksTodoEntry
    private let yellow = Color(red: 1, green: 0.79, blue: 0.05)
    private let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
    private let paper = Color(red: 0.96, green: 0.92, blue: 0.79)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(entry.snapshot.count)")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(WidgetLanguage.text("我的待辦", "My To-Dos"))
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: "bolt.fill")
                    .font(.title3.weight(.black))
                    .foregroundStyle(yellow)
                    .frame(width: 42, height: 42)
                    .background(ink, in: Circle())
                    .accessibilityHidden(true)
            }

            Rectangle()
                .fill(ink)
                .frame(height: 2)
                .padding(.top, 10)
                .padding(.bottom, 10)

            if entry.snapshot.count == 0 {
                Text(WidgetLanguage.text("目前沒有待辦事項", "No to-dos"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.snapshot.items) { item in
                        HStack(spacing: 12) {
                            Circle()
                                .strokeBorder(ink, lineWidth: 2)
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                            Text(item.title)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 38)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .foregroundStyle(ink)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(ink)
                    .offset(x: 4, y: 4)
                RoundedRectangle(cornerRadius: 18)
                    .fill(paper)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ink, lineWidth: 3))
        .padding(.trailing, 4)
        .padding(.bottom, 4)
        .padding(14)
        .widgetURL(URL(string: "oopsbomb://my-tasks"))
        .containerBackground(for: .widget) { yellow }
    }
}
