import MyFitPlateCore
import SwiftUI

struct RecipeVersionHistoryView: View {
    let recipeID: String
    let onChanged: (Recipe?) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var service: RecipeService
    @State private var versions: [RecipeVersionRecord] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var review: RecipeVersionRestoreSession?
    @State private var expandedVersionIDs: Set<String> = []
    private let owner = DIContainer.shared.authService.currentUserID
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Recipe edits from this update onward keep a version you can restore.")
                    Text("Restoring updates this recipe. Existing logs and planned meals keep their original amounts and nutrition.")
                    if let exportJSON {
                        ShareLink(item: exportJSON, subject: Text("Recipe version snapshots")) { Label("Share loaded version snapshots", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("recipe_history_share")
                    }
                    Button("Resume version restore") { resume() }.frame(minHeight: 44).accessibilityIdentifier("recipe_history_resume")
                }
                if isLoading { ProgressView("Loading saved versions") }
                if let errorMessage { Text(errorMessage).foregroundStyle(AppPalette.caution).accessibilityIdentifier("recipe_history_error") }
                if !isLoading, versions.isEmpty { Text("No saved versions yet. Your next recipe edit will keep the before and after versions.").foregroundStyle(.secondary) }
                ForEach(versions) { version in
                    Section {
                        Text(version.snapshot.name).appTextRole(.control)
                        Text("\(phase(version.phase)) · \(version.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        Text("\(version.snapshot.servings?.formatted() ?? "Unknown") servings · \(version.snapshot.nutritionBasisLabel)")
                            .appTextRole(.secondary)
                        Text("\(version.snapshot.nutrition.calories.formatted()) cal in the saved basis")
                        Text("Nutrition origin: \(version.snapshot.nutritionOrigin == .ingredients ? "Matched ingredients" : version.snapshot.nutritionOrigin == .aiEstimate ? "AI estimate" : "Not recorded") · unknown nutrients stay unknown")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("recipe_version_origin_\(version.id)")
                        Button {
                            if !expandedVersionIDs.insert(version.id).inserted { expandedVersionIDs.remove(version.id) }
                        } label: {
                            HStack {
                                Text(expandedVersionIDs.contains(version.id) ? "Hide this snapshot" : "Inspect this snapshot")
                                Spacer()
                                Image(systemName: expandedVersionIDs.contains(version.id) ? "chevron.up" : "chevron.down")
                                    .accessibilityHidden(true)
                            }
                        }.accessibilityValue(expandedVersionIDs.contains(version.id) ? "Expanded" : "Collapsed")
                            .accessibilityIdentifier("recipe_version_inspect_\(version.id)")
                        if expandedVersionIDs.contains(version.id) {
                            // Each source line owns its List row and accessibility frame.
                            ForEach(Array(RecipePortionRules.originalIngredientLines(for: version.snapshot).enumerated()), id: \.offset) { index, line in
                                Text(line).accessibilityIdentifier("recipe_version_ingredient_\(version.id)_\(index)")
                            }
                            ForEach(Array(version.snapshot.instructions.enumerated()), id: \.offset) { index, step in
                                Text(step).accessibilityIdentifier("recipe_version_instruction_\(version.id)_\(index)")
                            }
                        }
                        Button("Review restore") { Task { await prepare(version) } }.frame(minHeight: 44)
                            .accessibilityIdentifier("recipe_version_review_\(version.id)")
                    }
                }
                if versions.count == 60 { Text("Showing the latest 60 recorded snapshots.").foregroundStyle(.secondary) }
            }.appFormStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recipe_history_list")
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Recipe versions").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $review, onDismiss: { Task { await refreshCurrent(); await load() } }) { session in
                RecipeVersionRestoreReviewView(session: session) { Task { await refreshCurrent() } }
            }
        }.modifier(RecipeVersionOwnerBoundary(owner: owner))
    }
    private var exportJSON: String? {
        guard !versions.isEmpty, DIContainer.shared.authService.currentUserID == owner else { return nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(versions)).flatMap { String(data: $0, encoding: .utf8) }
    }
    private func phase(_ phase: RecipeVersionRecord.Phase) -> String {
        switch phase {
        case .before: "Before edit"
        case .saved: "Saved version"
        case .restored: "Restored version"
        }
    }
    private func load() async {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let values = try await service.fetchRecipeVersionHistory(recipeID: recipeID)
            guard DIContainer.shared.authService.currentUserID == owner else { return }
            versions = values; errorMessage = nil
        } catch { errorMessage = "Saved versions could not be loaded. Current recipes and earlier snapshots are kept. " + error.localizedDescription }
    }
    private func prepare(_ version: RecipeVersionRecord) async {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        do {
            let values = try await DIContainer.shared.nutritionRepository.fetchRecipes(userID: owner)
            guard DIContainer.shared.authService.currentUserID == owner,
                  let current = values.first(where: { $0.id == recipeID }) else { throw RecipeRevisionError.changed }
            let proposal = RecipeVersionRestoreProposal(userID: owner, version: version, expected: current)
            try proposal.validate()
            review = RecipeVersionRestoreSession(userID: owner, proposal: proposal)
        } catch { errorMessage = error.localizedDescription }
    }
    private func resume() {
        let session = RecipeVersionRestoreSession(userID: owner)
        if session.checkpoint != nil || session.errorMessage != nil { review = session } else { errorMessage = "No pending version restore is kept for this account." }
    }
    private func refreshCurrent() async {
        guard let owner, DIContainer.shared.authService.currentUserID == owner else { return }
        await service.fetchUserRecipes()
        guard DIContainer.shared.authService.currentUserID == owner else { return }
        onChanged(service.userRecipes.first { $0.id == recipeID })
    }
}

