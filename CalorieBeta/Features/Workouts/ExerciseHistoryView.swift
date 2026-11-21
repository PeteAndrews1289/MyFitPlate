import MyFitPlateCore
import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ExerciseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: RoutineExercise
    let routineID: String?
    @State private var scope = 0
    @State private var section = 0
    @State private var media: WorkoutInstructionMedia?
    @State private var mediaURL: URL?
    @State private var builtinMedia: WorkoutBuiltinInstructionMedia?
    @State private var builtinURL: URL?
    @State private var importing = false
    @State private var attribution = ""
    @State private var caption = ""
    @State private var permission = WorkoutInstructionMedia.Permission.ownerRecording
    @State private var permissionNotes = ""
    @State private var confirmsPermission = false
    @State private var mediaError: String?
    private let ownerID = DIContainer.shared.authService.currentUserID
    @StateObject private var viewModel: ExerciseHistoryViewModel

    init(exercise: RoutineExercise, routineID: String? = nil) {
        self.routineID = routineID
        self.exercise = exercise
        _viewModel = StateObject(wrappedValue: ExerciseHistoryViewModel(exercise: exercise))
    }

    init(exerciseName: String) { self.init(exercise: RoutineExercise(name: exerciseName)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Exercise information", selection: $section) {
                        Text("History").tag(0)
                        Text("Technique").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("exercise_information_section")
                }
                if section == 1 {
                let guide = WorkoutTechniqueCatalog.guide(for: exercise)
                if let howTo = WorkoutTechniqueCatalog.briefCue(for: exercise) {
                    Section(guide == nil ? "How to perform" : "Quick cue") {
                        Text(howTo).appTextRole(.body).fontWeight(.semibold)
                            .accessibilityIdentifier("exercise_technique_cue")
                        if let guide {
                            if guide.canonicalName != exercise.name {
                                Text(guide.canonicalName).appTextRole(.caption).foregroundStyle(.secondary)
                            }
                            Text(guide.variation).appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Your technique") {
                        Text("Technique guidance isn't available for this exact variation. You can keep your own demonstration below.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let guide {
                    Section("Set up") {
                        TechniqueSteps(steps: guide.setup, identifier: "exercise_technique_setup")
                    }
                    Section("Perform the rep") {
                        TechniqueSteps(steps: guide.execution, identifier: "exercise_technique_execution")
                    }
                    Section {
                        DisclosureGroup {
                            ForEach(guide.corrections, id: \.self) { Text($0).foregroundStyle(.secondary) }
                        } label: {
                            Text("Common corrections").accessibilityIdentifier("exercise_technique_corrections")
                        }
                        DisclosureGroup {
                            Text("These cues are available offline. The reference opens online.")
                                .appTextRole(.caption).foregroundStyle(.secondary)
                            Link(guide.reference.title, destination: guide.reference.url).frame(minHeight: 44)
                        } label: {
                            Text("Technique reference").accessibilityIdentifier("exercise_technique_reference")
                        }
                    }
                }
                if let media, let mediaURL {
                    Section("Offline demonstration") {
                        VideoPlayer(player: AVPlayer(url: mediaURL)).frame(height: 240)
                            .accessibilityLabel("Account-owned demonstration for \(exercise.name). Caption transcript follows.")
                        Text(media.captionTranscript).textSelection(.enabled)
                        Text("\(media.attribution) · \(media.permission.title) · imported \(media.importedAt.formatted(date: .abbreviated, time: .omitted))")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }
                }
                if mediaURL == nil, let builtinMedia, let builtinURL {
                    Section("Catalog demonstration · offline") {
                        CaptionedInstructionPlayer(url: builtinURL, assetID: builtinMedia.id)
                            .accessibilityLabel("\(exercise.name) demonstration. Caption transcript follows.")
                        Text(builtinMedia.captionTranscript).textSelection(.enabled)
                        Text("\(builtinMedia.author) · \(builtinMedia.licenseName) · asset v\(builtinMedia.version)")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        Link("Original source & creator", destination: builtinMedia.sourceURL).frame(minHeight: 44)
                        Link("License terms", destination: builtinMedia.licenseURL).frame(minHeight: 44)
                        Text("An instructional reference for this exact catalog variant. Use a suitable range and review your setup; it is not a record of your performance.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("exercise_catalog_demonstration")
                }
                Section {
                    DisclosureGroup(media == nil ? "Add your demonstration" : "Replace demonstration") {
                    Text("Import your own or licensed video (up to 30 MB). Stored videos play offline; any available text cues stay readable without a video.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                    TextField("Creator / attribution", text: $attribution)
                    Picker("Permission", selection: $permission) { ForEach(WorkoutInstructionMedia.Permission.allCases) { Text($0.title).tag($0) } }
                    TextField("License or permission note", text: $permissionNotes, axis: .vertical)
                    TextField("Caption / transcript shown below video", text: $caption, axis: .vertical).lineLimit(3...8)
                    Toggle("I have permission to store and view this recording", isOn: $confirmsPermission)
                    Button("Choose offline video") { importing = true }.frame(minHeight: 44)
                        .disabled(!confirmsPermission || attribution.trimmed.isEmpty || caption.trimmed.isEmpty)
                    }
                    if let mediaError { Text(mediaError).foregroundStyle(AppPalette.caution) }
                }
                } else {
                Section("Comparison setup") {
                    Text(WorkoutSetMath.contextLabel(exercise)).foregroundStyle(.secondary)
                    Picker("History scope", selection: $scope) {
                        Text("All compatible & reference").tag(0)
                        Text("Compatible setups only").tag(1)
                        if routineID != nil { Text("Same plan day").tag(2) }
                    }.accessibilityIdentifier("exercise_history_scope")
                }
                if viewModel.isLoading { ProgressView("Loading history") }
                if let error = viewModel.loadError {
                    Section { Text(error); Button("Retry", action: viewModel.fetchHistory) }
                }
                if !viewModel.isLoading && viewModel.history.isEmpty && viewModel.loadError == nil {
                    Text("No saved sets for this movement yet.").foregroundStyle(.secondary)
                }
                ForEach(viewModel.history.filter { scope == 0 || (scope == 1 ? $0.compatible : $0.routineID == routineID && $0.compatible) }) { session in
                    Section {
                        Text(WorkoutSetMath.contextLabel(session.exercise)).font(.caption).foregroundStyle(.secondary)
                        if !session.compatible { Text("Different or unknown setup · shown for reference").font(.caption).foregroundStyle(.secondary) }
                        ForEach(Array(session.sets.enumerated()), id: \.element.id) { index, set in
                            let unit = session.exercise.loadEquipment?.unit ?? .lb
                            HStack {
                                Text("Set \(index + 1) · \(set.resolvedSetType.rawValue)")
                                Spacer()
                                switch session.exercise.type {
                                case .strength:
                                    Text("\(unit.displayWeight(set.weight).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue) × \(set.reps) reps")
                                case .cardio:
                                    Text("\((set.distance ?? 0).formatted(.number.precision(.fractionLength(0...2)))) mi · \(set.durationInSeconds ?? 0) sec")
                                case .flexibility:
                                    Text("\(set.durationInSeconds ?? 0) sec")
                                }
                            }
                        }
                    } header: { Text("\(session.date.formatted(date: .abbreviated, time: .omitted)) · \(session.compatible ? "Compatible" : "Reference")") }
                }
                }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle(exercise.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("exercise_information_done")
                }
            }
            .onAppear(perform: loadMedia)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.movie]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let ownerID else { throw WorkoutBlockError.accountChanged }
                    let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                          let size = attributes.fileSize, (1...30_000_000).contains(size) else { throw WorkoutBlockError.invalid }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    media = try WorkoutInstructionMediaStore().importVideo(data, extension: url.pathExtension, exercise: exercise,
                        userID: ownerID, attribution: attribution, permission: permission, permissionNotes: permissionNotes, captionTranscript: caption)
                    loadMedia()
                } catch { mediaError = "The video could not be imported. Your existing guidance is kept. \(error.localizedDescription)" }
            }
        }
    }
    private func loadMedia() {
        if let manifest = Bundle.main.url(forResource: "WorkoutInstructionManifest", withExtension: "json"),
           let data = try? Data(contentsOf: manifest), let catalog = try? WorkoutBuiltinInstructionCatalog.decode(data),
           let item = catalog.media(for: exercise),
           let url = Bundle.main.url(forResource: item.resourceName, withExtension: item.fileExtension) {
            builtinMedia = item; builtinURL = url
        } else { builtinMedia = nil; builtinURL = nil }
        do {
            guard let ownerID else { return }
            media = try WorkoutInstructionMediaStore().media(for: exercise, userID: ownerID)
            if let media { mediaURL = try WorkoutInstructionMediaStore().fileURL(media, userID: ownerID) }
            mediaError = nil
        } catch { mediaError = "The stored video is unavailable. Text guidance and saved history remain usable."; mediaURL = nil }
    }
}

