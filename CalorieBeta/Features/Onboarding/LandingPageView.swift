import SwiftUI

struct LandingPageView: View {
    @EnvironmentObject var appState: AppState
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("mfp logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)

                Text("MyFitPlate")
                    .appFont(size: 34, weight: .bold)
                    .foregroundColor(.textPrimary)

                if let error = errorMessage {
                    Text(error)
                        .appFont(size: 13)
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(14)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button("Retry") {
                        loadData()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    ProgressView()
                        .tint(.blue)
                        .scaleEffect(1.2)
                }
            }
            .padding(24)
        }
        .onAppear {
            loadData()
        }
    }

    private func loadData() {
        guard DIContainer.shared.authService.currentUserID != nil else {
            errorMessage = "User not authenticated. Please log in."
            return
        }
    }
}
