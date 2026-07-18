//
//  MyFitPlateTests.swift
//  MyFitPlateTests
//
//  Created by Peter Andrews on 6/20/26.
//

import XCTest
@testable import MyFitPlate

@MainActor
final class AIChatbotAccountIsolationTests: XCTestCase {
    func testResponseFromPreviousAccountCannotEnterNextAccountsChat() async {
        let authService = MockAuthService()
        authService.currentUserID = "maia-account-a"
        let aiService = MockAIService()
        aiService.mockResult = .success("Private response for account A")
        aiService.responseDelayNanoseconds = 100_000_000
        DIContainer.shared.authService = authService
        DIContainer.shared.aiService = aiService
        DIContainer.shared.analyticsManager = MockAnalyticsManager()

        let viewModel = AIChatbotViewModel()
        viewModel.setupView()
        viewModel.userMessage = "Private question from account A"
        viewModel.sendMessage()

        authService.currentUserID = "maia-account-b"
        viewModel.setupView()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.chatMessages.contains { $0.text.contains("account A") })
    }
}
