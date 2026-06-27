import SwiftUI

struct FeatureTourView: View {
    @Binding var isPresented: Bool
    @State private var selection = 0

    private struct FeatureInfo {
        let iconName: String
        let title: String
        let description: String
        let color: Color
    }

    private let features: [FeatureInfo] = [
        // Slide 1: Core AI Value Prop
        FeatureInfo(
            iconName: "sparkles",
            title: "Meet Maia",
            description: "Your personal AI nutrition coach. Ask her anything, log food by chatting, or get smart suggestions for your next meal.",
            color: .brandPrimary
        ),
        // Slide 2: Vision & Logging
        FeatureInfo(
            iconName: "camera.viewfinder",
            title: "Snap & Log",
            description: "No more searching. Just snap a photo of your meal or a nutrition label, and our AI will estimate the calories and macros for you.",
            color: .accentCarbs
        ),
        // Slide 3: Fitness & Live Activities
        FeatureInfo(
            iconName: "dumbbell.fill",
            title: "Smart Training",
            description: "Generate custom workout plans with AI, track your sets, and see your rest timers right on your Lock Screen.",
            color: .blue
        ),
        // Slide 4: Wellness Score (Unique Selling Point)
        FeatureInfo(
            iconName: "heart.text.square.fill",
            title: "Daily Wellness",
            description: "We combine your Nutrition, Sleep, and Recovery data into a single 'Wellness Score' to help you balance effort with rest.",
            color: .accentPositive
        ),
        // Slide 5: Planning
        FeatureInfo(
            iconName: "calendar.badge.clock",
            title: "Plan Ahead",
            description: "Generate full 7-day meal plans and grocery lists in seconds based on your specific goals and taste preferences.",
            color: .orange
        )
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            TabView(selection: $selection) {
                ForEach(features.indices, id: \.self) { index in
                    featureCard(for: features[index]).tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))

            Spacer()

            Button(selection == features.count - 1 ? "Get Started" : "Next") {
                if selection == features.count - 1 {
                    isPresented = false
                } else {
                    withAnimation {
                        selection += 1
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 30)
            .padding(.bottom, 40)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
    }

    @ViewBuilder
    private func featureCard(for feature: FeatureInfo) -> some View {
        VStack(spacing: 25) {
            Spacer()
            Image(systemName: feature.iconName)
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(feature.color)
                .padding()
                .background(
                    Circle()
                        .fill(feature.color.opacity(0.1))
                        .frame(width: 160, height: 160)
                )
            
            Text(feature.title)
                .appFont(size: 32, weight: .bold)
                .multilineTextAlignment(.center)
            
            Text(feature.description)
                .appFont(size: 17, weight: .regular)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(4)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
