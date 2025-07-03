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
        FeatureInfo(iconName: "fork.knife.circle.fill", title: "Effortless Logging", description: "Quickly log meals by searching our database, scanning a barcode, or describing your meal to Maia, your AI assistant.", color: .brandPrimary),
        FeatureInfo(iconName: "photo.fill.on.rectangle.fill", title: "Advanced Tools", description: "Use our AI-powered Recipe Importer to grab recipes from websites, or snap a picture to identify food with your camera.", color: .accentFats),
        FeatureInfo(iconName: "chart.bar.xaxis", title: "Detailed Tracking", description: "Go beyond calories. Monitor macros, micronutrients, water intake, and weight progress with detailed charts and reports.", color: .accentPositive),
        FeatureInfo(iconName: "flame.fill", title: "Stay Motivated", description: "Unlock achievements, complete weekly challenges, and level up as you build consistent, healthy habits.", color: .accentCarbs),
        FeatureInfo(iconName: "calendar", title: "Plan Ahead", description: "Let our Meal Plan Generator create a custom 7-day plan based on your goals and food preferences, complete with a grocery list.", color: .brandSecondary)
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
    }

    @ViewBuilder
    private func featureCard(for feature: FeatureInfo) -> some View {
        VStack(spacing: 25) {
            Image(systemName: feature.iconName)
                .font(.system(size: 80, weight: .bold))
                .foregroundColor(feature.color)
            
            Text(feature.title)
                .appFont(size: 34, weight: .bold)
            
            Text(feature.description)
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 20)
    }
}
