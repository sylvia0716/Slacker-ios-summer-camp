import SwiftUI
import WidgetKit

struct MyTasksTodoEntry: TimelineEntry {
    let date: Date
    let load: WidgetTodoLoad

    var snapshot: WidgetTodoSnapshot { load.snapshot ?? .empty }
}

struct MyTasksTodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> MyTasksTodoEntry {
        MyTasksTodoEntry(date: .now, load: .loaded(.sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (MyTasksTodoEntry) -> Void) {
        // The widget gallery has no access to the user's data, so show the sample there.
        completion(context.isPreview ? placeholder(in: context) : currentEntry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MyTasksTodoEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private var currentEntry: MyTasksTodoEntry {
        MyTasksTodoEntry(date: .now, load: WidgetSnapshotStore.loadTodo())
    }
}

struct MyTasksTodoWidget: Widget {
    let kind = WidgetSharedConfig.todoWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MyTasksTodoProvider()) { entry in
            MyTasksTodoWidgetView(entry: entry)
        }
        .configurationDisplayName(Text(WidgetLanguage.text("我的待辦", "My To-Dos")))
        .description(Text(WidgetLanguage.text("查看我的任務中尚未完成的子任務。", "See unfinished items from My Tasks.")))
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}

private struct MyTasksTodoWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: MyTasksTodoEntry

    var body: some View {
        switch family {
        case .accessoryCircular: AccessoryCircularTodoView(entry: entry)
        case .accessoryRectangular: AccessoryRectangularTodoView(entry: entry)
        case .accessoryInline: AccessoryInlineTodoView(entry: entry)
        default: HomeScreenTodoView(entry: entry)
        }
    }
}

// MARK: - Home Screen

/// The paper-card presentation used by the small, medium and large families.
private struct HomeScreenTodoView: View {
    @Environment(\.widgetFamily) private var family

    let entry: MyTasksTodoEntry

    private var isSmall: Bool { family == .systemSmall }
    private var isLarge: Bool { family == .systemLarge }

    private var contentInset: CGFloat { isLarge ? 16 : 10 }
    private var outerMargin: CGFloat { isLarge ? 12 : 6 }
    /// Room for the offset drop shadow behind the card.
    private var shadowOffset: CGFloat { isLarge ? 4 : 2 }

    var body: some View {
        content
            .foregroundStyle(BombWidgetTheme.ink)
            .padding(contentInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(BombWidgetTheme.ink)
                        .offset(x: shadowOffset, y: shadowOffset)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(BombWidgetTheme.paper)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(BombWidgetTheme.ink, lineWidth: isLarge ? 3 : 2)
            )
            .padding(EdgeInsets(
                top: outerMargin,
                leading: outerMargin,
                bottom: outerMargin + shadowOffset,
                trailing: outerMargin + shadowOffset
            ))
            .widgetURL(URL(string: "oopsbomb://my-tasks"))
            .containerBackground(for: .widget) { BombWidgetTheme.yellow }
    }

    @ViewBuilder private var content: some View {
        switch entry.load {
        case .unreadable:
            statusText(WidgetLanguage.text("資料需要更新，請開啟 App", "Open the app to refresh"))
        case .missing:
            // The app has never published a snapshot, so this is not an empty to-do list.
            statusText(WidgetLanguage.text("開啟 App 載入你的任務", "Open the app to load your tasks"))
        case .loaded:
            if entry.snapshot.count == 0 {
                statusText(WidgetLanguage.text("目前沒有待辦事項", "No to-dos"))
            } else if isLarge {
                largeContent
            } else {
                compactContent
            }
        }
    }

