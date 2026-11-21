import Foundation

/// Read-only teaching content. This never assigns identities, edits prescriptions, or rewrites history.
public struct WorkoutTechniqueGuide: Identifiable, Sendable {
    public struct Reference: Identifiable, Sendable {
        public let title: String
        public let url: URL
        public var id: String { url.absoluteString }
    }
    public let canonicalName: String
    public let identity: WorkoutMovementIdentity
    public let quickCue: String
    public let setup: [String]
    public let execution: [String]
    public let corrections: [String]
    public let variation: String
    public let reference: Reference
    public var id: String { "\(identity.movementID).\(identity.variantID)" }
}

public enum WorkoutTechniqueCatalog {
    /// Exact identities take precedence over display names. Legacy records only receive exact-name
    /// guidance; aliases and similar names must not turn custom movements into catalog variants.
    public static func guide(for exercise: RoutineExercise) -> WorkoutTechniqueGuide? {
        guard exercise.type == .strength else { return nil }
        if let identity = exercise.movementIdentity {
            guard identity.isValid, identity.ownerID == nil else { return nil }
            return guides.first { $0.identity == identity }
        }
        return guides.first { $0.canonicalName == exercise.name }
    }

    public static func briefCue(for exercise: RoutineExercise) -> String? {
        guard exercise.type == .strength else { return nil }
        if let guide = guide(for: exercise) { return guide.quickCue }
        if let identity = exercise.movementIdentity {
            guard identity.isValid, identity.ownerID == nil else { return nil }
            return ExerciseList.entries.first {
                WorkoutMovementCatalog.identity(for: $0.name) == identity
            }?.howTo
        }
        return ExerciseList.entries.first { $0.name == exercise.name }?.howTo
    }

