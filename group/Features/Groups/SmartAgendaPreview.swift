#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

/// Launched only with -preview-smart-agenda. The real project screen is unchanged.
struct SmartAgendaPreview: View {
    @State private var model = SmartAgendaPreviewModel()
    @State private var showsMeetingEditor = false
    @State private var showsMaterialEditor = false
    @State private var showsMeeting = false
    @State private var selectedAttachment: String?
    @State private var selection = AppTab.groups

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        projectIdentity
                        countdown
                        Label("Complete all tasks to settle", systemImage: "checkmark.seal.fill")
                            .font(SmartAgendaStyle.heading(13))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(SmartAgendaStyle.ink.opacity(0.3))
                            .background(SmartAgendaStyle.paper.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SmartAgendaStyle.ink.opacity(0.25), lineWidth: 2))
                        Text("Smart agenda").font(sectionFont).id("agenda")
                        agendaCard
                        Text("My progress").font(sectionFont).id("mine")
                        progressRow(model.currentMember)
                        Text("Member progress").font(sectionFont)
                        ForEach(model.members.filter { $0.id != model.currentMemberID }) { person in
                            progressRow(person)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    previewTabBar.frame(maxWidth: .infinity)
                        .padding(.top, 5).background(SmartAgendaStyle.yellow)
                }
                .onChange(of: selection) { _, value in
                    withAnimation(.smooth) { reader.scrollTo(value == .myTasks ? "mine" : "agenda", anchor: .top) }
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .background(SmartAgendaStyle.yellow.ignoresSafeArea())
            .foregroundStyle(SmartAgendaStyle.ink)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsMeetingEditor) { AgendaMeetingEditor(model: model) }
            .sheet(isPresented: $showsMaterialEditor) { AgendaMaterialEditor(model: model) }
            .sheet(isPresented: $showsMeeting) { meetingRunSheet }
            .sheet(isPresented: Binding(get: { selectedAttachment != nil }, set: { if !$0 { selectedAttachment = nil } })) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "paperclip").font(.largeTitle)
                        Text(selectedAttachment ?? "").font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SmartAgendaStyle.paper)
                    .navigationTitle("Attachment")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Done") { selectedAttachment = nil } }
                }
                .presentationDetents([.medium])
            }
            .task(id: model.preparationRevision) { await model.generatePreviewPlan() }
            .task(id: model.replayRevision) { await model.replayPreparation() }
            .animation(.easeInOut(duration: 0.25), value: model.preparedCount)
        }
        .tint(SmartAgendaStyle.ink)
    }

    private var sectionFont: Font { SmartAgendaStyle.heading(20) }

    private var header: some View {
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).frame(width: 36, height: 36)
                .foregroundStyle(SmartAgendaStyle.yellow).background(SmartAgendaStyle.ink, in: Circle())
            Spacer()
            Text("Project tasks").font(SmartAgendaStyle.heading(17))
            Spacer()
            Menu {
                Section("Preview as") {
                    ForEach(model.members) { person in
                        Button(person.name + (person.id == model.leaderID ? " · Leader" : "")) { model.currentMemberID = person.id }
                    }
                }
                Section("Preparation") {
                    Button("Replay 0/4 → 4/4") { model.replayRevision += 1 }
                    Button("Clear my material") { model.saveMyMaterial(.init()) }
                    Button("Show completed example") { model.showCompletedExample() }
                }
            } label: {
                Text("Test").font(SmartAgendaStyle.text(12, bold: true))
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(SmartAgendaStyle.paper, in: Capsule())
                    .overlay(Capsule().stroke(SmartAgendaStyle.ink, lineWidth: 2))
            }
            .disabled(model.isPlaying)
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(SmartAgendaStyle.yellow).background(SmartAgendaStyle.ink, in: Circle())
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(SmartAgendaStyle.yellow)
    }

    private var projectIdentity: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.projectName).font(SmartAgendaStyle.heading(23))
                HStack(spacing: 5) {
                    Text("Group code: \(model.projectCode)")
                    Image(systemName: "doc.on.doc")
                }.font(SmartAgendaStyle.heading(11))
            }
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up").frame(width: 30, height: 30)
                    .foregroundStyle(SmartAgendaStyle.paper).background(SmartAgendaStyle.ink, in: Circle())
                Image(systemName: "pencil").frame(width: 30, height: 30)
                    .foregroundStyle(SmartAgendaStyle.paper).background(SmartAgendaStyle.ink, in: Circle())
            }
        }
    }

    private var countdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "timer").foregroundStyle(SmartAgendaStyle.yellow)
                Text("Project countdown").font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Text(verbatim: "LIVE").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(SmartAgendaStyle.red)
            }
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                countdownUnit(model.countdownDays, unit: "d")
                Text(":").font(SmartAgendaStyle.digits(24))
                countdownUnit(model.countdownHours, unit: "h")
                Text(":").font(SmartAgendaStyle.digits(24))
                countdownUnit(model.countdownMinutes, unit: "m")
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(model.projectProgress)").font(SmartAgendaStyle.digits(23))
                    Text("%").font(SmartAgendaStyle.text(12))
                }
            }
            ProgressView(value: Double(model.projectProgress), total: 100).tint(SmartAgendaStyle.yellow)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(SmartAgendaStyle.ink, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { index in
                    Rectangle().fill(index.isMultiple(of: 2) ? SmartAgendaStyle.ink : SmartAgendaStyle.yellow)
                }
            }.frame(height: 10).padding(.horizontal, 20).offset(y: -5)
        }
        .padding(.top, 5)
    }

    private func countdownUnit(_ value: String, unit: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(value).font(SmartAgendaStyle.digits(29))
            Text(unit).font(SmartAgendaStyle.text(11, bold: true))
        }
    }

    private var agendaCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meeting topic").font(SmartAgendaStyle.text(10.5, bold: true)).foregroundStyle(SmartAgendaStyle.secondary)
                    Text(model.topic).font(SmartAgendaStyle.text(16, bold: true)).fixedSize(horizontal: false, vertical: true)
                    Text(model.meetingSummary).font(SmartAgendaStyle.text(11.5))
                }
                Spacer(minLength: 8)
                if model.isLeader {
                    Button("Edit") { showsMeetingEditor = true }
                        .font(SmartAgendaStyle.text(12))
                        .frame(minWidth: 32, minHeight: 28, alignment: .topTrailing)
                        .disabled(model.isPlaying)
                }
            }
            .padding(.bottom, 6)
            rule
            HStack {
                Text("Team prep").font(SmartAgendaStyle.text(12.5, bold: true))
                Spacer()
                Text("\(model.preparedCount)/\(model.members.count) prepared")
                    .font(SmartAgendaStyle.text(11.5, bold: true)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 4)
            rule
            ForEach(model.preparedMembers) { person in
                materialRow(person)
                if person.id != model.preparedMembers.last?.id { rule }
            }
            if model.preparedCount == 0 {
                Text("Add what you’d like to discuss.").font(.system(size: 12)).foregroundStyle(SmartAgendaStyle.secondary)
                    .padding(.vertical, 18)
            }
            Button { showsMaterialEditor = true } label: {
                Label("Add my material", systemImage: "plus").font(SmartAgendaStyle.text(11, bold: true))
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .overlay(Capsule().stroke(SmartAgendaStyle.ink, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(model.isPlaying)
            .padding(.top, 7).padding(.bottom, 12)
            if model.allPrepared {
                rule
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI suggested plan").font(SmartAgendaStyle.text(12, bold: true))
                        .padding(.top, 5).padding(.bottom, 4)
                    if model.isGenerating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Generating meeting plan…").font(.system(size: 12))
                        }
                        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                    } else {
                        ForEach(model.stages) { stage in
                            HStack(alignment: .center, spacing: 10) {
                                Text(stage.time).font(SmartAgendaStyle.text(10.5, bold: true)).foregroundStyle(SmartAgendaStyle.secondary)
                                    .frame(width: 70, alignment: .leading)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(stage.title).font(SmartAgendaStyle.text(11, bold: true))
                                    Text(stage.goal).font(SmartAgendaStyle.text(9.5)).foregroundStyle(SmartAgendaStyle.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            if stage.id != model.stages.last?.id { rule }
                        }
                        Button {
                            model.meetingStartedAt = Date()
                            showsMeeting = true
                        } label: {
                            Text("Start meeting").font(SmartAgendaStyle.text(11.5, bold: true))
                                .frame(maxWidth: .infinity, minHeight: 29)
                                .foregroundStyle(.white)
                                .background(SmartAgendaStyle.ink, in: Capsule())
                        }
                        .buttonStyle(.plain).padding(.top, 3)
                        .disabled(model.stages.isEmpty)
                    }
                }
            }
        }
        .padding(13)
        .background(SmartAgendaStyle.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SmartAgendaStyle.ink, lineWidth: 1.8))
    }

    private var rule: some View { Rectangle().fill(SmartAgendaStyle.rule).frame(height: 0.7) }

    private func avatar(_ person: SmartAgendaPreviewModel.Person) -> some View {
        Text(String(person.name.prefix(1))).font(SmartAgendaStyle.text(16, bold: true))
            .foregroundStyle(SmartAgendaStyle.yellow).frame(width: 30, height: 30)
            .background(SmartAgendaStyle.ink, in: Circle())
            .accessibilityHidden(true)
    }

    private func materialRow(_ person: SmartAgendaPreviewModel.Person) -> some View {
        let material = model.materials[person.id] ?? .init()
        return HStack(alignment: .center, spacing: 12) {
            avatar(person)
            Text(person.name).font(SmartAgendaStyle.text(10.5, bold: true)).frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if !material.note.isEmpty {
                    Text(material.note).font(SmartAgendaStyle.text(9.5)).foregroundStyle(SmartAgendaStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let name = material.fileName {
                    Button { selectedAttachment = name } label: {
                        Label(name, systemImage: "paperclip").font(SmartAgendaStyle.text(9.5)).foregroundStyle(SmartAgendaStyle.secondary)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .frame(minHeight: 39)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func progressRow(_ person: SmartAgendaPreviewModel.Person) -> some View {
        HStack(spacing: 10) {
            avatar(person)
            Text(person.name).font(.headline)
            Spacer()
            Text("\(model.projectProgress)%").font(.headline)
        }
        .padding(14)
        .background(SmartAgendaStyle.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SmartAgendaStyle.ink, lineWidth: 2))
    }

    private var previewTabBar: some View {
        HStack(spacing: 3) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol).font(.system(size: 16, weight: .black))
                        Text(tab == .groups ? "Groups" : tab == .myTasks ? "My tasks" : "Settings")
                            .font(SmartAgendaStyle.text(10, bold: true))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(selection == tab ? SmartAgendaStyle.ink : SmartAgendaStyle.paper)
                    .background(selection == tab ? SmartAgendaStyle.yellow : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(4).background(SmartAgendaStyle.ink, in: Capsule())
        .frame(width: 296).padding(.bottom, 12)
    }

    private var meetingRunSheet: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = max(0, Int(context.date.timeIntervalSince(model.meetingStartedAt ?? context.date)))
                let remaining = max(0, model.duration * 60 - elapsed)
                let current = model.stages.first { elapsed < $0.end * 60 }
                VStack(alignment: .leading, spacing: 20) {
                    Text(model.topic).font(.title2.bold())
                    Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                        .font(.system(size: 52, weight: .black, design: .monospaced))
                    if let current {
                        Text(current.time).font(.subheadline).foregroundStyle(SmartAgendaStyle.secondary)
                        Text(current.title).font(.title3.bold())
                        Text(current.goal).font(.body)
                    } else { Text("Meeting complete").font(.title3.bold()) }
                    Spacer()
                    Button("End meeting") { showsMeeting = false }
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(SmartAgendaStyle.paper).background(SmartAgendaStyle.ink, in: Capsule())
                }
                .padding(24).background(SmartAgendaStyle.paper)
            }
            .navigationTitle("Meeting").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { showsMeeting = false } }
        }
    }
}

