import UIKit
import SwiftUI
import DGCharts
import FirebaseAuth

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
        
        Task {
            var fetchedWeight = self.currentWeight
            var fetchedHistory: [(id: String, date: Date, weight: Double)] = []
            
            // Fetch Current Weight
            await withCheckedContinuation { continuation in
                DIContainer.shared.settingsRepository.fetchUserGoals(userID: userID) { data in
                    if let weight = data?["weight"] as? Double {
                        fetchedWeight = weight
                    }
                    continuation.resume()
                }
            }
            
            // Fetch History
            do {
                fetchedHistory = try await DIContainer.shared.settingsRepository.fetchWeightHistory(userID: userID)
            } catch {
                AppLog.health.error("Failed to fetch weight history: \(error.localizedDescription, privacy: .public)")
            }
            
            await MainActor.run {
                self.currentWeight = fetchedWeight
                self.weightHistory = fetchedHistory
                
                if self.hostingController == nil {
                    self.setupSwiftUIChart()
                } else {
                    self.updateChart()
                }
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
