import SwiftUI
import FirebaseAuth

struct AITextLogView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var mealDescription = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var estimatedItems: [FoodItem]?
    @State private var showResults = false
    
    private let textLogService = AITextLogService()

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "text.bubble.fill")
                                    .appFont(size: 18, weight: .bold)
                                    .foregroundColor(.brandPrimary)
                                    .frame(width: 42, height: 42)
                                    .background(Color.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Describe Your Meal")
                                        .appFont(size: 25, weight: .bold)
                                        .foregroundColor(.textPrimary)

                                    Text("Maia will estimate nutrition from plain language.")
                                        .appFont(size: 13)
                                        .foregroundColor(Color(UIColor.secondaryLabel))
                                }
                            }
                        }
                        .asCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Meal Description")
                                .appFont(size: 17, weight: .bold)
                                .foregroundColor(.textPrimary)

                            TextEditor(text: $mealDescription)
                                .padding(12)
                                .frame(minHeight: 170)
                                .scrollContentBackground(.hidden)
                                .background(Color.backgroundSecondary.opacity(0.74), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )

                            if mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Example: A bowl of oatmeal with blueberries, peanut butter, and a coffee.")
                                    .appFont(size: 13)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                        }
                        .asCard()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Good details help")
                                .appFont(size: 17, weight: .bold)
                                .foregroundColor(.textPrimary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                detailChip("portion")
                                detailChip("brand")
                                detailChip("sauce")
                                detailChip("cooking method")
                            }
                        }
                        .asCard()

                        if let error = errorMessage {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .appFont(size: 13)
                                    .foregroundColor(.textPrimary)
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        Button(action: analyzeText) {
                            Label("Analyze with Maia", systemImage: "sparkles")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isLoading || mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                }
                .navigationTitle("Describe Meal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .sheet(isPresented: $showResults) {
                    if let items = estimatedItems {
                        AITextResultsView(foodItems: .constant(items)) {
                            dismiss()
                        }
                    }
                }
                
                if isLoading {
                    Color.black.opacity(0.34).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.brandPrimary)
                        Text("Analyzing your meal...")
                            .appFont(size: 16, weight: .semibold)
                            .foregroundColor(.textPrimary)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }

    private func detailChip(_ text: String) -> some View {
        Text(text)
            .appFont(size: 12, weight: .semibold)
            .foregroundColor(.brandPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.brandPrimary.opacity(0.10), in: Capsule())
    }
    
    private func analyzeText() {
        isLoading = true
        errorMessage = nil
        
        Task {
            let result = await textLogService.estimateNutrition(from: mealDescription)
            isLoading = false
            
            switch result {
            case .success(let foodItems):
                self.estimatedItems = foodItems
                self.showResults = true
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
