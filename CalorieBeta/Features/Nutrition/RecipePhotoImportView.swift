import CryptoKit
import ImageIO
import MyFitPlateCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision
import VisionKit

struct RecipePhotoCheckpoint: Codable {
    var draft = RecipeDocumentDraft()
    var checkedPages = Set<UUID>()
    var submission: RecipeImportProvenance?
}

/// Call only after the corresponding reviewed import finishes saving. A later import/edit wins.
@MainActor
enum RecipePhotoImportCheckpointStore {
    static let scope = "recipe-photo-document-import"
    static func finish(userID: String, provenance: RecipeImportProvenance, store: EditorDraftStore = EditorDraftStore()) throws {
        guard DIContainer.shared.authService.currentUserID == userID else { throw RecipeDocumentError.noText }
        guard let saved = try store.load(RecipePhotoCheckpoint.self, userID: userID, scope: scope),
              saved.value.submission == provenance else { return }
        try store.remove(userID: userID, scope: scope)
    }
}

@MainActor
final class RecipePhotoImportModel: ObservableObject {
    @Published private(set) var checkpoint = RecipePhotoCheckpoint()
    @Published private(set) var processing = false
    @Published private(set) var pendingCorrections = false
    @Published private(set) var restored = false
    @Published private(set) var handedOff = false
    @Published var errorMessage: String?
    private let ownerID: String?
    private let store: EditorDraftStore
    private var expected: String?
    private var unreadable = false
    private var pendingWrite: Task<Void, Never>?

    init(userID: String?, store: EditorDraftStore = EditorDraftStore()) {
        ownerID = userID; self.store = store
        guard let userID, DIContainer.shared.authService.currentUserID == userID else {
            errorMessage = "Sign in before capturing a recipe."; return
        }
        do {
            if let saved = try store.load(RecipePhotoCheckpoint.self, userID: userID, scope: RecipePhotoImportCheckpointStore.scope) {
                guard saved.value.draft.pages.count <= 8,
                      Set(saved.value.draft.pages.map(\.digest)).count == saved.value.draft.pages.count else { throw RecipeDocumentError.duplicateOrLimit }
                checkpoint = saved.value; expected = try PlanFingerprint.make(saved.value); restored = true
            }
        } catch { unreadable = true; errorMessage = "Your previous recipe capture couldn't be opened. It has been kept on this device; close this sheet to keep it intact." }
    }

    var canCapture: Bool { ownerID != nil && !unreadable && !processing && !handedOff && DIContainer.shared.authService.currentUserID == ownerID }
    var canReview: Bool {
        canCapture && !checkpoint.draft.pages.isEmpty && checkpoint.draft.looksLikeRecipe
            && checkpoint.draft.pages.allSatisfy { checkpoint.checkedPages.contains($0.id) }
    }
    func prepareToClose() -> Bool {
        unreadable || ownerID == nil || DIContainer.shared.authService.currentUserID != ownerID || flush()
    }

    func editText(pageID: UUID, text: String) {
        guard canCapture, let index = checkpoint.draft.pages.firstIndex(where: { $0.id == pageID }) else { return }
        checkpoint.draft.pages[index].reviewedText = text
        checkpoint.checkedPages.remove(pageID); checkpoint.submission = nil
        scheduleWrite()
    }
    func setRetainSource(_ value: Bool) {
        guard canCapture else { return }
        checkpoint.draft.retainSourceText = value; checkpoint.submission = nil; _ = flush()
    }
    func setChecked(_ id: UUID, value: Bool) {
        guard canCapture else { return }
        if value { checkpoint.checkedPages.insert(id) } else { checkpoint.checkedPages.remove(id) }
        checkpoint.submission = nil; _ = flush()
    }
    func remove(_ id: UUID) {
        guard canCapture else { return }
        checkpoint.draft.pages.removeAll { $0.id == id }; checkpoint.checkedPages.remove(id)
        checkpoint.submission = nil; _ = flush()
    }
    func move(_ id: UUID, by offset: Int) {
        guard canCapture, let index = checkpoint.draft.pages.firstIndex(where: { $0.id == id }),
              checkpoint.draft.pages.indices.contains(index + offset) else { return }
        checkpoint.draft.pages.swapAt(index, index + offset); checkpoint.submission = nil; _ = flush()
    }

