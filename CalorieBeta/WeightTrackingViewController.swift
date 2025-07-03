import UIKit
import SwiftUI
import DGCharts
import FirebaseAuth
import FirebaseFirestore

class WeightTrackingViewController: UIViewController {
    var weightHistory: [(id: String, date: Date, weight: Double)] = []
    var currentWeight: Double = 150.0

    var hostingController: UIHostingController<WeightChartView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadWeightData()
    }

    private func setupSwiftUIChart() {
        guard hostingController == nil else {
            updateChart()
            return
        }

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

    private func loadWeightData() {
        guard let userID = Auth.auth().currentUser?.uid else {
            return
        }
        let db = Firestore.firestore()
        let group = DispatchGroup()

        group.enter()
        db.collection("users").document(userID).getDocument { document, error in
            defer { group.leave() }
            if let document = document, document.exists, let weight = document.data()?["weight"] as? Double {
                self.currentWeight = weight
            } else if let error = error {
                 print("Error fetching current weight: \(error.localizedDescription)")
            }
        }

        group.enter()
        db.collection("users").document(userID).collection("weightHistory")
            .order(by: "timestamp", descending: false)
            .getDocuments { snapshot, error in
                defer { group.leave() }
                if let error = error {
                    print("Error fetching weight history: \(error.localizedDescription)")
                    return
                }

                self.weightHistory = snapshot?.documents.compactMap { doc in
                    let data = doc.data()
                    if let weight = data["weight"] as? Double,
                       let timestamp = data["timestamp"] as? Timestamp {
                        return (id: doc.documentID, date: timestamp.dateValue(), weight: weight)
                    }
                    return nil
                } ?? []
                self.weightHistory.sort { $0.date < $1.date }
            }

        group.notify(queue: .main) {
             if self.hostingController == nil {
                 self.setupSwiftUIChart()
             } else {
                 self.updateChart()
             }
        }
    }

    private func updateChart() {
        guard let hostingController = hostingController else {
            return
        }
        hostingController.rootView = WeightChartView(weightHistory: self.weightHistory, currentWeight: self.currentWeight)
    }
}
