
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
        FeatureInfo(iconName: "fork.knife.circle.fill", title: "Effortless Logging", description: "Quickly log meals by searching our database, scanning a barcode, or describing your meal to Maia, your AI assistant.", color: .blue),
        FeatureInfo(iconName: "photo.fill.on.rectangle.fill", title: "Advanced Tools", description: "Use our AI-powered Recipe Importer to grab recipes from websites, or snap a picture to identify food with your camera.", color: .purple),
        FeatureInfo(iconName: "chart.bar.xaxis", title: "Detailed Tracking", description: "Go beyond calories. Monitor macros, micronutrients, water intake, and weight progress with detailed charts and reports.", color: .green),
        FeatureInfo(iconName: "flame.fill", title: "Stay Motivated", description: "Unlock achievements, complete weekly challenges, and level up as you build consistent, healthy habits.", color: .orange),
        FeatureInfo(iconName: "calendar", title: "Plan Ahead", description: "Let our Meal Plan Generator create a custom 7-day plan based on your goals and food preferences, complete with a grocery list.", color: .teal)
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

            Button(action: {
                if selection == features.count - 1 {
                    isPresented = false
                } else {
                    withAnimation {
                        selection += 1
                    }
                }
            }) {
                Text(selection == features.count - 1 ? "Get Started" : "Next")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
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
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(feature.description)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 20)
    }
}
