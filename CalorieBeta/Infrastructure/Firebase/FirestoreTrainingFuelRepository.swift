import FirebaseFirestore
import MyFitPlateCore

@MainActor
final class FirestoreTrainingFuelRepository: TrainingFuelRepository {
    private let database: Firestore
    init(database: Firestore = Firestore.firestore()) { self.database = database }

    func merge(_ state: TrainingFuelCloudState, userID: String) async throws -> TrainingFuelCloudState {
        guard DIContainer.shared.authService.currentUserID == userID else { throw TrainingFuelLibraryError.accountChanged }
        let reference = database.collection(FirestoreCollection.users).document(userID)
            .collection("adaptiveTools").document("trainingFuel")
        let result = try await database.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(reference)
                let remote: TrainingFuelCloudState
                if snapshot.exists {
                    guard snapshot.data()?["version"] as? Int == 1,
                          let payload = snapshot.data()?["payload"] as? Data else { throw TrainingFuelLibraryError.unreadable }
                    remote = try JSONDecoder().decode(TrainingFuelCloudState.self, from: payload)
                } else { remote = TrainingFuelCloudState() }
                let merged = try remote.merging(state)
                let data = try JSONEncoder().encode(merged)
                guard data.count < 900_000 else { throw CocoaError(.fileWriteOutOfSpace) }
                transaction.setData(["version": 1, "payload": data, "updatedAt": FieldValue.serverTimestamp()], forDocument: reference)
                return data
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        guard DIContainer.shared.authService.currentUserID == userID else { throw TrainingFuelLibraryError.accountChanged }
        guard let payload = result as? Data else { throw TrainingFuelLibraryError.unreadable }
        return try JSONDecoder().decode(TrainingFuelCloudState.self, from: payload)
    }
}