private struct TechniqueSteps: View {
    let steps: [String]
    let identifier: String

    var body: some View {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1)").appTextRole(.secondary).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 16)
                Text(step).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(identifier)_\(index + 1)")
        }
    }
}

@MainActor
final class ExerciseHistoryViewModel: ObservableObject {
    struct ExerciseHistorySession: Identifiable {
        let id: String
        let date: Date
        let routineID: String
        let sets: [CompletedSet]
        let exercise: RoutineExercise
        let compatible: Bool
    }
    @Published var history: [ExerciseHistorySession] = []
    @Published var isLoading = false
    @Published var loadError: String?
    private let exercise: RoutineExercise
    private var generation = UUID()
    private var loadedOwner: String?
    private let currentUserID: @MainActor () -> String?
    private let fetchCompleteHistory: @MainActor (String) async throws -> [WorkoutSessionLog]

    init(exercise: RoutineExercise, automaticallyLoads: Bool = true,
         currentUserID: @escaping @MainActor () -> String? = { DIContainer.shared.authService.currentUserID },
         fetchCompleteHistory: @escaping @MainActor (String) async throws -> [WorkoutSessionLog] = {
             try await DIContainer.shared.workoutRepository.fetchCompleteWorkoutHistory(userID: $0)
         }) {
        self.exercise = exercise; self.currentUserID = currentUserID
        self.fetchCompleteHistory = fetchCompleteHistory
        if automaticallyLoads { fetchHistory() }
    }

