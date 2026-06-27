import SwiftUI

struct AIChatbotView: View {
    @Binding var selectedTab: Int
    var chatContext: String?

    @StateObject private var viewModel = AIChatbotViewModel()

    var bgGreen = Color(red: 16/255, green: 20/255, blue: 21/255)

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var goalSettings: GoalSettings
    @EnvironmentObject var dailyLogService: DailyLogService
    @EnvironmentObject var achievementService: AchievementService
    @EnvironmentObject var mealPlannerService: MealPlannerService
    @EnvironmentObject var healthKitViewModel: HealthKitViewModel

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var ttsManager = TTSManager.shared

    private var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    private var starterSuggestions: [String] {
        var suggestions: [String] = []

        if dailyLogService.currentDailyLog?.calorieConsistencyStatus().hasMeaningfulMismatch == true {
            suggestions.append("Audit today's calorie and macro mismatch.")
        }

        if viewModel.remainingProtein >= 15 {
            suggestions.append("Help me hit \(Int(viewModel.remainingProtein.rounded()))g more protein.")
        }

        if viewModel.workoutCount > 0 {
            suggestions.append("What should I eat after today's workout?")
        }

        if viewModel.mealCount == 0 {
            suggestions.append("Build my first meal for today.")
        } else {
            suggestions.append("What should I eat with \(Int(viewModel.remainingCalories.rounded())) calories left?")
        }

        suggestions.append("Give me a simple dinner idea.")
        suggestions.append("Log 1 apple and a handful of almonds.")

        return Array(suggestions.prefix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.chatMessages.count <= 1 {
                MaiaBriefingCard(
                    calories: viewModel.remainingCalories,
                    protein: viewModel.remainingProtein,
                    carbs: viewModel.remainingCarbs,
                    fats: viewModel.remainingFats,
                    water: viewModel.waterOunces,
                    waterGoal: viewModel.waterGoal,
                    mealCount: viewModel.mealCount,
                    workoutCount: viewModel.workoutCount
                )
                .padding(.horizontal)
                .padding(.top, 10)

                if healthKitViewModel.isAuthorized {
                    MaiaHealthKitContextIndicator(
                        steps: healthKitViewModel.todaySteps,
                        activeEnergy: healthKitViewModel.todayActiveEnergy,
                        sleepSummary: healthKitViewModel.sleepSummary
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }

            ChatHistoryListView(
                chatMessages: $viewModel.chatMessages,
                onLogRecipe: { viewModel.logRecipe(recipeText: $0) },
                onSpeak: ttsManager.speak,
                onAction: { viewModel.handleMaiaAction($0) },
                showAlert: $viewModel.showAlert,
                alertMessage: $viewModel.alertMessage
            )
            .onTapGesture { hideKeyboard() }

            VStack(spacing: 0) {
                if viewModel.chatMessages.count <= 1 && !viewModel.isLoading {
                    SuggestionButtonsView(suggestions: starterSuggestions) { prompt in
                        viewModel.userMessage = prompt
                        viewModel.sendMessage()
                    }
                    .padding(.vertical, 10)
                }

                if viewModel.isLoading {
                    HStack(alignment: .bottom, spacing: 10) {
                        Image("maia_avatar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            .clipShape(Circle())
                            .background(Color.backgroundSecondary, in: Circle())
                        
                        MaiaTypingIndicator()
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                HStack(spacing: 10) {
                    TextField("Ask Maia anything...", text: $viewModel.userMessage, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.backgroundPrimary.opacity(colorScheme == .dark ? 0.62 : 0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .lineLimit(1...4)
                        .onSubmit { viewModel.sendMessage() }

                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up")
                            .appFont(size: 16, weight: .bold)
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(
                                viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading
                                ? Color(UIColor.tertiaryLabel)
                                : Color.brandPrimary,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.userMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, bottomSafeAreaInset)
            }
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(
                        Rectangle().frame(height: 1).foregroundColor(Color.primary.opacity(0.05)),
                        alignment: .top
                    )
            )
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Maia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.showingClearChatConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.chatMessages.count <= 1)
            }
        }
        .onAppear {
            viewModel.chatContext = self.chatContext
            viewModel.dailyLogService = self.dailyLogService
            viewModel.goalSettings = self.goalSettings
            viewModel.achievementService = self.achievementService
            viewModel.mealPlannerService = self.mealPlannerService
            viewModel.healthKitViewModel = self.healthKitViewModel
            viewModel.setupView()
        }
        .onDisappear {
            viewModel.saveMessages()
        }
        .onReceive(appState.$pendingChatPrompt) { prompt in
            if let prompt = prompt {
                viewModel.userMessage = prompt
                viewModel.sendMessage()
                appState.pendingChatPrompt = nil
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(title: Text("Notification"), message: Text(viewModel.alertMessage), dismissButton: .default(Text("OK")))
        }
        .confirmationDialog("Clear Maia chat?", isPresented: $viewModel.showingClearChatConfirmation, titleVisibility: .visible) {
            Button("Clear Chat", role: .destructive) { viewModel.clearChat() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved conversation history on this device.")
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