struct RecipeVersionRestoreReviewView: View {
    @ObservedObject var session: RecipeVersionRestoreSession
    let onFinished: () -> Void
    @EnvironmentObject private var service: RecipeService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let value = session.checkpoint {
                    Text(value.proposal.version.snapshot.name).appTextRole(.sectionTitle)
                    Text("Restore the content recorded \(value.proposal.version.recordedAt.formatted(date: .abbreviated, time: .shortened)).")
                    Text("This restores recipe ingredients, yield, finished weight, nutrition, instructions and source evidence. Current favorites, tags and archive state stay. Existing diary logs, planned portions and physical stock are unchanged.")
                    Text("Current yield: \(value.proposal.expected.servings?.formatted() ?? "Unknown") → restored yield: \(value.proposal.version.snapshot.servings?.formatted() ?? "Unknown")")
                    Text("The opening recipe is checked again when saving; a concurrent edit blocks this restore.")
                    if value.submitted, !session.finished {
                        Button("Check restore status") { Task { await session.resolve(using: service, cancelIfUnaccepted: false) } }.frame(minHeight: 44).accessibilityIdentifier("recipe_restore_status")
                        Button("Cancel pending restore", role: .destructive) { Task { await session.resolve(using: service, cancelIfUnaccepted: true) } }.frame(minHeight: 44).accessibilityIdentifier("recipe_restore_cancel")
                    }
                    if !value.submitted { Button("Discard restore review", role: .destructive) { finish() }.frame(minHeight: 44) }
                    if session.finished { Text(value.resolution == .accepted ? "Restore accepted. The current library was refreshed." : "Restore cancelled before acceptance.") }
                } else if session.errorMessage == nil {
                    Text("No pending version restore is kept for this account.")
                }
            }.appFormStyle()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recipe_restore_list")
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Review version restore").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(session.isWorking) } }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                    if let error = session.errorMessage { Text(error).foregroundStyle(AppPalette.caution).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("recipe_restore_error") }
                    Button(session.finished ? "Done" : session.isWorking ? "Restoring…" : "Restore this version") {
                        if session.finished { finish() } else { Task { await session.save(using: service) } }
                    }.buttonStyle(AppActionButtonStyle(.primary)).disabled(session.isWorking || session.checkpoint == nil).accessibilityIdentifier("recipe_restore_confirm")
                }.padding().background(AppPalette.canvas).accessibilityElement(children: .contain)
            }
        }.interactiveDismissDisabled(session.isWorking)
            .modifier(RecipeVersionOwnerBoundary(owner: session.userID))
    }
    private func finish() { if session.finish() { onFinished(); dismiss() } }
}

/// Closing an account-bound review never clears its durable proposal.
private struct RecipeVersionOwnerBoundary: ViewModifier {
    let owner: String?
    @Environment(\.dismiss) private var dismiss
    @State private var observer: Any?
    @State private var observedAuth: (any AuthServiceProtocol)?
    func body(content: Content) -> some View {
        content.task {
            guard let owner, DIContainer.shared.authService.currentUserID == owner,
                  let auth = DIContainer.shared.authService else { dismiss(); return }
            guard observer == nil else { return }
            observedAuth = auth
            observer = auth.observeAuthState { current in
                if current != owner { Task { @MainActor in dismiss() } }
            }
        }.onDisappear {
            if let observer { observedAuth?.removeObserver(observer) }
            observer = nil; observedAuth = nil
        }
    }
}
