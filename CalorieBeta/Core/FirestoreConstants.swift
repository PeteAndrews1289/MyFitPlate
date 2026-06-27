import Foundation

enum FirestoreCollection {
    static let users = "users"
    static let posts = "posts"
    static let groups = "groups"
    static let groupMemberships = "groupMemberships"
    
    // User Sub-Collections
    static let dailyLogs = "dailyLogs"
    static let weightHistory = "weightHistory"
    static let calorieHistory = "calorieHistory"
    static let achievementStatus = "achievementStatus"
    static let activeChallenges = "activeChallenges"
    static let recipes = "recipes"
    static let pantryItems = "pantryItems"
    static let mealPlans = "mealPlans"
    static let userSettings = "userSettings"
    static let workoutSessionLogs = "workoutSessionLogs"
    static let workoutRoutines = "workoutRoutines"
    static let workoutPrograms = "workoutPrograms"
    static let dailySummaries = "dailySummaries"
}

enum FirestoreDocument {
    static let groceryList = "groceryList"
}
