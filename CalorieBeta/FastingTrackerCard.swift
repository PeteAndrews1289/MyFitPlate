import SwiftUI

struct FastingTrackerCard: View {
    @ObservedObject var fastingManager = FastingManager.shared
    
    // Some pre-defined fasts
    let fastOptions = [12, 14, 16, 18, 20]
    @State private var selectedFastDuration = 16
    @State private var showingOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("Intermittent Fasting")
                    .font(.headline)
                Spacer()
                if fastingManager.isFasting {
                    Text(fastingManager.fastType)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Button(action: { showingOptions.toggle() }) {
                        Text("\(selectedFastDuration)h Fast")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    .confirmationDialog("Select Fast Duration", isPresented: $showingOptions, titleVisibility: .visible) {
                        ForEach(fastOptions, id: \.self) { hours in
                            Button("\(hours) hours") {
                                selectedFastDuration = hours
                            }
                        }
                    }
                }
            }

            if fastingManager.isFasting, let targetTime = fastingManager.currentFastTargetEndTime {
                // Currently Fasting UI
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text("Remaining")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(timerInterval: Date()...targetTime, countsDown: true)
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    Button(action: {
                        fastingManager.endFast()
                    }) {
                        Text("End Fast")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                }
            } else {
                // Not Fasting UI
                HStack {
                    Text("Ready to start your fast?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        fastingManager.startFast(hours: selectedFastDuration)
                    }) {
                        Text("Start Fast")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

#Preview {
    FastingTrackerCard()
        .padding()
}
