import Foundation

public enum FirestoreCollection {
    public static let users = "users"
    public static let posts = "posts"
    public static let groups = "groups"
    public static let groupMemberships = "groupMemberships"
    
    // User Sub-Collections
    public static let dailyLogs = "dailyLogs"
    public static let weightHistory = "weightHistory"
    public static let calorieHistory = "calorieHistory"
    public static let achievementStatus = "achievementStatus"
    public static let activeChallenges = "activeChallenges"
    public static let recipes = "recipes"
    public static let pantryItems = "pantryItems"
    public static let mealPlans = "mealPlans"
    public static let userSettings = "userSettings"
    public static let workoutSessionLogs = "workoutSessionLogs"
    public static let workoutRoutines = "workoutRoutines"
    public static let workoutPrograms = "workoutPrograms"
    public static let dailySummaries = "dailySummaries"
}

public enum FirestoreDocument {
    public static let groceryList = "groceryList"
}