    private func statusText(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BombWidgetTheme.ink.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Large

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(BombWidgetTheme.ink)
                .frame(height: 2)
                .padding(.top, 8)
                .padding(.bottom, 18)

            ViewThatFits(in: .vertical) {
                // Keep complete rows and their context when the system offers less height.
                groupedList(limit: 4)
                groupedList(limit: 3)
                groupedList(limit: 2)
                groupedList(limit: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("\(entry.snapshot.count)")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(WidgetLanguage.text("我的待辦", "My To-Dos"))
                .font(.system(size: 16, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            BombWidgetTheme.badge(size: 36, glyph: 17)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetLanguage.text(
            "我的待辦，\(entry.snapshot.count) 項", "My To-Dos, \(entry.snapshot.count) items"
        ))
    }

    /// Groups consecutive items under their task heading so a subtask is never shown
    /// without the task and project it belongs to.
    private func groupedList(limit: Int) -> some View {
        let items = Array(entry.snapshot.items.prefix(limit))
        let sections = items.reduce(into: [TodoSection]()) { sections, item in
            if sections.last?.id == item.taskID {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(TodoSection(id: item.taskID, items: [item]))
            }
        }

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(sections) { section in
                if let firstItem = section.items.first {
                    VStack(alignment: .leading, spacing: 10) {
                        taskHeading(firstItem)
                        VStack(spacing: 4) {
                            ForEach(section.items) { item in
                                todoRow(item, circle: 17, font: 16, showsBackground: true)
                            }
                        }
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { BombWidgetTheme.rule }
                    }
                }
            }
            remainingLabel(total: entry.snapshot.count, shown: items.count, font: 11)
                .padding(.top, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private struct TodoSection: Identifiable {
        let id: UUID
        var items: [WidgetTodoItem]
    }

    // MARK: Small & medium

    @ViewBuilder private var compactContent: some View {
        if isSmall {
            checklist(items: entry.snapshot.items, total: entry.snapshot.count)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let first = entry.snapshot.items.first {
            // Only show this task's subtasks under its heading, so the count beside the
            // list describes the same task the heading names.
            let taskItems = entry.snapshot.items.filter { $0.taskID == first.taskID }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        Text("\(entry.snapshot.count)")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .monospacedDigit()
                        Text(WidgetLanguage.text("我的待辦", "My To-Dos"))
                            .font(.system(size: 14, weight: .black))
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        BombWidgetTheme.badge(size: 25, glyph: 13)
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WidgetLanguage.text(
                        "我的待辦，\(entry.snapshot.count) 項", "My To-Dos, \(entry.snapshot.count) items"
                    ))
                    Rectangle().fill(BombWidgetTheme.ink).frame(height: 1)
                    Text(first.taskTitle)
                        .font(.system(size: 15, weight: .black))
                        .lineLimit(2)
                    if !first.groupName.isEmpty {
                        BombWidgetTheme.groupLabel(first.groupName)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                checklist(items: taskItems, total: taskItems.count)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func checklist(items: [WidgetTodoItem], total: Int) -> some View {
        // Listed one by one rather than through a ForEach: ViewThatFits picks between its
        // direct subviews, so each candidate height has to be its own view.
        ViewThatFits(in: .vertical) {
            checklistRows(items: items, total: total, limit: 4)
            checklistRows(items: items, total: total, limit: 3)
            checklistRows(items: items, total: total, limit: 2)
            checklistRows(items: items, total: total, limit: 1)
        }
    }

    private func checklistRows(items: [WidgetTodoItem], total: Int, limit: Int) -> some View {
        let visibleItems = Array(items.prefix(limit))

        return VStack(alignment: .leading, spacing: isSmall ? 12 : 10) {
            VStack(spacing: isSmall ? 8 : 4) {
                ForEach(visibleItems) { item in
                    todoRow(
                        item,
                        circle: isSmall ? 16 : 14,
                        font: isSmall ? 14 : 13,
                        showsBackground: !isSmall
                    )
                }
            }
            .padding(.leading, isSmall ? 0 : 8)
            .overlay(alignment: .leading) {
                if !isSmall { BombWidgetTheme.rule }
            }
            remainingLabel(total: total, shown: visibleItems.count, font: 10)
        }
        .padding(.horizontal, isSmall ? 5 : 0)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Shared pieces

    @ViewBuilder
    private func remainingLabel(total: Int, shown: Int, font: CGFloat) -> some View {
        let remaining = max(0, total - shown)
        if remaining > 0 {
            Text(WidgetLanguage.text("還有 \(remaining) 項", "+\(remaining) more"))
                .font(.system(size: font, weight: .semibold))
                .foregroundStyle(BombWidgetTheme.ink.opacity(0.6))
                .lineLimit(1)
        }
    }

    private func taskHeading(_ item: WidgetTodoItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(item.taskTitle)
                .font(.system(size: 17, weight: .black))
                .lineLimit(1)
            if !item.groupName.isEmpty {
                BombWidgetTheme.groupLabel(item.groupName)
                    .frame(maxWidth: 110, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A tappable row: the checkbox completes the subtask without leaving the Home Screen.
    private func todoRow(
        _ item: WidgetTodoItem,
        circle: CGFloat,
        font: CGFloat,
        showsBackground: Bool
    ) -> some View {
        Button(intent: ToggleTodoIntent(subtaskID: item.id, taskID: item.taskID)) {
            HStack(spacing: circle > 15 ? 10 : 7) {
                Circle()
                    .strokeBorder(BombWidgetTheme.ink.opacity(0.75), lineWidth: circle > 15 ? 1.5 : 1.2)
                    .frame(width: circle, height: circle)
                Text(item.title)
                    .font(.system(size: font, weight: .bold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, showsBackground ? 6 : 0)
            .padding(.vertical, showsBackground ? 3 : 0)
            .background(
                showsBackground ? BombWidgetTheme.ink.opacity(0.045) : .clear,
                in: RoundedRectangle(cornerRadius: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel([item.groupName, item.taskTitle, item.title]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(WidgetLanguage.text("完成這項待辦", "Completes this to-do"))
    }
}

// MARK: - Lock Screen & StandBy

private struct AccessoryCircularTodoView: View {
    let entry: MyTasksTodoEntry

    var body: some View {
        VStack(spacing: -2) {
            Image(systemName: "checklist")
                .font(.system(size: 11, weight: .bold))
            Text("\(entry.snapshot.count)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .widgetURL(URL(string: "oopsbomb://my-tasks"))
        .accessibilityLabel(WidgetLanguage.text(
            "待辦 \(entry.snapshot.count) 項", "\(entry.snapshot.count) to-dos"
        ))
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

private struct AccessoryRectangularTodoView: View {
    let entry: MyTasksTodoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(WidgetLanguage.text("我的待辦 \(entry.snapshot.count)", "My To-Dos \(entry.snapshot.count)"))
                .font(.caption.weight(.bold))
                .widgetAccentable()
            if let first = entry.snapshot.items.first {
                Text(first.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                Text(first.taskTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(entry.load.snapshot != nil
                     ? WidgetLanguage.text("目前沒有待辦事項", "No to-dos")
                     : WidgetLanguage.text("開啟 App 載入任務", "Open the app to load"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "oopsbomb://my-tasks"))
        .containerBackground(for: .widget) { Color.clear }
    }
}

private struct AccessoryInlineTodoView: View {
    let entry: MyTasksTodoEntry

    var body: some View {
        let count = entry.snapshot.count
        let text = count == 0
            ? WidgetLanguage.text("沒有待辦事項", "No to-dos")
            : WidgetLanguage.text("待辦 \(count) 項", "\(count) to-dos")
        return Label(text, systemImage: "checklist")
            .widgetURL(URL(string: "oopsbomb://my-tasks"))
            .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Theme

private enum BombWidgetTheme {
    static let yellow = Color(red: 1, green: 0.79, blue: 0.05)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.07)
    static let paper = Color(red: 0.96, green: 0.92, blue: 0.79)

    /// The vertical accent that ties a group of subtasks to its task heading.
    static var rule: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(yellow)
            .frame(width: 2)
    }

    static func badge(size: CGFloat, glyph: CGFloat) -> some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: glyph, weight: .black))
            .foregroundStyle(yellow)
            .frame(width: size, height: size)
            .background(ink, in: Circle())
            .accessibilityHidden(true)
    }

    static func groupLabel(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(yellow.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Previews

extension WidgetTodoSnapshot {
    /// Sample content for the widget gallery and Xcode previews.
    static let sample: WidgetTodoSnapshot = {
        let reportTask = UUID()
        let slidesTask = UUID()
        return WidgetTodoSnapshot(
            count: 7,
            items: [
                WidgetTodoItem(id: UUID(), title: "整理訪談逐字稿", taskID: reportTask,
                               groupName: "期末報告拆彈小隊", taskTitle: "撰寫研究方法"),
                WidgetTodoItem(id: UUID(), title: "補上參考文獻", taskID: reportTask,
                               groupName: "期末報告拆彈小隊", taskTitle: "撰寫研究方法"),
                WidgetTodoItem(id: UUID(), title: "設計封面", taskID: slidesTask,
                               groupName: "行銷專題", taskTitle: "製作簡報"),
                WidgetTodoItem(id: UUID(), title: "排版第三章", taskID: slidesTask,
                               groupName: "行銷專題", taskTitle: "製作簡報"),
            ]
        )
    }()
}

#Preview("Small", as: .systemSmall) {
    MyTasksTodoWidget()
} timeline: {
    MyTasksTodoEntry(date: .now, load: .loaded(.sample))
    MyTasksTodoEntry(date: .now, load: .missing)
}

#Preview("Medium", as: .systemMedium) {
    MyTasksTodoWidget()
} timeline: {
    MyTasksTodoEntry(date: .now, load: .loaded(.sample))
    MyTasksTodoEntry(date: .now, load: .unreadable)
}

#Preview("Large", as: .systemLarge) {
    MyTasksTodoWidget()
} timeline: {
    MyTasksTodoEntry(date: .now, load: .loaded(.sample))
    MyTasksTodoEntry(date: .now, load: .missing)
}

#Preview("Circular", as: .accessoryCircular) {
    MyTasksTodoWidget()
} timeline: {
    MyTasksTodoEntry(date: .now, load: .loaded(.sample))
}

#Preview("Rectangular", as: .accessoryRectangular) {
    MyTasksTodoWidget()
} timeline: {
    MyTasksTodoEntry(date: .now, load: .loaded(.sample))
    MyTasksTodoEntry(date: .now, load: .missing)
}
