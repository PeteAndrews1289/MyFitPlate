import SwiftUI

struct SetWaterGoalView: View {
    @EnvironmentObject var goalSettings: GoalSettings
    @Binding var waterGoalInput: String
    var onSave: () -> Void

    let presetGoals = [64, 80, 100, 128]

    var body: some View {
        ZStack {
            AnimatedBackgroundView()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor.secondarySystemFill))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "drop.fill")
                        .appFont(size: 44, weight: .bold)
                        .foregroundColor(.cyan)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Daily water goal")
                        .appFont(size: 21, weight: .bold)
                        .foregroundColor(.textPrimary)
                    
                    Text("Set your daily hydration target to feel your best.")
                        .appFont(size: 15)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("0", text: $waterGoalInput)
                        .keyboardType(.numberPad)
                        .appFont(size: 54, weight: .bold)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(width: 120)
                        .padding(.bottom, -8)

                    Text("oz")
                        .appFont(size: 20, weight: .bold)
                        .foregroundColor(.cyan)
                        .padding(.bottom, 6)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick select")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                        .padding(.horizontal, 32)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(presetGoals, id: \.self) { preset in
                                Button(action: {
                                    withAnimation {
                                        waterGoalInput = "\(preset)"
                                    }
                                }) {
                                    Text("\(preset.formatted()) oz")
                                        .appFont(size: 15, weight: .semibold)
                                        .foregroundColor(waterGoalInput == "\(preset)" ? .white : .cyan)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 20)
                                        .background(
                                            waterGoalInput == "\(preset)" ? Color.cyan : Color.cyan.opacity(0.15),
                                            in: Capsule()
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                }
                .padding(.top, 8)

                Spacer()

                Button(action: {
                    self.onSave()
                }) {
                    Text("Save goal")
                        .appFont(size: 17, weight: .bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
        }
    }
}
