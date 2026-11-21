import MyFitPlateCore
import SwiftUI

struct StrengthGymLibraryView: View {
    var onSelect: ((StrengthGymProfile) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var profiles: [StrengthGymProfile] = []
    @State private var editing: StrengthGymProfile?
    @State private var creating = false
    @State private var removing: StrengthGymProfile?
    @State private var errorMessage: String?
    private let ownerID = DIContainer.shared.authService.currentUserID

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: AppSpacing.compact) {
                        if profiles.isEmpty {
                            Text("Set up your first gym").appTextRole(.control)
                        }
                        Text("Keep your bars, dumbbell racks and machines ready for each workout.")
                            .appTextRole(.secondary).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(AppPalette.caution) } }
                ForEach(profiles) { profile in
                    Section {
                        VStack(alignment: .leading, spacing: AppSpacing.compact) {
                            Text(profile.name).appTextRole(.control)
                            Text("\(profile.implements.count) implements · saved on this device")
                                .appTextRole(.secondary).foregroundStyle(.secondary)
                        }
                        if let onSelect {
                            Button("Use \(profile.name)") { onSelect(profile); dismiss() }
                                .frame(minHeight: 44).accessibilityIdentifier("gym_profile_use_\(profile.id)")
                        }
                        Button("Edit profile") { editing = profile }.frame(minHeight: 44)
                        Button("Delete profile", role: .destructive) { removing = profile }.frame(minHeight: 44)
                    }
                }
                Section {
                    Button("Add gym profile", systemImage: "plus") { creating = true }
                        .frame(minHeight: 44).accessibilityIdentifier("gym_profile_add")
                } footer: {
                    Text("Profiles are saved on this device. Review the equipment before applying it to a workout.")
                        .appTextRole(.caption)
                }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("gym_profile_library")
            .navigationTitle("My gyms").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $creating, onDismiss: reload) { StrengthGymProfileEditorView(profile: nil, didSave: reload) }
            .sheet(item: $editing, onDismiss: reload) { profile in StrengthGymProfileEditorView(profile: profile, didSave: reload) }
            .confirmationDialog("Delete this gym profile?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Delete profile", role: .destructive) {
                    guard let ownerID, let removing else { return }
                    do { try StrengthGymProfileStore().remove(removing, userID: ownerID); reload() } catch { errorMessage = error.localizedDescription }
                    self.removing = nil
                }
            } message: { Text("Existing sessions keep their original equipment snapshots. Exercise-local setups stay in place.") }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        guard let ownerID else { errorMessage = StrengthSessionToolsError.accountChanged.localizedDescription; return }
        do { profiles = try StrengthGymProfileStore().profiles(userID: ownerID); errorMessage = nil } catch { errorMessage = "Couldn't open your gym profiles. Existing saved setups have been kept. \(error.localizedDescription)" }
    }
}

private struct GymProfileEditorCheckpoint: Codable {
    var expected: StrengthGymProfile?
    var draft: StrengthGymProfile
}

private struct StrengthGymProfileEditorView: View {
    let didSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StrengthGymProfile
    @State private var expected: StrengthGymProfile?
    @State private var editingImplement: StrengthGymImplement?
    @State private var errorMessage: String?
    @State private var restored = false
    @State private var unreadable = false
    @State private var ready = false
    @State private var accepted = false
    @State private var confirmingDiscard = false
    @FocusState private var nameFocused: Bool
    private let originalID: String?
    private let ownerID = DIContainer.shared.authService.currentUserID
    private let store = EditorDraftStore()
    private var scope: String { "strength-gym-editor-\(originalID ?? "new")" }
    private var checkpointData: Data? { try? JSONEncoder().encode(GymProfileEditorCheckpoint(expected: expected, draft: draft)) }

