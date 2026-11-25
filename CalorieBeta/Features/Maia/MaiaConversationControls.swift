import SwiftUI
import MyFitPlateCore

struct MaiaConversationBrowser: View {
    @ObservedObject var model: AIChatbotViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var conversations: [MaiaConversation] {
        model.conversationLibrary.conversations.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(search) }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { model.newConversation(); dismiss() } label: { Label("New conversation", systemImage: "plus.bubble") }
                        .accessibilityIdentifier("maia_new_conversation")
                }
                Section("Saved on this device") {
                    if conversations.isEmpty {
                        Text(search.isEmpty ? "Start a conversation to keep your questions and replies together." : "No conversations match your search.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                    ForEach(conversations) { conversation in
                        Button {
                            TTSManager.shared.pauseSpeaking()
                            model.selectConversation(conversation.id); dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conversation.title).appTextRole(.control).foregroundStyle(AppPalette.text)
                                if !conversation.draft.isEmpty {
                                    Text("Draft: \(conversation.draft)").appTextRole(.caption).foregroundStyle(.secondary).lineLimit(1)
                                } else if let message = conversation.messages.last {
                                    Text(message.text).appTextRole(.secondary).foregroundStyle(.secondary).lineLimit(2)
                                }
                                HStack {
                                    Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day())
                                    if conversation.request?.state == .interrupted || conversation.request?.state == .failed {
                                        Text("Question kept")
                                    }
                                }.appTextRole(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppPalette.text)
                        .accessibilityIdentifier("maia_conversation_\(conversation.id.uuidString)")
                    }
                }
            }
            .appFormStyle()
            .searchable(text: $search, prompt: "Find a conversation")
            .navigationTitle("Conversations").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct MaiaContextControls: View {
    @ObservedObject var model: AIChatbotViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var context: MaiaConversationContext
    @State private var profile: MaiaCommunicationProfile
    @State private var onlyThisTopic: Bool
    @State private var loadedPresentedContext = false

    init(model: AIChatbotViewModel) {
        self.model = model
        _context = State(initialValue: model.currentConversationContext)
        _profile = State(initialValue: model.effectiveCommunicationProfile)
        _onlyThisTopic = State(initialValue: model.currentConversation?.communicationOverride != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose what Maia can use in this conversation. Changes apply to your next request.")
                        .appTextRole(.secondary)
                    if let day = model.dailyLogService?.activelyViewedDate {
                        LabeledContent("Diary day", value: day.formatted(date: .abbreviated, time: .omitted))
                    }
                    ForEach(MaiaContextScope.allCases, id: \.rawValue) { scope in
                        Toggle(contextLabel(for: scope), isOn: Binding(
                            get: { context.includedScopes.contains(scope) },
                            set: { enabled in
                                context.includedScopes.removeAll { $0 == scope }
                                if enabled { context.includedScopes.append(scope) }
                            }))
                    }
                    Text("Health sharing still requires your separate consent. Disabled categories are excluded even when a quick action requests them.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                } header: { Text("Shared context") }
                Section("Topic summary & history") {
                    Toggle("Include recent messages", isOn: $context.includeRecentMessages)
                        .accessibilityIdentifier("maia_context_history")
                    TextField("Topic summary, written by you", text: $context.notes, axis: .vertical)
                        .lineLimit(3...6).accessibilityIdentifier("maia_context_notes")
                    DisclosureGroup("How conversation history is used") {
                        Text("Maia receives your summary and up to 6 recent messages. Older messages stay searchable on this device. Other topics stay separate; your summary is never rewritten automatically.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                    if !context.notes.isEmpty {
                        Button("Clear topic summary", role: .destructive) { context.notes = "" }
                    }
                }
                Section("Communication") {
                    Picker("Tone", selection: $profile.tone) {
                        Text("Balanced").tag("Balanced"); Text("Coach").tag("Coach"); Text("Analyst").tag("Analyst")
                    }
                    Picker("Answer length", selection: $profile.length) {
                        ForEach(MaiaCommunicationProfile.Length.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Encouragement", selection: $profile.motivation) {
                        ForEach(MaiaCommunicationProfile.Motivation.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    DisclosureGroup("Compare styles with the same question") {
                        Text(MaiaCommunicationProfile.previewQuestion).appTextRole(.control)
                        ForEach(["Balanced", "Coach", "Analyst"], id: \.self) { tone in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tone).appTextRole(.control)
                                Text(MaiaCommunicationProfile(tone: tone, length: profile.length, motivation: profile.motivation).previewAnswer)
                                    .appTextRole(.secondary)
                            }.padding(.vertical, 4)
                        }
                        Text("Illustrative wording using the same facts, not live advice. Length and encouragement use your selections above.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("maia_style_previews")
                    Toggle("Use only for this topic", isOn: $onlyThisTopic)
                    Text("Changes the presentation of answers. Your targets, logged facts, and reviewed actions stay the same.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            }
            .appFormStyle()
            .disabled(model.isSavingCommunication)
            .onAppear {
                guard !loadedPresentedContext else { return }
                loadedPresentedContext = true
                // Sheet content may be initialized before the account library finishes projecting.
                // Seed the review from the selected topic at presentation, once; later updates must not erase edits.
                context = model.currentConversationContext
                profile = model.effectiveCommunicationProfile
                onlyThisTopic = model.currentConversation?.communicationOverride != nil
            }
            .safeAreaInset(edge: .bottom) {
                if let error = model.storageError { Text(error).appTextRole(.caption).padding().background(.bar) }
            }
            .navigationTitle("Context & style").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        context.notes = String(context.notes.prefix(2_000))
                        Task {
                            if await model.updateContext(context, profile: profile, onlyThisTopic: onlyThisTopic) { dismiss() }
                        }
                    }.disabled(model.isSavingCommunication).accessibilityIdentifier("maia_context_save")
                }
            }
        }
    }

    private func contextLabel(for scope: MaiaContextScope) -> String {
        switch scope {
        case .todayLog: return "Today's food totals"
        case .nutritionGoals: return "Nutrition goals"
        case .nutritionAudit: return "Food log quality checks"
        case .water: return "Water progress"
        case .loggedTraining: return "Logged workouts"
        case .healthKit: return "Apple Health data"
        case .pantry: return "Foods in your pantry"
        case .coachingPreferences: return "Coaching preferences"
        case .aiEstimates: return "Number of AI food estimates"
        }
    }
}

struct MaiaPlaybackControls: View {
    @ObservedObject var speech: TTSManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.compact) {
            HStack {
                Text(speech.playbackState == .preparing ? "Preparing audio" : "Sentence \(speech.sentenceIndex + 1) of \(speech.sentenceCount)")
                    .appTextRole(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { rate in
                        Button("\(rate.formatted())×") { speech.setPlaybackRate(rate) }
                    }
                } label: { Text("\(speech.playbackRate.formatted())×").appTextRole(.control).frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("Playback speed").accessibilityValue("\(speech.playbackRate.formatted()) times")
                Button { speech.stopSpeaking() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close playback")
            }
            Text(speech.currentSentence ?? "").appTextRole(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                .accessibilityIdentifier("maia_playback_sentence")
            HStack(spacing: AppSpacing.row) {
                Button { speech.seekSentence(speech.sentenceIndex - 1) } label: { Label("Back", systemImage: "backward.end").frame(minHeight: 44) }
                    .disabled(speech.sentenceIndex == 0).accessibilityIdentifier("maia_playback_previous")
                Spacer()
                Button {
                    if speech.playbackState == .paused { speech.resumeSpeaking() } else { speech.pauseSpeaking() }
                } label: {
                    Label(speech.playbackState == .paused ? "Resume" : "Pause", systemImage: speech.playbackState == .paused ? "play.fill" : "pause.fill").frame(minHeight: 44)
                }.accessibilityIdentifier("maia_playback_toggle")
                Spacer()
                Button { speech.seekSentence(speech.sentenceIndex + 1) } label: { Label("Next", systemImage: "forward.end").frame(minHeight: 44) }
                    .disabled(speech.sentenceIndex + 1 >= speech.sentenceCount).accessibilityIdentifier("maia_playback_next")
            }
            .appTextRole(.secondary).buttonStyle(.plain).frame(minHeight: 44)
            if let notice = speech.playbackNotice { Text(notice).appTextRole(.caption).foregroundStyle(.secondary) }
        }
        .padding(AppSpacing.row)
        .background(AppPalette.control, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .accessibilityElement(children: .contain).accessibilityIdentifier("maia_playback_controls")
    }
}
