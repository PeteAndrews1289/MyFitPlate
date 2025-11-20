import SwiftUI

// High-level comment: A completely revamped, visually engaging summary screen.
// Uses a grid layout for stats and distinct cards for insights/PRs.
struct WorkoutCompleteAnalyticsView: View {
    @Environment(\.dismiss) var dismiss
    let analytics: WorkoutAnalytics?
    
    // Simple state for a "pop" animation on appear
    @State private var isAnimated = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 1. Header Section
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                            .shadow(color: .orange.opacity(0.5), radius: 10)
                            .scaleEffect(isAnimated ? 1.0 : 0.5)
                            .animation(.spring(response: 0.5, dampingFraction: 0.5), value: isAnimated)
                        
                        Text("Workout Crushed!")
                            .appFont(size: 32, weight: .black)
                            .foregroundColor(.primary)
                        
                        Text("Great job staying consistent.")
                            .appFont(size: 16)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)

                    if let analytics = analytics {
                        // 2. Key Stats Grid (Bento Box Style)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            StatCard(title: "Total Volume", value: "\(Int(analytics.totalVolume))", unit: "lbs", icon: "dumbbell.fill", color: .blue)
                            StatCard(title: "PRs Set", value: "\(analytics.personalRecords.count)", unit: "records", icon: "star.fill", color: .yellow)
                            // You can add Duration or Calories here if you pass them into the struct later
                        }
                        .padding(.horizontal)

                        // 3. Personal Records Section (if any)
                        if !analytics.personalRecords.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "rosette")
                                        .foregroundColor(.purple)
                                    Text("New Personal Records")
                                        .appFont(size: 20, weight: .bold)
                                }
                                .padding(.horizontal)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(analytics.personalRecords.sorted(by: <), id: \.key) { key, value in
                                            PRCard(exerciseName: key, detail: value)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // 4. AI Insights Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.brandPrimary)
                                Text("Maia's Analysis")
                                    .appFont(size: 20, weight: .bold)
                            }
                            .padding(.horizontal)
                            
                            ForEach(analytics.aiInsights) { insight in
                                InsightCard(insight: insight)
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        // Loading State
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Crunching the numbers...")
                                .appFont(size: 16)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 300)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationBarHidden(true)
            .overlay(
                // Floating Done Button
                Button(action: { dismiss() }) {
                    Text("Done")
                        .appFont(size: 18, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.brandPrimary)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(radius: 5)
                }
                .padding()
                , alignment: .bottom
            )
            .onAppear {
                isAnimated = true
            }
        }
    }
}

// MARK: - Subviews

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .appFont(size: 24, weight: .bold)
                Text(unit)
                    .appFont(size: 12)
                    .foregroundColor(.secondary)
            }
            
            Text(title)
                .appFont(size: 14, weight: .medium)
                .foregroundColor(.secondary)
                .opacity(0.8)
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
    }
}

struct PRCard: View {
    let exerciseName: String
    let detail: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
                Spacer()
            }
            
            Text(exerciseName)
                .appFont(size: 16, weight: .bold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Text(detail)
                .appFont(size: 14)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 160, height: 140)
        .background(Color.backgroundSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 2)
        )
        .cornerRadius(16)
    }
}

struct InsightCard: View {
    let insight: WorkoutAnalysisInsight
    
    var categoryIcon: String {
        switch insight.category {
        case "Performance": return "chart.bar.fill"
        case "Recovery": return "bed.double.fill"
        case "Nutrition": return "fork.knife"
        default: return "lightbulb.fill"
        }
    }
    
    var categoryColor: Color {
        switch insight.category {
        case "Performance": return .blue
        case "Recovery": return .indigo
        case "Nutrition": return .green
        default: return .orange
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: categoryIcon)
                    .foregroundColor(categoryColor)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .appFont(size: 16, weight: .bold)
                
                Text(insight.message)
                    .appFont(size: 14)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(16)
    }
}