    func recognize(_ images: [Data], replacing pageID: UUID? = nil) async {
        guard canCapture, flush() else { return }
        processing = true; defer { processing = false }
        var failures: [String] = []
        for data in images {
            guard DIContainer.shared.authService.currentUserID == ownerID else { return }
            if pageID == nil && checkpoint.draft.pages.count >= 8 {
                failures.append(RecipeDocumentError.duplicateOrLimit.localizedDescription); break
            }
            do {
                let page = try await Task.detached(priority: .userInitiated) { try RecipePhotoOCR.page(from: data) }.value
                guard DIContainer.shared.authService.currentUserID == ownerID else { return }
                if let pageID {
                    guard let index = checkpoint.draft.pages.firstIndex(where: { $0.id == pageID }),
                          !checkpoint.draft.pages.contains(where: { $0.id != pageID && $0.digest == page.digest }) else { throw RecipeDocumentError.duplicateOrLimit }
                    checkpoint.draft.pages[index] = page; checkpoint.checkedPages.remove(pageID)
                } else { try checkpoint.draft.append(page) }
                checkpoint.submission = nil
                guard flush() else { return }
                if pageID != nil { break }
            } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: " ") }
    }

    func reviewed() -> (String, RecipeImportProvenance)? {
        guard canReview, flush() else { return nil }
        let provenance = checkpoint.submission ?? checkpoint.draft.provenance
        checkpoint.submission = provenance
        guard flush() else { return nil }
        handedOff = true
        return (checkpoint.draft.combinedText, provenance)
    }

    @discardableResult func flush() -> Bool {
        pendingWrite?.cancel(); pendingWrite = nil
        guard !unreadable, let ownerID, DIContainer.shared.authService.currentUserID == ownerID else { return false }
        do {
            let current = try store.load(RecipePhotoCheckpoint.self, userID: ownerID, scope: RecipePhotoImportCheckpointStore.scope)?.value
            let actual = try current.map { try PlanFingerprint.make($0) }
            guard actual == expected else {
                errorMessage = "This recipe capture changed in another editor. Close and reopen it before making more changes."
                return false
            }
            try store.save(checkpoint, userID: ownerID, scope: RecipePhotoImportCheckpointStore.scope)
            expected = try PlanFingerprint.make(checkpoint)
            pendingCorrections = false; errorMessage = nil; return true
        } catch {
            pendingCorrections = true
            errorMessage = "Couldn't keep the latest recipe capture on this device. Keep this sheet open and retry before leaving."
            return false
        }
    }
    private func scheduleWrite() {
        pendingWrite?.cancel(); pendingCorrections = true
        pendingWrite = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            _ = self?.flush()
        }
    }
}

enum RecipePhotoOCR {
    static func page(from data: Data) throws -> RecipeDocumentPage {
        guard data.count <= 25_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_400
              ] as CFDictionary) else { throw RecipeDocumentError.noText }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> RecipeDocumentLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return RecipeDocumentLine(text: candidate.string, confidence: Double(candidate.confidence),
                x: box.minX, y: box.minY, width: box.width, height: box.height)
        }.sorted { abs($0.y - $1.y) < 0.008 ? $0.x < $1.x : $0.y > $1.y }
        guard !lines.isEmpty else { throw RecipeDocumentError.noText }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_200
        ] as CFDictionary) else { throw RecipeDocumentError.noText }
        guard let bytes = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { throw RecipeDocumentError.noText }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(destination), (1...2_000_000).contains(CFDataGetLength(bytes)),
              let pointer = CFDataGetBytePtr(bytes) else { throw RecipeDocumentError.noText }
        let preview = Data(bytes: pointer, count: CFDataGetLength(bytes))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return RecipeDocumentPage(digest: digest, lines: lines, preview: preview)
    }
}

