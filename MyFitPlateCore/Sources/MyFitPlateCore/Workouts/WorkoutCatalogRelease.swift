import Foundation

public struct WorkoutCatalogRelease: Codable, Equatable, Sendable {
    public var templateID: String
    public var version: Int
    public var source: String
    public var fidelity: String
    public var goal: String
    public var experience: String
    public var equipment: String
    public var weekCount: Int
    public var supportedPolicy: WorkoutProgressionPolicy.Kind
    public var tags: [String]

    public static func profile(templateID: String) -> WorkoutCatalogRelease? {
        // Explicit catalog contract. Display names never determine the training behavior.
        let data: [String: (String, String, String, [String])] = [
            "stronglifts_5x5": ("Strength", "Beginner", "Barbell + bench + rack", ["Strength", "Barbell"]),
            "beginner_bodyweight": ("Strength", "Beginner", "Bodyweight + pull-up/dip supports", ["Full Body", "Bodyweight"]),
            "dumbbell_hypertrophy_4_day": ("Muscle", "Intermediate", "Dumbbell + bench", ["Hypertrophy", "Dumbbell"]),
            "mobility_core_reset": ("Recovery", "All Levels", "Minimal Equipment", ["Mobility", "Recovery"]),
            "phat": ("Muscle", "Advanced", "Barbell + dumbbell + machines", ["Hypertrophy", "Strength"]),
            "basic_beginner_strength": ("Strength", "Beginner", "Barbell + rack + bench + pull-up support", ["Strength", "Full Body"]),
            "gzclp": ("Strength", "Beginner", "Barbell + dumbbell + cable", ["Strength", "Barbell"]),
            "531_for_beginners": ("Strength", "Beginner", "Barbell + bench + machines", ["Strength", "Barbell"]),
            "531_boring_but_big": ("Muscle", "Intermediate", "Barbell + bench + machines", ["Strength", "Hypertrophy"]),
            "phul": ("Muscle", "Intermediate", "Barbell + dumbbell + machines", ["Strength", "Hypertrophy"]),
            "beginner_ppl": ("Muscle", "Beginner", "Barbell + dumbbell + machines", ["Hypertrophy", "Strength"]),
            "bodyweight_foundation": ("Strength", "Beginner", "Bodyweight + pull-up/dip supports", ["Full Body", "Bodyweight"]),
            "machine_gym_full_body": ("Muscle", "Beginner", "Machines + cable", ["Machines", "Full Body"]),
            "machine_gym_ppl": ("Muscle", "Intermediate", "Machines + cable", ["Machines", "Hypertrophy"]),
            "athletic_strength_builder": ("Strength", "Intermediate", "Barbell + dumbbell + supports", ["Strength", "Conditioning"]),
            "german_volume_training": ("Muscle", "Advanced", "Barbell + dumbbell + machines", ["Hypertrophy", "Barbell"]),
            "monolith_strength_size": ("Muscle", "Advanced", "Barbell + dumbbell + machines", ["Strength", "Hypertrophy"]),
            "glute_lower_growth": ("Muscle", "Intermediate", "Barbell + dumbbell + machines", ["Hypertrophy", "Lower Body"]),
            "busy_professional_strength": ("Strength", "Beginner", "Barbell + dumbbell + bench", ["Strength", "Full Body"]),
            "rotating_upper_lower_3_day": ("Muscle", "Intermediate", "Barbell + dumbbell + machines", ["Hypertrophy", "Strength"]),
            "fat_loss_strength_conditioning": ("Conditioning", "Intermediate", "Dumbbell + machines", ["Conditioning", "Strength"]),
            "beginner_dumbbell_only": ("Strength", "Beginner", "Dumbbell + bench", ["Dumbbell", "Full Body"]),
            "kettlebell_bodyweight_conditioning": ("Conditioning", "Intermediate", "Kettlebell + floor", ["Conditioning", "Full Body"]),
            "mobility_zone2_base": ("Recovery", "All Levels", "Minimal Equipment", ["Mobility", "Low Impact"]),
            "return_to_training_ramp": ("Recovery", "Beginner", "Dumbbell + machines", ["Recovery", "Full Body"]),
            "powerbuilding_4_day": ("Muscle", "Intermediate", "Barbell + dumbbell + machines", ["Strength", "Hypertrophy"]),
            "minimalist_garage_gym": ("Strength", "Intermediate", "Barbell + rack + bench + pull-up support", ["Barbell", "Strength"])
        ]
        guard let values = data[templateID.replacingOccurrences(of: "prebuilt_", with: "")] else { return nil }
        return WorkoutCatalogRelease(templateID: templateID, version: 2, source: "MyFitPlate curated adaptation",
            fidelity: "An adapted exercise split with explicit set targets and conservative progression. It does not claim the complete original named method or endorsement. Review starting loads and equipment before adoption.",
            goal: values.0, experience: values.1, equipment: values.2, weekCount: 12,
            supportedPolicy: .conservativeDouble, tags: values.3)
    }
}
