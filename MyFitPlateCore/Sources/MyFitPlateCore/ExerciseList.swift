
import Foundation

public struct ExerciseList {

    /// One exercise: its display name, muscle-group category, and a concise how-to cue.
    /// This is the single source of truth — `categorizedExercises` and `instructions`
    /// are derived from it, so adding an exercise here surfaces it everywhere.
    public struct Entry: Identifiable, Hashable {
        public let name: String
        public let category: String
        public let howTo: String
        public var id: String { name }

        public init(name: String, category: String, howTo: String) {
            self.name = name
            self.category = category
            self.howTo = howTo
        }
    }

    public static let entries: [Entry] = [
        // MARK: Chest
        Entry(name: "Barbell Bench Press", category: "Chest", howTo: "Lie on a flat bench, lower the bar to mid-chest with elbows about 45°, then press back to lockout."),
        Entry(name: "Incline Barbell Bench Press", category: "Chest", howTo: "On a 30–45° incline, lower the bar to the upper chest and press up, keeping shoulder blades pinned."),
        Entry(name: "Decline Barbell Bench Press", category: "Chest", howTo: "On a decline bench, lower the bar to the lower chest and press up; emphasizes the lower pecs."),
        Entry(name: "Dumbbell Bench Press", category: "Chest", howTo: "Press two dumbbells from chest height to lockout, lowering until you feel a stretch across the chest."),
        Entry(name: "Incline Dumbbell Bench Press", category: "Chest", howTo: "On an incline, press dumbbells up and slightly together; lower under control to the upper chest."),
        Entry(name: "Decline Dumbbell Bench Press", category: "Chest", howTo: "On a decline, press dumbbells from the lower chest to lockout, keeping wrists stacked over elbows."),
        Entry(name: "Dumbbell Fly", category: "Chest", howTo: "With a slight elbow bend, open the dumbbells wide in an arc, feel the chest stretch, then hug them back together."),
        Entry(name: "Incline Dumbbell Fly", category: "Chest", howTo: "On an incline, arc the dumbbells out and back with soft elbows; squeeze the upper chest at the top."),
        Entry(name: "Cable Crossover", category: "Chest", howTo: "From high pulleys, sweep the handles down and together in front of you, squeezing the chest; return slowly."),
        Entry(name: "Chest Dip", category: "Chest", howTo: "Lean the torso forward on parallel bars, lower until you feel a chest stretch, then press back up."),
        Entry(name: "Push-up", category: "Chest", howTo: "In a plank, lower your chest to just above the floor with elbows ~45°, then push back to a straight-arm plank."),
        Entry(name: "Machine Chest Press", category: "Chest", howTo: "Set the seat so handles are at chest height; press forward to near lockout and return under control."),
        Entry(name: "Machine Fly (Pec Deck)", category: "Chest", howTo: "Bring the pads or handles together in front of your chest with soft elbows; squeeze, then open slowly."),

        // MARK: Back
        Entry(name: "Deadlift (Conventional)", category: "Back", howTo: "Grip the bar just outside the knees, brace, and drive the floor away — hips and shoulders rise together to lockout."),
        Entry(name: "Sumo Deadlift", category: "Back", howTo: "Take a wide stance with hands inside the knees; push the knees out and stand the bar up keeping it close."),
        Entry(name: "Romanian Deadlift", category: "Back", howTo: "With soft knees, hinge at the hips and slide the bar down the thighs until you feel a hamstring stretch, then stand tall."),
        Entry(name: "Pull-up", category: "Back", howTo: "Hang with an overhand grip; pull your chest toward the bar by driving elbows down, then lower fully."),
        Entry(name: "Chin-up", category: "Back", howTo: "With an underhand shoulder-width grip, pull until your chin clears the bar, then lower under control."),
        Entry(name: "Lat Pulldown", category: "Back", howTo: "Pull the bar to your upper chest by driving the elbows down and back; control the bar back up."),
        Entry(name: "Barbell Bent-over Row", category: "Back", howTo: "Hinge to ~45°, row the bar to your lower ribs/belly, squeeze the shoulder blades, then lower."),
        Entry(name: "Pendlay Row", category: "Back", howTo: "From a flat back, row the bar explosively from the floor to your lower chest, then reset it on the floor each rep."),
        Entry(name: "Dumbbell Row", category: "Back", howTo: "Brace a hand and knee on a bench; row the dumbbell to your hip, keeping the torso still."),
        Entry(name: "T-Bar Row", category: "Back", howTo: "Hinge over the bar and row the handles to your chest, driving the elbows back; lower under control."),
        Entry(name: "Seated Cable Row", category: "Back", howTo: "With a tall chest, pull the handle to your belly, squeezing the shoulder blades; extend the arms slowly."),
        Entry(name: "Face Pull", category: "Back", howTo: "From a high pulley with a rope, pull toward your face with elbows high, rotating hands back; squeeze rear delts."),
        Entry(name: "Good Mornings", category: "Back", howTo: "With the bar on your back and soft knees, hinge forward until your torso is near parallel, then stand tall."),
        Entry(name: "Back Extension (Hyperextension)", category: "Back", howTo: "Hinge over the pad, lower your torso, then raise it to a straight line by squeezing the glutes and lower back."),
        Entry(name: "Inverted Row", category: "Back", howTo: "Hang under a fixed bar with a straight body; pull your chest to the bar and lower with control."),

        // MARK: Shoulders
        Entry(name: "Barbell Overhead Press (Military Press)", category: "Shoulders", howTo: "From the front rack, brace and press the bar overhead to lockout, moving your head 'through' at the top."),
        Entry(name: "Dumbbell Shoulder Press", category: "Shoulders", howTo: "Press dumbbells from shoulder height to lockout overhead; lower under control to ear level."),
        Entry(name: "Arnold Press", category: "Shoulders", howTo: "Start palms facing you at chin height; rotate the palms forward as you press overhead, then reverse on the way down."),
        Entry(name: "Dumbbell Lateral Raise", category: "Shoulders", howTo: "With a slight elbow bend, raise the dumbbells out to shoulder height leading with the elbows; lower slowly."),
        Entry(name: "Cable Lateral Raise", category: "Shoulders", howTo: "From a low pulley, raise the handle out to the side to shoulder height; control the return for constant tension."),
        Entry(name: "Dumbbell Front Raise", category: "Shoulders", howTo: "Raise a dumbbell straight in front to shoulder height with a soft elbow, then lower under control."),
        Entry(name: "Barbell Shrug", category: "Shoulders", howTo: "Hold the bar at arm's length and shrug the shoulders straight up toward your ears; pause, then lower."),
        Entry(name: "Dumbbell Shrug", category: "Shoulders", howTo: "With dumbbells at your sides, elevate the shoulders straight up, squeeze the traps, and lower slowly."),
        Entry(name: "Dumbbell Rear Delt Fly", category: "Shoulders", howTo: "Hinge forward and raise the dumbbells out to the sides with soft elbows; squeeze the rear delts at the top."),
        Entry(name: "Upright Row", category: "Shoulders", howTo: "Pull the bar or dumbbells up the front of the body to chest height, leading with the elbows; lower under control."),

        // MARK: Biceps
        Entry(name: "Barbell Curl", category: "Biceps", howTo: "With elbows pinned to your sides, curl the bar to your shoulders, then lower slowly without swinging."),
        Entry(name: "Dumbbell Curl", category: "Biceps", howTo: "Curl the dumbbells up, supinating the wrists; squeeze the biceps at the top and lower under control."),
        Entry(name: "Hammer Curl", category: "Biceps", howTo: "Curl with palms facing each other (neutral grip); lower slowly to target the biceps and forearms."),
        Entry(name: "Preacher Curl", category: "Biceps", howTo: "Rest the arms on the preacher pad and curl the weight up; lower until the arms are nearly straight."),
        Entry(name: "Concentration Curl", category: "Biceps", howTo: "Seated with your elbow braced on your inner thigh, curl the dumbbell up and squeeze; lower fully."),
        Entry(name: "Incline Dumbbell Curl", category: "Biceps", howTo: "Lie back on an incline with arms hanging; curl the dumbbells up for a deep biceps stretch, then lower slowly."),
        Entry(name: "Cable Curl", category: "Biceps", howTo: "From a low pulley, curl the bar or handle up with elbows fixed; keep tension constant on the way down."),

        // MARK: Triceps
        Entry(name: "Close-Grip Bench Press", category: "Triceps", howTo: "Bench with hands shoulder-width; tuck the elbows and press, emphasizing the triceps at lockout."),
        Entry(name: "Triceps Dip", category: "Triceps", howTo: "On parallel bars with the torso upright, lower until elbows reach ~90°, then press back to lockout."),
        Entry(name: "Bench Dip", category: "Triceps", howTo: "Hands on a bench behind you, lower the hips by bending the elbows, then press back up."),
        Entry(name: "Skull Crusher (Lying Triceps Extension)", category: "Triceps", howTo: "Lying down, keep upper arms vertical and lower the bar toward your forehead, then extend to lockout."),
        Entry(name: "Triceps Pushdown (Cable)", category: "Triceps", howTo: "With elbows pinned to your sides, push the bar or rope down to full extension; control the return."),
        Entry(name: "Overhead Triceps Extension (Dumbbell/Cable)", category: "Triceps", howTo: "Keep the upper arms by your ears and extend the weight overhead, then lower behind the head for a stretch."),
        Entry(name: "Triceps Kickback", category: "Triceps", howTo: "Hinge forward, upper arm parallel to the floor; extend the forearm back to lockout and squeeze the triceps."),

        // MARK: Forearms
        Entry(name: "Wrist Curl", category: "Forearms", howTo: "Rest forearms on your thighs, palms up; curl the bar with the wrists only, then lower for a full stretch."),
        Entry(name: "Reverse Wrist Curl", category: "Forearms", howTo: "Forearms on thighs, palms down; raise the bar with the wrists to work the forearm extensors, then lower slowly."),
        Entry(name: "Reverse Barbell Curl", category: "Forearms", howTo: "Curl the bar with an overhand grip, elbows pinned; targets the forearms and brachialis."),
        Entry(name: "Farmer's Carry", category: "Forearms", howTo: "Hold heavy dumbbells at your sides and walk with a tall posture and braced core for distance or time."),
        Entry(name: "Plate Pinch", category: "Forearms", howTo: "Pinch two smooth plates together between thumb and fingers and hold for time to build grip strength."),

        // MARK: Legs (Quads / general)
        Entry(name: "Barbell Back Squat", category: "Legs", howTo: "Bar on the upper back, brace and sit down between your hips to at least parallel, then drive up through mid-foot."),
        Entry(name: "Barbell Front Squat", category: "Legs", howTo: "Bar in the front rack with high elbows; squat down keeping the torso upright, then stand tall."),
        Entry(name: "Goblet Squat (Dumbbell/Kettlebell)", category: "Legs", howTo: "Hold a weight at your chest; squat down between the knees keeping the chest up, then stand."),
        Entry(name: "Leg Press", category: "Legs", howTo: "Press the platform away to near lockout (don't lock hard), then lower until knees reach ~90°."),
        Entry(name: "Hack Squat", category: "Legs", howTo: "Shoulders under the pads, lower into a deep squat along the machine's track, then press back up."),
        Entry(name: "Bulgarian Split Squat", category: "Legs", howTo: "Rear foot elevated, lower the back knee toward the floor over the front foot, then drive up through the front heel."),
        Entry(name: "Walking Lunge", category: "Legs", howTo: "Step forward and lower the back knee toward the floor, then push off to step through into the next lunge."),
        Entry(name: "Reverse Lunge", category: "Legs", howTo: "Step backward and lower the back knee, keeping weight on the front heel; drive up to standing."),
        Entry(name: "Step-up", category: "Legs", howTo: "Drive through the foot on a box to stand fully, then lower under control; keep the knee tracking over the toes."),
        Entry(name: "Leg Extension", category: "Legs", howTo: "Extend the knees to straighten the legs against the pad, squeeze the quads, then lower slowly."),
        Entry(name: "Lying Leg Curl", category: "Legs", howTo: "Curl the pad toward your glutes by bending the knees, squeeze the hamstrings, then lower under control."),
        Entry(name: "Seated Leg Curl", category: "Legs", howTo: "Curl the pad down and under by bending the knees; pause, then return slowly for constant hamstring tension."),
        Entry(name: "Sumo Squat", category: "Legs", howTo: "Wide stance, toes out; squat straight down pushing the knees out, then stand and squeeze the glutes."),

        // MARK: Glutes
        Entry(name: "Barbell Hip Thrust", category: "Glutes", howTo: "Shoulders on a bench, bar over the hips; drive the hips up to a flat back-to-knee line and squeeze the glutes."),
        Entry(name: "Glute Bridge", category: "Glutes", howTo: "Lying down, drive the hips up by squeezing the glutes until the body forms a straight line, then lower."),
        Entry(name: "Cable Kickback", category: "Glutes", howTo: "With an ankle strap, kick the leg straight back and up, squeezing the glute; return under control."),
        Entry(name: "Cable Pull-through", category: "Glutes", howTo: "Facing away from a low pulley, hinge at the hips and let the rope pull back, then stand by squeezing the glutes."),
        Entry(name: "Hip Abduction (Machine)", category: "Glutes", howTo: "Push the pads apart by driving the knees out against resistance; squeeze, then return slowly."),
        Entry(name: "Curtsy Lunge", category: "Glutes", howTo: "Step one leg behind and across the other and lower into a lunge; drive up through the front heel."),
        Entry(name: "Frog Pump", category: "Glutes", howTo: "Soles of the feet together, knees out; pulse the hips up squeezing the glutes, then lower."),

        // MARK: Calves
        Entry(name: "Standing Calf Raise", category: "Calves", howTo: "Rise onto the balls of your feet as high as possible, pause, then lower the heels for a deep stretch."),
        Entry(name: "Seated Calf Raise", category: "Calves", howTo: "With pads on your knees, press up onto the balls of your feet, squeeze, and lower slowly (targets the soleus)."),
        Entry(name: "Leg Press Calf Raise", category: "Calves", howTo: "With the balls of your feet on the platform edge, press the platform by extending the ankles, then lower."),
        Entry(name: "Single-Leg Calf Raise", category: "Calves", howTo: "On one foot, rise onto the ball of the foot for a full range, then lower under control; switch sides."),

        // MARK: Core
        Entry(name: "Plank", category: "Core", howTo: "Hold a straight line from head to heels on the forearms, bracing the abs and glutes; don't let the hips sag."),
        Entry(name: "Side Plank", category: "Core", howTo: "On one forearm, stack the hips and feet and lift into a straight line; hold and brace the obliques."),
        Entry(name: "Hanging Leg Raise", category: "Core", howTo: "Hang from a bar and raise straight legs to hip height or above without swinging, then lower under control."),
        Entry(name: "Hanging Knee Raise", category: "Core", howTo: "Hang and draw the knees up toward the chest, curling the pelvis; lower slowly without swinging."),
        Entry(name: "Cable Crunch", category: "Core", howTo: "Kneel at a high pulley and crunch the rib cage toward the pelvis by rounding the spine; return slowly."),
        Entry(name: "Crunch", category: "Core", howTo: "Lying down, curl the shoulders off the floor by contracting the abs; lower under control."),
        Entry(name: "Bicycle Crunch", category: "Core", howTo: "Alternate bringing each elbow toward the opposite knee while extending the other leg; move with control."),
        Entry(name: "Russian Twist", category: "Core", howTo: "Sit leaning back with feet up; rotate the torso side to side, tapping the weight beside each hip."),
        Entry(name: "Dead Bug", category: "Core", howTo: "On your back with arms and knees up, lower the opposite arm and leg while keeping the lower back flat, then switch."),
        Entry(name: "Ab Wheel Rollout", category: "Core", howTo: "From the knees, roll the wheel forward keeping the abs braced and back flat, then pull back to the start."),
        Entry(name: "Mountain Climber", category: "Core", howTo: "In a plank, drive the knees toward the chest alternately at a quick pace while keeping the hips level."),
        Entry(name: "Leg Raise", category: "Core", howTo: "Lying down, raise straight legs to vertical, then lower slowly without letting the lower back arch."),

        // MARK: Cardio
        Entry(name: "Treadmill Run", category: "Cardio", howTo: "Run at a steady or interval pace with an upright posture and relaxed arms; set incline as desired."),
        Entry(name: "Treadmill Walk", category: "Cardio", howTo: "Walk at a brisk pace, optionally on an incline, keeping a tall posture and a natural arm swing."),
        Entry(name: "Stationary Bike", category: "Cardio", howTo: "Pedal at a steady cadence with resistance set so effort is challenging but sustainable; keep the core engaged."),
        Entry(name: "Rowing Machine", category: "Cardio", howTo: "Drive with the legs, then lean back and pull the handle to the lower ribs; reverse the order to return."),
        Entry(name: "Elliptical", category: "Cardio", howTo: "Stride smoothly pushing and pulling the handles; keep an upright posture and steady cadence."),
        Entry(name: "Stair Climber", category: "Cardio", howTo: "Step continuously at a steady pace without leaning hard on the rails; keep the chest up."),
        Entry(name: "Jump Rope", category: "Cardio", howTo: "Turn the rope from the wrists and hop just high enough to clear it, landing softly on the balls of the feet."),
        Entry(name: "Burpee", category: "Cardio", howTo: "Drop to a plank, do a push-up if desired, jump the feet in, then jump up explosively; repeat."),
        Entry(name: "High Knees", category: "Cardio", howTo: "Run in place driving the knees up to hip height at a quick pace, staying on the balls of your feet."),
        Entry(name: "Battle Ropes", category: "Cardio", howTo: "Hold an end in each hand and create fast waves with the arms while keeping a braced athletic stance."),

        // MARK: Full Body / Power
        Entry(name: "Kettlebell Swing", category: "Full Body", howTo: "Hinge and hike the bell back, then snap the hips forward to float it to chest height; let it fall and repeat."),
        Entry(name: "Power Clean", category: "Full Body", howTo: "Explosively extend the hips to pull the bar up, then drop under and catch it in the front rack; stand tall."),
        Entry(name: "Hang Clean", category: "Full Body", howTo: "From the hang, explosively extend the hips and shrug, then pull under to catch the bar in the front rack."),
        Entry(name: "Snatch", category: "Full Body", howTo: "In one explosive motion, pull the bar overhead from the floor and catch it locked out in a squat, then stand."),
        Entry(name: "Thruster", category: "Full Body", howTo: "From a front-rack squat, drive up and press the bar overhead in one motion; lower to the rack and repeat."),
        Entry(name: "Clean and Press", category: "Full Body", howTo: "Clean the weight to the shoulders, then press it overhead to lockout; lower and repeat."),
        Entry(name: "Dumbbell Snatch", category: "Full Body", howTo: "Explosively pull one dumbbell from between the feet to overhead in a single motion; lower and switch sides."),
        Entry(name: "Wall Ball", category: "Full Body", howTo: "Squat with the ball at your chest, then stand and throw it to a target overhead; catch and repeat."),
    ]

    /// Category → ordered exercise names. Derived from `entries`; preserves backward compatibility.
    public static let categorizedExercises: [String: [String]] = {
        var result: [String: [String]] = [:]
        for entry in entries {
            result[entry.category, default: []].append(entry.name)
        }
        return result
    }()

    /// Exercise name → how-to cue.
    public static let instructions: [String: String] = {
        var result: [String: String] = [:]
        for entry in entries where result[entry.name] == nil {
            result[entry.name] = entry.howTo
        }
        return result
    }()

    /// All exercise names, alphabetized.
    public static var allExercises: [String] { entries.map(\.name).sorted() }

    public static func instructions(for name: String) -> String? { instructions[name] }

    public static func category(for name: String) -> String? {
        entries.first { $0.name == name }?.category
    }
}