/// Captures written recipe pages locally. A reviewed-text callback opens the normal recipe draft;
/// it does not save a recipe or send page images to a model.
@MainActor
struct RecipePhotoImportView: View {
    let onReviewedText: (String, RecipeImportProvenance) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: RecipePhotoImportModel
    @State private var photos: [PhotosPickerItem] = []
    @State private var replacementPhoto: PhotosPickerItem?
    @State private var replacementID: UUID?
    @State private var showingReplacement = false
    @State private var showingCamera = false
    @State private var expandedPage: UUID?
    @State private var removingPage: UUID?
    @State private var loadingPhotos = false

    init(onReviewedText: @escaping (String, RecipeImportProvenance) -> Void) {
        self.onReviewedText = onReviewedText
        _model = StateObject(wrappedValue: RecipePhotoImportModel(userID: DIContainer.shared.authService.currentUserID))
    }

    @discardableResult
    static func finish(userID: String, provenance: RecipeImportProvenance) -> Bool {
        do { try RecipePhotoImportCheckpointStore.finish(userID: userID, provenance: provenance); return true } catch { return false }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Capture a written recipe from a cookbook, card or printout. For plated food, use the food camera.")
                        .appTextRole(.secondary).foregroundStyle(.secondary)
                    Text(model.restored ? "Restored your captured pages and corrections." : "Captured pages and corrections are kept privately on this device.")
                        .appTextRole(.secondary).foregroundStyle(.secondary).accessibilityIdentifier("recipe_photo_status")
                    if model.pendingCorrections { Text("Saving corrections…").foregroundStyle(.secondary) }
                    if loadingPhotos { ProgressView("Opening selected photos…") }
                    if model.processing { ProgressView("Reading recipe text on this device…") }
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(AppPalette.caution).accessibilityIdentifier("recipe_photo_error")
                        Button("Retry keeping changes") { _ = model.flush() }.frame(minHeight: 44)
                    }
                }
                Section("Add pages · \(model.checkpoint.draft.pages.count) of 8") {
                    PhotosPicker(selection: $photos, maxSelectionCount: max(1, 8 - model.checkpoint.draft.pages.count), matching: .images) {
                        Label("Choose recipe photos", systemImage: "photo.on.rectangle").frame(minHeight: 44)
                    }
                    .disabled(!model.canCapture || loadingPhotos || model.checkpoint.draft.pages.count >= 8)
                    .accessibilityIdentifier("recipe_photo_choose")
                    if VNDocumentCameraViewController.isSupported {
                        Button("Scan recipe pages", systemImage: "doc.viewfinder") { replacementID = nil; showingCamera = true }
                            .frame(minHeight: 44).disabled(!model.canCapture || loadingPhotos || model.checkpoint.draft.pages.count >= 8)
                            .accessibilityIdentifier("recipe_photo_camera")
                    }
                }
                ForEach(Array(model.checkpoint.draft.pages.enumerated()), id: \.element.id) { index, page in
                    pageSection(page, index: index)
                }
                if !model.checkpoint.draft.pages.isEmpty {
                    Section("Source privacy") {
                        Toggle("Keep reviewed source text with the recipe", isOn: Binding(
                            get: { model.checkpoint.draft.retainSourceText }, set: { model.setRetainSource($0) }))
                        Text("Page photos stay on this device until you save the reviewed recipe. They are not included in your cloud recipe.")
                            .appTextRole(.caption).foregroundStyle(.secondary)
                        if !model.checkpoint.draft.looksLikeRecipe {
                            Text(RecipeDocumentError.notRecipe.localizedDescription).foregroundStyle(AppPalette.caution)
                        }
                    }
                }
            }.appFormStyle()
            .buttonStyle(AppListButtonStyle())
            .navigationTitle("Capture a recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Close") { if model.prepareToClose() { dismiss() } }.disabled(model.processing || loadingPhotos)
            } }
            .safeAreaInset(edge: .bottom) {
                Button("Use reviewed recipe text") {
                    if let (text, provenance) = model.reviewed() { onReviewedText(text, provenance); dismiss() }
                }
                .buttonStyle(AppActionButtonStyle(.primary)).disabled(!model.canReview || loadingPhotos)
                .padding(AppSpacing.screenHorizontal).background(AppPalette.canvas)
                .accessibilityIdentifier("recipe_photo_use_text")
            }
            .photosPicker(isPresented: $showingReplacement, selection: $replacementPhoto, matching: .images)
            .sheet(isPresented: $showingCamera) {
                RecipeDocumentScanner { images in
                    showingCamera = false
                    Task { await model.recognize(images, replacing: replacementID) }
                } onCancel: { showingCamera = false } onError: { error in
                    showingCamera = false; model.errorMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Remove this captured page?", isPresented: Binding(get: { removingPage != nil }, set: { if !$0 { removingPage = nil } }), titleVisibility: .visible) {
                Button("Remove page", role: .destructive) { if let removingPage { model.remove(removingPage) }; removingPage = nil }
            } message: { Text("This removes only its private capture and text. It does not change any saved recipe.") }
            .onChange(of: photos) { _, selection in
                guard !selection.isEmpty else { return }
                Task {
                    loadingPhotos = true; defer { loadingPhotos = false }
                    var data: [Data] = []
                    for item in selection { if let value = try? await item.loadTransferable(type: Data.self) { data.append(value) } }
                    await model.recognize(data)
                    if data.count != selection.count { model.errorMessage = "Some selected photos couldn't open. Already captured pages are still here." }
                    photos = []
                }
            }
            .onChange(of: replacementPhoto) { _, item in
                guard let item else { return }
                Task {
                    loadingPhotos = true; defer { loadingPhotos = false }
                    if let data = try? await item.loadTransferable(type: Data.self) { await model.recognize([data], replacing: replacementID) } else { model.errorMessage = "This photo couldn't open. The previous page is still kept." }
                    replacementPhoto = nil
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { _ = model.flush() } }
            .interactiveDismissDisabled(true)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recipe_photo_import")
        }
    }

    @ViewBuilder private func pageSection(_ page: RecipeDocumentPage, index: Int) -> some View {
        Section("Page \(index + 1)") {
            if let data = page.preview, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                    .accessibilityLabel("Captured recipe page \(index + 1)")
            }
            let uncertain = page.lines.filter(\.needsReview)
            if !uncertain.isEmpty {
                DisclosureGroup("Check \(uncertain.count) uncertain text line\(uncertain.count == 1 ? "" : "s")") {
                    ForEach(Array(uncertain.enumerated()), id: \.offset) { _, line in
                        Label(line.text, systemImage: "text.badge.checkmark")
                            .appTextRole(.secondary).foregroundStyle(AppPalette.caution)
                    }
                    Text("Compare these with the page and correct the text below. Columns, fractions and tables can need extra care.")
                        .appTextRole(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Review and correct page text", isExpanded: Binding(
                get: { expandedPage == page.id }, set: { expandedPage = $0 ? page.id : nil })) {
                TextEditor(text: Binding(get: { model.checkpoint.draft.pages.first(where: { $0.id == page.id })?.reviewedText ?? "" },
                                        set: { model.editText(pageID: page.id, text: $0) }))
                    .frame(minHeight: 240).accessibilityLabel("Recipe text for page \(index + 1)")
                    .accessibilityIdentifier("recipe_photo_text_\(page.id)")
            }
            Toggle("I've checked the text and ingredient amounts", isOn: Binding(
                get: { model.checkpoint.checkedPages.contains(page.id) }, set: { model.setChecked(page.id, value: $0) }))
                .disabled(model.processing).accessibilityIdentifier("recipe_photo_checked_\(page.id)")
            Menu("Page actions") {
                Button("Move earlier") { model.move(page.id, by: -1) }.disabled(index == 0)
                Button("Move later") { model.move(page.id, by: 1) }.disabled(index == model.checkpoint.draft.pages.count - 1)
                Button("Replace from Photos") { replacementID = page.id; showingReplacement = true }
                if VNDocumentCameraViewController.isSupported {
                    Button("Rescan with camera") { replacementID = page.id; showingCamera = true }
                }
                Button("Remove page", role: .destructive) { removingPage = page.id }
            }
            .frame(minHeight: 44).disabled(!model.canCapture || loadingPhotos)
        }
    }
}

private struct RecipeDocumentScanner: UIViewControllerRepresentable {
    let onImages: ([Data]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: RecipeDocumentScanner
        init(_ parent: RecipeDocumentScanner) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onImages((0..<min(scan.pageCount, 9)).compactMap { scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.85) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onError(error) }
    }
}
