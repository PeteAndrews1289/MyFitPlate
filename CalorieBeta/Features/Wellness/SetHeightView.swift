import SwiftUI

struct SetHeightView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @AppStorage("useMetricBodyUnits") private var useMetric: Bool = Locale.current.measurementSystem != .us
    @Binding var feetInput: String
    @Binding var inchesInput: String
    @State private var cmInput: String = ""
    var onSave: () -> Void

    var body: some View {
        ZStack {
            AnimatedBackgroundView()
            
            VStack(spacing: 24) {
                // Header Graphic
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "ruler.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.blue)
                        .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
                        .rotationEffect(.degrees(45))
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Your Height")
                        .appFont(size: 28, weight: .bold)
                        .foregroundColor(.textPrimary)
                    
                    Text("Accurate height data helps Maia estimate your metabolic rate.")
                        .appFont(size: 15)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Inputs
                Group {
                    if useMetric {
                        HeightInputCard(title: "Height", value: $cmInput, unit: "cm")
                    } else {
                        HStack(spacing: 16) {
                            HeightInputCard(title: "Feet", value: $feetInput, unit: "ft")
                            HeightInputCard(title: "Inches", value: $inchesInput, unit: "in")
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .onAppear {
                    if useMetric { cmInput = String(Int(goalSettings.height.rounded())) }
                }

                Spacer()

                Button(action: {
                    if useMetric, let cm = Double(cmInput), cm > 0 {
                        let totalInches = Int((cm / BodyUnits.cmPerInch).rounded())
                        feetInput = String(totalInches / 12)
                        inchesInput = String(totalInches % 12)
                    }
                    self.onSave()
                }) {
                    Text("Save Height")
                        .appFont(size: 17, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
        }
    }
}

private struct HeightInputCard: View {
    let title: String
    @Binding var value: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .appFont(size: 13, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
            
            HStack(alignment: .bottom, spacing: 4) {
                TextField("0", text: $value)
                    .keyboardType(.numberPad)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, -6)
                
                Text(unit)
                    .appFont(size: 16, weight: .bold)
                    .foregroundColor(.blue)
                    .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}
