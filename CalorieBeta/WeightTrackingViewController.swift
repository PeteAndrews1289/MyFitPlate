import UIKit
import SwiftUI
import DGCharts
import FirebaseAuth
import FirebaseFirestore

// This view controller manages the weight tracking interface using a SwiftUI chart embedded
// in a UIKit environment, fetching and displaying weight history data from Firestore.
class WeightTrackingViewController: UIViewController {
    // *** FIX: Update property type to include ID ***
    var weightHistory: [(id: String, date: Date, weight: Double)] = [] // Stores weight data locally for chart use.
    var currentWeight: Double = 150.0 // Default value, will be updated

    // Optional reference to the hosting controller for the SwiftUI chart to manage updates.
    var hostingController: UIHostingController<WeightChartView>? // Retains reference to avoid reloading issues.

    override func viewDidLoad() {
        super.viewDidLoad() // Calls the superclass's initialization.
        view.backgroundColor = .systemBackground // Use system background

        // Load data first
        loadWeightData()
    }

    // Sets up the SwiftUI chart within the UIKit view controller.
    private func setupSwiftUIChart() {
        guard hostingController == nil else {
            updateChart()
            return
        }

        // Create the SwiftUI view with the correctly typed history
        let chartViewContent = WeightChartView(weightHistory: self.weightHistory, currentWeight: self.currentWeight)
        let chartHostingController = UIHostingController(rootView: chartViewContent)

        addChild(chartHostingController)
        chartHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chartHostingController.view)
        chartHostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            chartHostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chartHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chartHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chartHostingController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        hostingController = chartHostingController
    }

    // Fetches weight history data AND current weight from Firestore.
    private func loadWeightData() {
        guard let userID = Auth.auth().currentUser?.uid else {
            print("❌ User not logged in in WeightTrackingViewController")
            return
        }
        let db = Firestore.firestore()
        let group = DispatchGroup()

        // Fetch Current Weight
        group.enter()
        db.collection("users").document(userID).getDocument { document, error in
            defer { group.leave() }
            if let document = document, document.exists, let weight = document.data()?["weight"] as? Double {
                self.currentWeight = weight
                print("✅ Fetched current weight: \(self.currentWeight)")
            } else if let error = error {
                 print("❌ Error fetching current weight: \(error.localizedDescription)")
            } else {
                print("⚠️ Could not find current weight, using default: \(self.currentWeight)")
            }
        }

        // Fetch Weight History
        group.enter()
        db.collection("users").document(userID).collection("weightHistory")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                defer { group.leave() }
                if let error = error {
                    print("❌ Error fetching weight history: \(error.localizedDescription)")
                    return
                }

                // *** Ensure mapping includes the ID and matches the property type ***
                self.weightHistory = snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    if let weight = data["weight"] as? Double,
                       let timestamp = data["timestamp"] as? Timestamp {
                        // Create tuple with id, date, weight
                        return (id: doc.documentID, date: timestamp.dateValue(), weight: weight)
                    }
                    return nil
                } ?? []
                // Ensure sorting if needed (Firestore order is primary)
                self.weightHistory.sort { $0.date < $1.date }
                print("✅ Fetched weight history count: \(self.weightHistory.count)")
            }

        // Update UI after both fetches complete
        group.notify(queue: .main) {
             print("🔄 Both weight fetches completed. Setting up/updating chart.")
             if self.hostingController == nil {
                 self.setupSwiftUIChart()
             } else {
                 self.updateChart()
             }
        }
    }

    // Updates the SwiftUI chart with the latest weight history data.
    private func updateChart() {
        guard let hostingController = hostingController else {
            print("⚠️ Attempted to update chart, but hostingController is nil.")
            return
        }
        // Pass the correctly typed history
        hostingController.rootView = WeightChartView(weightHistory: self.weightHistory, currentWeight: self.currentWeight)
        print("✅ Updated chart with \(weightHistory.count) history points and current weight \(currentWeight)")
    }
}