private struct AgendaMeetingEditor: View {
    let model: SmartAgendaPreviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var topic: String
    @State private var date: Date
    @State private var duration: Int

    init(model: SmartAgendaPreviewModel) {
        self.model = model
        _topic = State(initialValue: model.topic)
        _date = State(initialValue: model.meetingDate)
        _duration = State(initialValue: model.duration)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meeting topic") { TextField("Meeting topic", text: $topic) }
                Section("Date & time") { DatePicker("Meeting", selection: $date).labelsHidden() }
                Section("Duration") {
                    Picker("Meeting length", selection: $duration) {
                        ForEach([10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(SmartAgendaStyle.paper)
            .navigationTitle("Edit meeting").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveMeeting(topic: topic, date: date, duration: duration)
                        dismiss()
                    }.disabled(!model.isLeader || topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AgendaMaterialEditor: View {
    let model: SmartAgendaPreviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var material: SmartAgendaPreviewModel.Material
    @State private var showsImporter = false
    @State private var importError: String?

    init(model: SmartAgendaPreviewModel) {
        self.model = model
        _material = State(initialValue: model.myMaterial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("What would you like to discuss?", text: $material.note, axis: .vertical)
                        .lineLimit(3...5)
                }
                Section("Attachment") {
                    if let fileName = material.fileName {
                        HStack {
                            Label(fileName, systemImage: "paperclip").lineLimit(2)
                            Spacer()
                            Button {
                                material.fileName = nil
                                material.fileURL = nil
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).accessibilityLabel("Remove attachment")
                        }
                    }
                    Button(material.fileName == nil ? "Choose file" : "Replace file", systemImage: "plus") { showsImporter = true }
                    if let importError { Text(importError).foregroundStyle(SmartAgendaStyle.red) }
                }
            }
            .scrollContentBackground(.hidden).background(SmartAgendaStyle.paper)
            .navigationTitle("My material").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.saveMyMaterial(material); dismiss() }
                        .disabled(!material.isPrepared)
                }
            }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.item]) { result in
                do {
                    let url = try result.get()
                    material.fileName = url.lastPathComponent
                    material.fileURL = url
                    importError = nil
                } catch { importError = "Could not select this file. Try again." }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
