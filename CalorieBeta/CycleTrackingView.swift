import SwiftUI

struct CycleTrackingView: View {
    @EnvironmentObject var cycleService: CycleTrackingService
    @State private var showingCycleSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let cycleDay = cycleService.cycleDay {
                    CyclePhaseRingView(cycleDay: cycleDay)
                        .padding(.vertical)

                    Menu {
                        Button("Log Period Start") {
                            cycleService.logPeriodStart()
                        }
                        Button("Cycle Settings") {
                            showingCycleSettings = true
                        }
                        Button("Clear Last Period Start", role: .destructive) {
                            cycleService.clearLastPeriodStart()
                        }
                    } label: {
                        Label("Cycle Options", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if cycleService.isLoadingInsight {
                        ProgressView("Loading AI Insights...")
                            .padding()
                            .frame(minHeight: 300)
                    } else if let insight = cycleService.aiInsight {
                        CyclePhaseDescriptionView(insight: insight)
                        CycleInsightCard(insight: insight)
                    }

                } else {
                    VStack(spacing: 16) {
                        Text("No period start date has been logged.")
                            .appFont(size: 17)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        
                        Button("Log Period Start") {
                            cycleService.logPeriodStart()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        
                        Button("Open Settings") {
                            showingCycleSettings = true
                        }
                    }
                    .padding(.top, 50)
                }
            }
            .padding()
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Cycle Phase")
        .onAppear {
            cycleService.fetchAIInsight()
        }
        .sheet(isPresented: $showingCycleSettings) {
            NavigationView {
                CycleSettingsView(cycleSettings: $cycleService.cycleSettings)
                    .navigationBarItems(trailing: Button("Done") {
                        showingCycleSettings = false
                    })
            }
        }
    }
}

struct CyclePhaseRingView: View {
    let cycleDay: CycleDay
    
    private let phaseColors: [MenstrualPhase: Color] = [
        .menstrual: .red.opacity(0.6),
        .follicular: .green.opacity(0.6),
        .ovulatory: .blue.opacity(0.6),
        .luteal: .orange.opacity(0.6)
    ]

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 30)

                Circle()
                    .trim(from: 0, to: CGFloat(cycleDay.cycleDayNumber) / 28.0)
                    .stroke(phaseColors[cycleDay.phase, default: .gray], style: StrokeStyle(lineWidth: 30, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: cycleDay.cycleDayNumber)

                VStack {
                    Text(cycleDay.phase.rawValue.capitalized)
                        .appFont(size: 34, weight: .bold)
                    Text("Day \(cycleDay.cycleDayNumber)")
                        .appFont(size: 18)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 220, height: 220)
            .padding(.bottom)

            HStack(spacing: 20) {
                ForEach(MenstrualPhase.allCases) { phase in
                    HStack {
                        Circle()
                            .fill(phaseColors[phase, default: .gray])
                            .frame(width: 12, height: 12)
                        Text(phase.rawValue.capitalized)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

struct CyclePhaseDescriptionView: View {
    let insight: AIInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.phaseTitle)
                .appFont(size: 22, weight: .bold)
                .foregroundColor(.brandPrimary)
            
            Text(insight.phaseDescription)
                .appFont(size: 15)
        }
        .padding()
        .background(Color.backgroundSecondary)
        .cornerRadius(15)
    }
}
