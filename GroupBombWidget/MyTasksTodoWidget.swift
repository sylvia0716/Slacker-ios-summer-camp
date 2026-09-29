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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private struct MyTasksTodoWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: MyTasksTodoEntry
    private let yellow = Color(red: 1, green: 0.79, blue: 0.05)
    private let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
    private let paper = Color(red: 0.96, green: 0.92, blue: 0.79)

    private var isSmall: Bool { family == .systemSmall }
    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isLarge {
                compactContent
            } else {
                largeContent
            }
        }
        .foregroundStyle(ink)
        .padding(isLarge ? 16 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(ink)
                    .offset(x: isLarge ? 4 : 2, y: isLarge ? 4 : 2)
                RoundedRectangle(cornerRadius: 18)
                    .fill(paper)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ink, lineWidth: isLarge ? 3 : 2))
        .padding(.trailing, isLarge ? 4 : 2)
        .padding(.bottom, isLarge ? 4 : 2)
        .padding(isLarge ? 12 : 6)
        .widgetURL(URL(string: "oopsbomb://my-tasks"))
        .containerBackground(for: .widget) { yellow }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isSmall {
                HStack(alignment: .center, spacing: 6) {
                    Text("\(entry.snapshot.count)")
                        .font(.system(size: isLarge ? 38 : 24, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(WidgetLanguage.text("我的待辦", "My To-Dos"))
                        .font(.system(size: 16, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: isLarge ? 17 : 12, weight: .black))
                        .foregroundStyle(yellow)
                        .frame(width: isLarge ? 36 : 24, height: isLarge ? 36 : 24)
                        .background(ink, in: Circle())
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WidgetLanguage.text(
                    "我的待辦，\(entry.snapshot.count) 項", "My To-Dos, \(entry.snapshot.count) items"
                ))

                Rectangle()
                    .fill(ink)
                    .frame(height: 2)
                    .padding(.top, isLarge ? 8 : 4)
                    .padding(.bottom, isLarge ? 18 : 6)
            }

            if entry.snapshot.count == 0 {
                Text(WidgetLanguage.text("目前沒有待辦事項", "No to-dos"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ViewThatFits(in: .vertical) {
                    // Keep complete rows and their context when the system offers less height.
                    if isLarge {
                        todoList(limit: 4)
                        todoList(limit: 3)
                    }
                    todoList(limit: 2)
                    todoList(limit: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isSmall {
                Text("\(WidgetLanguage.text("我的待辦", "My To-Dos")) · \(entry.snapshot.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.65))
                    .lineLimit(1)
            }

            if entry.snapshot.count == 0 {
                Text(WidgetLanguage.text("目前沒有待辦事項", "No to-dos"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.7))
            } else {
                ViewThatFits(in: .vertical) {
                    if !isSmall {
                        compactList(limit: 2)
                    }
                    compactList(limit: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func compactList(limit: Int) -> some View {
        let items = Array(entry.snapshot.items.prefix(limit))
        let remaining = max(0, entry.snapshot.count - items.count)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: isSmall ? 17 : 15, weight: .bold))
                        .lineLimit(isSmall ? 2 : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(isSmall ? item.taskTitle : [item.taskTitle, item.groupName]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ink.opacity(0.6))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([item.groupName, item.taskTitle, item.title]
                    .filter { !$0.isEmpty }.joined(separator: ", "))
            }
            if remaining > 0 {
                Text(WidgetLanguage.text("還有 \(remaining) 項", "+\(remaining) more"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ink.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func todoList(limit: Int) -> some View {
        let items = Array(entry.snapshot.items.prefix(limit))
        let remaining = max(0, entry.snapshot.count - items.count)

        let sections = items.reduce(into: [TodoSection]()) { sections, item in
            if sections.last?.id == item.taskID {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(TodoSection(id: item.taskID, items: [item]))
            }
        }

        return VStack(alignment: .leading, spacing: isLarge ? 12 : 6) {
            ForEach(sections) { section in
                if let firstItem = section.items.first {
                    VStack(alignment: .leading, spacing: isLarge ? 10 : 5) {
                        taskHeading(firstItem)
                        VStack(spacing: isLarge ? 4 : 3) {
                            ForEach(section.items) { item in
                                todoRow(item)
                            }
                        }
                        .padding(.leading, isLarge ? 12 : 8)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(yellow)
                                .frame(width: 2)
                        }
                    }
                }
            }
            if remaining > 0 {
                Text(WidgetLanguage.text("還有 \(remaining) 項", "+\(remaining) more"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ink.opacity(0.6))
                    .lineLimit(1)
                    .padding(.top, isLarge ? 6 : 2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private struct TodoSection: Identifiable {
        let id: UUID
        var items: [WidgetTodoItem]
    }

    private func taskHeading(_ item: WidgetTodoItem) -> some View {
        let layout = isSmall
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        return layout {
            Text(item.taskTitle)
                .font(.system(size: isLarge ? 17 : 13, weight: .black))
                .lineLimit(1)
            if !item.groupName.isEmpty {
                groupLabel(item.groupName)
                    .frame(maxWidth: isSmall ? .infinity : 110, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupLabel(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(yellow.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
    }

    private func todoRow(_ item: WidgetTodoItem) -> some View {
        HStack(spacing: isLarge ? 10 : 7) {
            Circle()
                .strokeBorder(ink.opacity(0.75), lineWidth: 1.5)
                .frame(width: isLarge ? 17 : 14, height: isLarge ? 17 : 14)
                .accessibilityHidden(true)
            Text(item.title)
                .font(.system(size: isLarge ? 16 : 13, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isLarge ? 7 : 5)
        .padding(.vertical, isLarge ? 5 : 3)
        .background(ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.groupName, item.taskTitle, item.title]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
