import Foundation

public struct OnboardingQuizProgress: Codable, Equatable {
    public var step: Int
    public var answers: [String: String]
    public var metric: Bool
    public init(step: Int, answers: [String: String], metric: Bool) {
        self.step = step
        self.answers = answers
        self.metric = metric
    }
}

public struct OnboardingQuizProgressStore {
    private struct Saved: Codable { let progress: OnboardingQuizProgress; let date: Date }
    private let defaults: UserDefaults
    private let key: String
    public init(userID: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = AccountScopedStorageKey.make(prefix: "onboarding_quiz", userID: userID) ?? "onboarding_quiz_before_account"
    }
    public func save(_ progress: OnboardingQuizProgress, now: Date = Date()) {
        guard let data = try? JSONEncoder().encode(Saved(progress: progress, date: now)) else { return }
        defaults.set(data, forKey: key)
    }
    public func load(now: Date = Date()) -> OnboardingQuizProgress? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data),
              now.timeIntervalSince(saved.date) >= 0,
              now.timeIntervalSince(saved.date) <= OnboardingDraftStore.draftLifetime else {
            clear()
            return nil
        }
        return saved.progress
    }
    public func clear() { defaults.removeObject(forKey: key) }
}