    // Original, concise coaching copy checked against the linked primary teaching references.
    // Broad catalog names have an explicit setup scope; no new equipment/variant identity is implied.
    public static let guides: [WorkoutTechniqueGuide] = [
        make("Barbell Bench Press", cue: "Stable feet. Controlled touch. Press up and back.",
            setup: ["Set the rack and safeties for your range, or arrange a spotter before lifting.", "Keep feet planted and shoulders supported. Wrap thumbs around the bar; align wrists over elbows."],
            execution: ["Lower toward the mid-chest with control while keeping your hips on the bench.", "Press up and slightly back until your arms extend; settle before the next rep."],
            corrections: ["Bouncing off the chest: slow the descent and reverse the bar under control.", "Wrists folding back or elbows drifting: adjust your grip so forearms support the bar."],
            variation: "Flat barbell bench press. Incline presses and dumbbell presses have separate guides.",
            source: "ACE · Barbell chest press", url: "https://www.acefitness.org/resources/everyone/exercise-library/5/chest-press/"),
        make("Dumbbell Bench Press", cue: "Steady shoulders. Level dumbbells. Controlled return.",
            setup: ["Lie on a flat bench with feet supported and shoulder blades settled against the pad.", "Hold both dumbbells over your chest with straight wrists. Get help positioning them if needed."],
            execution: ["Lower both weights together beside your chest through a comfortable range.", "Press back over your chest, keeping each weight balanced above its elbow."],
            corrections: ["One weight racing ahead: reduce the load and match the tempo on both sides.", "Reaching too deep or lifting your hips: shorten the range until your setup stays steady."],
            variation: "Two dumbbells on a flat bench. This is separate from an incline or alternating press.",
            source: "ACE · Dumbbell chest press", url: "https://www.acefitness.org/resources/everyone/exercise-library/19/chest-press/"),
        make("Incline Dumbbell Bench Press", cue: "Press over the shoulders. Keep forearms under the weights.",
            setup: ["Set and lock the bench incline. Plant your feet and keep your back supported.", "Bring the dumbbells beside your shoulders with wrists stacked over elbows."],
            execution: ["Press both weights upward until they balance over your shoulders.", "Lower slowly, keeping upper arms angled toward your sides rather than flared straight out."],
            corrections: ["Weights drifting forward: finish above your shoulders, not your stomach.", "Changing the bench angle between sessions: record and repeat your chosen setup."],
            variation: "Inclined bench with two dumbbells; keep the same bench angle for comparable sessions.",
            source: "Catalyst Athletics · Dumbbell incline bench press", url: "https://www.catalystathletics.com/exercise/819/Dumbbell-Incline-Bench-Press/"),
        make("Incline Barbell Bench Press", cue: "Upper-chest descent. Steady feet. Press without sliding.",
            setup: ["Lock the bench incline and position the rack and safeties, or arrange a spotter.", "Plant your feet, support your shoulders, and take a full grip just wider than shoulder width."],
            execution: ["Lower the bar toward your upper chest with wrists above elbows.", "Press upward to extended arms while keeping your hips and shoulders supported."],
            corrections: ["Sliding down the bench: reset your feet and seat before the next rep.", "Bouncing the bar or losing wrist position: reduce the load and control the turnaround."],
            variation: "Inclined barbell press. Bench angle changes the movement; use a consistent setting.",
            source: "NASM · Incline barbell bench press", url: "https://www.nasm.org/resource-center/exercise-library/incline-barbell-bench-press"),
        make("Barbell Bent-over Row", cue: "Hold the hinge. Row to the torso. Lower without standing up.",
            setup: ["Take an overhand grip and hinge at the hips with knees slightly bent.", "Brace your trunk, let the arms hang, and choose a torso angle you can hold."],
            execution: ["Pull the bar toward your abdomen while keeping it close to your body.", "Lower until your arms extend, keeping the same torso angle for the next rep."],
            corrections: ["Standing up to throw the bar: lighten it and keep the hip position steady.", "Neck craning upward: look toward the floor ahead of you and keep your head aligned."],
            variation: "Controlled bent-over row with the bar held between reps. Pendlay rows reset on the floor and are separate.",
            source: "Catalyst Athletics · Bent row", url: "https://www.catalystathletics.com/exercise/171/Bent-Row/"),
        make("Lat Pulldown", cue: "Elbows down. Chest tall. Return with control.",
            setup: ["Adjust the thigh pad to hold you securely with feet supported.", "Grip the bar overhead, brace your trunk, and establish a small, steady backward lean."],
            execution: ["Pull the bar in front toward your upper chest by bringing elbows down.", "Let your arms lengthen overhead slowly without letting the stack pull you out of position."],
            corrections: ["Rocking backward to finish: lower the load and hold your torso angle.", "Pulling behind the neck: keep this variation in front of your body."],
            variation: "Seated cable pulldown with a bar in front. Grip and attachment can vary; keep your setup consistent.",
            source: "ACE · Seated lat pulldown", url: "https://www.acefitness.org/resources/everyone/exercise-library/158/seated-lat-pulldown/"),
        make("Barbell Overhead Press (Military Press)", cue: "Brace. Clear the face. Finish over your body.",
            setup: ["Start with the bar at the front of your shoulders and hands just outside them.", "Keep forearms under the bar, feet stable, and your trunk braced."],
            execution: ["Press without a knee dip, moving your head just enough to clear the bar.", "Finish with the bar balanced overhead, then lower to the shoulders under control."],
            corrections: ["Leaning back to finish: reduce the load and keep your ribs over your pelvis.", "Driving with the legs: reset before pressing; that changes this strict press into a push press."],
            variation: "Standing strict barbell press from the front of the shoulders; no leg drive.",
            source: "CSCCa · Barbell overhead press", url: "https://www.cscca.org/content.aspx?club_id=408309&module_id=732261&page_id=22"),
        make("Dumbbell Shoulder Press", cue: "Wrists over elbows. Press evenly. Keep your trunk still.",
            setup: ["Stand with feet stable and bring the dumbbells to shoulder height.", "Brace your trunk with elbows slightly forward and forearms supporting the weights."],
            execution: ["Press both dumbbells overhead without using a knee dip.", "Lower evenly to your starting position while keeping your ribs and pelvis aligned."],
            corrections: ["Arching to finish: reduce the load or use a range you can control.", "Uneven arms: slow the rep and match each side before increasing the weight."],
            variation: "Standing two-dumbbell shoulder press. A seated setup changes support; record and repeat the setup you use.",
            source: "ACE · Shoulder exercise procedures", url: "https://www.acefitness.org/certifiednews/images/article/pdfs/ACEShoulderStudy.pdf"),
        make("Barbell Back Squat", cue: "Brace first. Knees follow toes. Keep the whole foot grounded.",
            setup: ["Set rack height and safeties. Rest the bar across your upper traps, clear of your neck.", "Take a balanced stance with toes turned out as needed, then brace before descending."],
            execution: ["Bend hips and knees together, keeping pressure across the whole foot.", "Descend only as far as you can control your balance and trunk, then stand with hips and chest rising together."],
            corrections: ["Heels lifting: reduce depth and reset your stance before adding load.", "Hips shooting up first: lighten the bar and keep your torso supported through the ascent."],
            variation: "High-bar setup described. Low-bar squats use a different bar placement and torso angle; keep your chosen setup consistent.",
            source: "Catalyst Athletics · Back squat", url: "https://www.catalystathletics.com/exercise/77/Back-Squat/"),
        make("Barbell Front Squat", cue: "Bar on the shoulders. Elbows up. Stand through the whole foot.",
            setup: ["Set rack height and safeties. Support the bar on the fronts of your shoulders, not in your hands.", "Lift elbows into a secure front rack, set your stance, and brace your trunk."],
            execution: ["Bend hips and knees while keeping the bar supported and knees aligned with your toes.", "Use a controlled depth, then stand with your chest and hips rising together."],
            corrections: ["Elbows dropping and bar rolling: reset the rack position and reduce the load.", "Weight shifting onto your toes: shorten the descent until you can keep your whole foot grounded."],
            variation: "Barbell front squat with a front-rack grip. Do not force wrist position to hold a bar that should rest on your shoulders.",
            source: "Catalyst Athletics · Front squat", url: "https://www.catalystathletics.com/exercise/78/Front-Squat/"),
        make("Deadlift (Conventional)", cue: "Brace before pulling. Keep the bar close. Stand tall.",
            setup: ["Place the bar over your mid-foot with feet about hip width apart.", "Hinge and bend your knees to grip outside your legs. Brace and take tension out of the bar before it leaves the floor."],
            execution: ["Push through the floor while extending hips and knees, keeping the bar near your legs.", "Stand tall, then hinge back and bend your knees to return the bar under control."],
            corrections: ["Jerking the bar from the floor: build tension before each pull.", "Leaning back at the top: finish standing upright without adding a backward bend."],
            variation: "Conventional stance with hands outside the legs. Sumo and Romanian deadlifts use different starts and are separate movements.",
            source: "NASM · Barbell deadlift", url: "https://www.nasm.org/resource-center/exercise-library/barbell-deadlift"),
        make("Romanian Deadlift", cue: "Soft knees. Hips back. Stop when the hinge ends.",
            setup: ["Start standing with the bar held in front of your thighs.", "Brace your trunk and soften your knees, keeping that bend nearly constant."],
            execution: ["Move your hips backward and lower the bar close to your legs.", "Stop before your back position changes, then bring your hips forward to stand."],
            corrections: ["Trying to touch the floor: use the depth your hip hinge allows.", "Turning it into a squat: keep the knees softly bent while the hips travel backward."],
            variation: "Barbell Romanian deadlift described; it begins from standing. Dumbbell versions use separate implements and should keep their own equipment setup.",
            source: "Catalyst Athletics · Romanian deadlift", url: "https://www.catalystathletics.com/exercise/101/Romanian-Deadlift-RDL/"),
        make("Leg Press", cue: "Keep your back supported. Follow your toes. Control the return.",
            setup: ["Adjust the seat and stops for your machine before releasing its safety mechanism.", "Place feet flat on the platform with your hips and back supported."],
            execution: ["Press the platform away, extending your legs without snapping the knees backward.", "Lower until you reach a controlled depth while your pelvis stays against the pad."],
            corrections: ["Lower back lifting from the pad: shorten the range or adjust the seat.", "Knees collapsing inward: reduce the load and keep knees tracking with your toes."],
            variation: "Seated two-leg press. Sled angle, starting resistance and travel vary by machine; follow its setup instructions and keep your load convention consistent.",
            source: "ACE · Seated leg press", url: "https://www.acefitness.org/resources/everyone/exercise-library/154/seated-leg-press/"),
        make("Seated Cable Row", cue: "Sit tall. Elbows back. Let the arms return slowly.",
            setup: ["Use the seated cable station with feet supported and knees slightly bent.", "Take a close, neutral handle grip and brace with your torso tall."],
            execution: ["Pull the handle toward your abdomen, bringing elbows beside your body.", "Return the handle with control while keeping your torso steady."],
            corrections: ["Rocking forward and backward: lighten the stack and move through the arms and shoulders.", "Shrugging to finish: keep the neck relaxed and stop before you lose position."],
            variation: "Close neutral-handle seated cable row described. Wider bars and other grips change the setup; record your attachment.",
            source: "ACE · Seated row", url: "https://www.acefitness.org/resources/everyone/exercise-library/48/seated-row/"),
        make("Dumbbell Row", cue: "Support your torso. Pull the elbow back. Keep hips square.",
            setup: ["Place one hand and the same-side knee on a stable bench, with the other foot on the floor.", "Brace your trunk and let the dumbbell hang from the free arm."],
            execution: ["Pull the dumbbell alongside your torso until you can go no farther without rotating.", "Lower to an extended arm under control, then repeat on the other side."],
            corrections: ["Twisting upward to finish: reduce the load and keep your chest facing the floor.", "Dropping the shoulder at the bottom: stop the descent while your trunk remains supported."],
            variation: "Bench-supported single-arm row. Follow the session's per-side rep target; a two-arm or unsupported row is a different setup.",
            source: "ACE · Single-arm row", url: "https://www.acefitness.org/resources/everyone/exercise-library/126/single-arm-row/"),
        make("Walking Lunge", cue: "Step. Lower with control. Bring the back leg through.",
            setup: ["Choose a clear walking path and stand tall, with or without added weight.", "Brace your trunk and step forward with enough width to keep your balance."],
            execution: ["Bend both knees, lowering the rear knee toward the floor while the front knee follows your toes.", "Push through the front foot to rise, bring the rear leg forward, and continue with the other leg."],
            corrections: ["Stepping on a tightrope: leave enough side-to-side space for balance.", "Dropping onto the rear knee: slow down and use a shallower range."],
            variation: "Walking forward rather than returning to the same starting spot. Follow the session's per-side rep count and keep the same loading setup.",
            source: "Catalyst Athletics · Lunge", url: "https://www.catalystathletics.com/exercise/354/Lunge/")
    ]

    private static func make(_ name: String, cue: String, setup: [String], execution: [String],
                             corrections: [String], variation: String, source: String, url: String) -> WorkoutTechniqueGuide {
        // These are static, tested catalog entries, not user input or inferred identities.
        precondition(ExerciseList.entries.contains { $0.name == name })
        return WorkoutTechniqueGuide(canonicalName: name, identity: WorkoutMovementCatalog.identity(for: name)!,
            quickCue: cue, setup: setup, execution: execution, corrections: corrections,
            variation: variation, reference: .init(title: source, url: URL(string: url)!))
    }
}
