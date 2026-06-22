import SwiftUI

struct MealPrepCookingView: View {
    @StateObject private var mealPrepService = MealPrepService()
    let days: [MealPlanDay]
    
    @State private var keepScreenOn: Bool = true
    @State private var selectedTab: Int = 0 // 0 for Ingredients, 1 for Steps
    
    // Timer state
    @State private var timerDuration: TimeInterval = 0
    @State private var timerRemaining: TimeInterval = 0
    @State private var isTimerRunning = false
    @State private var showTimerSheet = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Prep Mode", selection: $selectedTab) {
                    Text("Bulk Ingredients").tag(0)
                    Text("Prep Steps").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if selectedTab == 0 {
                    ingredientsView
                } else {
                    stepsView
                }
            }
            .navigationTitle("Meal Prep Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        keepScreenOn.toggle()
                        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
                    }) {
                        Image(systemName: keepScreenOn ? "lightbulb.fill" : "lightbulb.slash")
                            .foregroundColor(keepScreenOn ? .yellow : .gray)
                    }
                }
            }
            .onAppear {
                mealPrepService.aggregate(days: days)
                UIApplication.shared.isIdleTimerDisabled = keepScreenOn
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .overlay(alignment: .bottomTrailing) {
                if isTimerRunning || timerRemaining > 0 {
                    timerOverlay
                        .padding()
                } else {
                    Button(action: { showTimerSheet = true }) {
                        Image(systemName: "timer")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.brandPrimary)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding()
                }
            }
            .sheet(isPresented: $showTimerSheet) {
                TimerSetupView(duration: $timerDuration) {
                    timerRemaining = timerDuration
                    isTimerRunning = true
                    showTimerSheet = false
                }
            }
        }
        .onReceive(timer) { _ in
            if isTimerRunning && timerRemaining > 0 {
                timerRemaining -= 1
            } else if isTimerRunning && timerRemaining == 0 {
                isTimerRunning = false
                HapticFeedback.success()
                // You could play a sound here
            }
        }
    }
    
    private var ingredientsView: some View {
        List {
            ForEach(Array(mealPrepService.bulkIngredients.keys.sorted()), id: \.self) { category in
                Section(header: Text(category)) {
                    if let items = mealPrepService.bulkIngredients[category] {
                        ForEach(items) { item in
                            HStack {
                                Text(item.name)
                                    .font(.body)
                                Spacer()
                                Text("\(formatQuantity(item.quantity)) \(item.unit == "item" ? "" : item.unit)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var stepsView: some View {
        List {
            ForEach(mealPrepService.prepSteps.indices, id: \.self) { index in
                let stepInfo = mealPrepService.prepSteps[index]
                VStack(alignment: .leading, spacing: 6) {
                    Text(stepInfo.recipeName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.brandPrimary)
                    
                    Text(stepInfo.step)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
        }
        .listStyle(.plain)
    }
    
    private var timerOverlay: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Timer")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                Text(timeString(from: timerRemaining))
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Button(action: {
                if timerRemaining > 0 {
                    isTimerRunning.toggle()
                } else {
                    timerRemaining = 0
                }
            }) {
                Image(systemName: isTimerRunning ? "pause.fill" : (timerRemaining > 0 ? "play.fill" : "xmark"))
                    .foregroundColor(.white)
            }
            if !isTimerRunning && timerRemaining > 0 {
                Button(action: {
                    timerRemaining = 0
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.75))
        .cornerRadius(12)
        .frame(width: 200)
    }
    
    private func formatQuantity(_ q: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: q)) ?? "\(q)"
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct TimerSetupView: View {
    @Binding var duration: TimeInterval
    var onStart: () -> Void
    
    @State private var minutes: Int = 10
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Set Timer")) {
                    Stepper("\(minutes) minutes", value: $minutes, in: 1...120)
                }
                
                Button(action: {
                    duration = TimeInterval(minutes * 60)
                    onStart()
                }) {
                    Text("Start Timer")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.brandPrimary)
                        .cornerRadius(8)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .navigationTitle("Cooking Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