    init(profile: StrengthGymProfile?, didSave: @escaping () -> Void) {
        originalID = profile?.id; self.didSave = didSave
        _draft = State(initialValue: profile ?? StrengthGymProfile(name: ""))
        _expected = State(initialValue: profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if restored { Text("Restored your unsaved profile changes.").foregroundStyle(.secondary) }
                    TextField("Gym name", text: $draft.name).focused($nameFocused).accessibilityIdentifier("gym_profile_name")
                    Text("A profile contains physical inventory. Editing it never changes equipment already recorded in a workout.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                }
                ForEach(draft.implements) { implement in
                    Section {
                        Text(implement.name).appTextRole(.control)
                        Text(equipmentSummary(implement.equipment)).appTextRole(.secondary).foregroundStyle(.secondary)
                        Button("Edit \(implement.name)") { editingImplement = implement }.frame(minHeight: 44)
                        Button("Remove implement", role: .destructive) { draft.implements.removeAll { $0.id == implement.id } }
                            .frame(minHeight: 44)
                    }
                }
                Section {
                    Button("Add bar, rack or machine", systemImage: "plus") {
                        editingImplement = StrengthGymImplement(name: "New implement", equipment: StrengthEquipment(
                            loadingMeaning: .total, name: "New implement", availableWeights: Array(stride(from: 5, through: 100, by: 5))))
                    }
                    .frame(minHeight: 44).disabled(draft.implements.count >= 24)
                    .accessibilityIdentifier("gym_profile_add_implement")
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(AppPalette.caution).accessibilityIdentifier("gym_profile_error") } }
                if restored || unreadable {
                    Section { Button("Discard this editor draft", role: .destructive) { confirmingDiscard = true }.frame(minHeight: 44) }
                }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("gym_profile_editor")
            .disabled(accepted)
            .navigationTitle(originalID == nil ? "New gym" : "Edit gym").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { if accepted || persist() { dismiss() } } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { nameFocused = false }.accessibilityIdentifier("gym_profile_keyboard_done")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(accepted ? "Done" : "Save gym profile", action: save)
                    .buttonStyle(AppActionButtonStyle(.primary))
                    .disabled(!accepted && (!draft.isValid || unreadable))
                    .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                    .accessibilityIdentifier("gym_profile_save")
            }
            .sheet(item: $editingImplement) { implement in
                StrengthEquipmentSetupView(exerciseName: "\(draft.name.isEmpty ? "Gym profile" : draft.name) · \(implement.name)",
                    equipment: implement.equipment, offersGymProfiles: false) { equipment in
                    guard DIContainer.shared.authService.currentUserID == ownerID, let equipment else { throw StrengthSessionToolsError.accountChanged }
                    let name = equipment.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !name.isEmpty else { throw StrengthSessionToolsError.invalid }
                    let updated = StrengthGymImplement(id: implement.id, name: name, equipment: equipment)
                    if let index = draft.implements.firstIndex(where: { $0.id == implement.id }) { draft.implements[index] = updated } else { draft.implements.append(updated) }
                    guard persist() else { throw CocoaError(.fileWriteUnknown) }
                }
            }
            .onAppear(perform: restore)
            .onChange(of: checkpointData) { _, _ in if ready && !accepted { _ = persist() } }
            .confirmationDialog("Discard these gym edits?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard editor draft", role: .destructive, action: discard)
                Button("Keep editing", role: .cancel) {}
            } message: { Text("Your saved gym profiles and workout records stay intact.") }
            .interactiveDismissDisabled(true)
        }
    }

    private func restore() {
        guard !ready, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return }
        do {
            if let value = try store.load(GymProfileEditorCheckpoint.self, userID: ownerID, scope: scope)?.value {
                draft = value.draft; expected = value.expected; restored = true
            }
        } catch { unreadable = true; errorMessage = "Your previous gym draft couldn't be opened. It has been kept." }
        ready = true
    }
    @discardableResult private func persist() -> Bool {
        guard ready, !unreadable, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return false }
        do {
            if draft == expected || (expected == nil && draft.name.isEmpty && draft.implements.isEmpty) {
                try store.remove(userID: ownerID, scope: scope)
            } else {
                try store.save(GymProfileEditorCheckpoint(expected: expected, draft: draft), userID: ownerID, scope: scope)
            }
            return true
        } catch { errorMessage = "Couldn't keep these gym edits on this device. Keep the editor open and try again."; return false }
    }
    private func discard() {
        guard let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return }
        do { try store.remove(userID: ownerID, scope: scope); accepted = true; dismiss() } catch { errorMessage = "Couldn't discard this draft. It is still kept on the device." }
    }
    private func save() {
        if accepted { dismiss(); return }
        guard let ownerID, persist() else { return }
        do {
            let saved = try StrengthGymProfileStore().save(draft, expected: expected, userID: ownerID)
            draft = saved; expected = saved; _ = persist(); accepted = true
            try store.remove(userID: ownerID, scope: scope)
            didSave(); dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct StrengthGymEquipmentPickerView: View {
    let onChoose: (StrengthEquipment) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var profile: StrengthGymProfile?
    @State private var showingLibrary = false

    var body: some View {
        NavigationStack {
            List {
                Section { Text("Choose an implement from a saved gym. You can review its exact inventory before saving this exercise.").foregroundStyle(.secondary) }
                if let profile {
                    Section(profile.name) {
                        ForEach(profile.implements) { implement in
                            Button {
                                if let equipment = profile.equipment(for: implement.id) { onChoose(equipment); dismiss() }
                            } label: {
                                VStack(alignment: .leading, spacing: AppSpacing.compact) {
                                    Text(implement.name)
                                    Text(equipmentSummary(implement.equipment)).appTextRole(.secondary).foregroundStyle(.secondary)
                                }.frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("gym_implement_choose_\(implement.id)")
                        }
                    }
                }
                Section { Button(profile == nil ? "Choose or create a gym" : "Choose another gym") { showingLibrary = true }.frame(minHeight: 44) }
            }
            .appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Saved gym equipment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingLibrary) { StrengthGymLibraryView { profile = $0 } }
        }
    }
}

func equipmentSummary(_ equipment: StrengthEquipment) -> String {
    let unit = equipment.unit
    let loads = equipment.attainableLoads
    guard let first = loads.first, let last = loads.last else { return "Review equipment" }
    let low = unit.displayWeight(first).formatted(.number.precision(.fractionLength(0...3)))
    let high = unit.displayWeight(last).formatted(.number.precision(.fractionLength(0...3)))
    return "\(equipment.kind.title) · \(low)–\(high) \(unit.rawValue) · \(equipment.loadingMeaning.title)"
}