    func fetchHistory() { Task { await load() } }

    func load() async {
        guard let owner = currentUserID() else {
            generation = UUID(); loadedOwner = nil; history = []; isLoading = false; loadError = nil; return
        }
        if loadedOwner != owner { history = []; loadedOwner = owner }
        isLoading = true; loadError = nil
        let request = UUID(); generation = request
        defer { if generation == request { isLoading = false } }
        do {
            // Legacy names use the same confirmed, complete history contract as catalog identities.
            let logs = try await fetchCompleteHistory(owner)
            guard generation == request else { return }
            guard currentUserID() == owner else { history = []; loadedOwner = nil; return }
            history = WorkoutSetMath.uniqueSessions(logs).flatMap { log in
                log.completedExercises.enumerated().compactMap { index, completed -> ExerciseHistorySession? in
                    guard WorkoutMovementCatalog.matches(exercise, completed.exercise) || WorkoutSetMath.normalizedName(completed.exerciseName) == WorkoutSetMath.normalizedName(exercise.name) else { return nil }
                    return ExerciseHistorySession(id: "\(log.id ?? String(log.date.timeIntervalSince1970)))-\(index)", date: log.date, routineID: log.routineID,
                        sets: completed.sets, exercise: completed.exercise,
                        compatible: WorkoutMovementCatalog.matches(exercise, completed.exercise) && StrengthEquipment.historyCompatible(current: exercise.loadEquipment, previous: completed.exercise.loadEquipment))
                }
            }
        } catch {
            guard generation == request else { return }
            guard currentUserID() == owner else { history = []; loadedOwner = nil; return }
            loadError = "Complete history could not refresh. Previously confirmed sets are kept; cached or partial data is not treated as complete."
        }
    }

}

/// Playback descriptions are separate, versioned local content; original videos remain unmodified.
private struct InstructionCaption: Decodable {
    let start: Double
    let end: Double
    let text: String
}
private struct InstructionCaptionCatalog: Decodable {
    let version: Int
    let clips: [String: [InstructionCaption]]
}
private struct CaptionedInstructionPlayer: View {
    @State private var player: AVPlayer
    @State private var showsCaptions = true
    private let cues: [InstructionCaption]
    init(url: URL, assetID: String) {
        _player = State(initialValue: AVPlayer(url: url))
        if let url = Bundle.main.url(forResource: "WorkoutInstructionCaptions", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let catalog = try? JSONDecoder().decode(InstructionCaptionCatalog.self, from: data), catalog.version == 1 {
            cues = (catalog.clips[assetID] ?? []).filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && !$0.text.isEmpty }
        } else { cues = [] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoPlayer(player: player).frame(height: 240).accessibilityIdentifier("exercise_demo_player")
            if !cues.isEmpty {
                Toggle("Movement captions", isOn: $showsCaptions).appTextRole(.caption)
                    .accessibilityIdentifier("exercise_demo_captions_toggle")
                if showsCaptions {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        let seconds = player.currentTime().seconds
                        Text(cues.first { seconds >= $0.start && seconds < $0.end }?.text ?? "Play the clip to follow the movement. Full description below.")
                            .appTextRole(.secondary).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .accessibilityIdentifier("exercise_demo_current_caption")
                    }
                }
                Text("Descriptions follow the visible movement. Full description and source credit remain below.")
                    .appTextRole(.caption).foregroundStyle(.secondary)
            }
        }.onDisappear { player.pause() }
    }
}
