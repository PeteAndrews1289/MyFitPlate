import MyFitPlateCore

import SwiftUI

/// This is the new "Fitness Analytics" page.
/// It combines workout analytics with related health data like sleep and nutrition.
struct WorkoutAnalyticsView: View {
    @ObservedObject var viewModel: ReportsViewModel

    var body: some View {
        WorkoutEvidenceReportView()
    }
}
