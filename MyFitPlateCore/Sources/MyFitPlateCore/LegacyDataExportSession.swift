import Foundation
import Combine

/// The existing two-CSV format, with failures kept distinct from confirmed empty sources.
@MainActor
public final class LegacyDataExportSession: ObservableObject {
    @Published public private(set) var isExporting = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var urls: [URL] = []
    public private(set) var ownerID: String?
    private var generation: UUID?
    private let root: URL

    public init(directory: URL = FileManager.default.temporaryDirectory) { root = directory }

    public func generate(for userID: String) async -> Bool {
        guard !isExporting else { return false }
        cleanup()
        guard DIContainer.shared.authService.currentUserID == userID else {
            errorMessage = "Your account changed. Reopen export from the correct account."
            return false
        }
        let token = UUID()
        generation = token; ownerID = userID; isExporting = true; errorMessage = nil
        let directory = root.appendingPathComponent("MyFitPlateExport-\(token.uuidString)", isDirectory: true)
        var stage = "food diary"
        do {
            let logs = try await DIContainer.shared.nutritionRepository.fetchExportDailyHistory(userID: userID)
            try validate(token, userID: userID)
            stage = "workout history"
            let sessions = try await DIContainer.shared.workoutRepository.fetchExportSessionLogs(userID: userID, sinceDays: 3_650)
            try validate(token, userID: userID)
            stage = "CSV files"
            let foodURL = directory.appendingPathComponent("myfitplate-food-diary.csv")
            let workoutURL = directory.appendingPathComponent("myfitplate-workouts.csv")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeProtected(Data(DataExporter.foodLogCSV(from: logs).utf8), to: foodURL)
            try writeProtected(Data(DataExporter.workoutCSV(from: sessions).utf8), to: workoutURL)
            try validate(token, userID: userID)
            urls = [foodURL, workoutURL]; isExporting = false; generation = nil
            return true
        } catch {
            try? FileManager.default.removeItem(at: directory)
            guard generation == token else { return false }
            generation = nil; isExporting = false; urls = []
            if error is CancellationError {
                errorMessage = DIContainer.shared.authService.currentUserID == userID
                    ? "Export cancelled. No files were shared."
                    : "Your account changed. No files were shared. Reopen export to try again."
            } else {
                errorMessage = "Could not export \(stage). No export was created. Try again."
            }
            return false
        }
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS) || os(watchOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }

    public func cancel() {
        let wasExporting = isExporting
        generation = nil; isExporting = false
        if wasExporting { errorMessage = "Export cancelled. No files were shared." }
        cleanup()
    }

    public func cleanup() {
        Set(urls.map { $0.deletingLastPathComponent() }).forEach { try? FileManager.default.removeItem(at: $0) }
        urls = []
    }

    private func validate(_ token: UUID, userID: String) throws {
        guard generation == token, DIContainer.shared.authService.currentUserID == userID, !Task.isCancelled else { throw CancellationError() }
    }
}
