import SwiftUI

struct ContinueProgramCard: View {
    let program: WorkoutProgram
    let nextWorkout: (routine: WorkoutRoutine, title: String)
    let onStartWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Program")
                .appFont(size: 17, weight: .semibold)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(program.name)
                        .appFont(size: 24, weight: .bold)
                        .lineLimit(2)
                    Spacer()
                    Menu {
                        Button("View Program Details") {
                        }
                        Button("Change Program", role: .destructive) {
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                    }
                }
                
                Text(nextWorkout.routine.name)
                    .appFont(size: 15, weight: .medium)
                    .foregroundColor(.secondary)

                Divider()

                VStack(spacing: 8) {
                    HStack {
                        Text("Exercise").appFont(size: 12, weight: .semibold).foregroundColor(.secondary)
                        Spacer()
                        Text("Sets").appFont(size: 12, weight: .semibold).foregroundColor(.secondary)
                        Text("Target").appFont(size: 12, weight: .semibold).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)

                    ForEach(nextWorkout.routine.exercises) { exercise in
                        HStack {
                            Text(exercise.name).appFont(size: 15).lineLimit(1)
                            Spacer()
                            Text("\(exercise.sets.count)").appFont(size: 15)
                            Text(exercise.sets.first?.target ?? "-").appFont(size: 15)
                        }
                        .padding(.horizontal, 8)
                    }
                }

                Button(action: onStartWorkout) {
                    Text(nextWorkout.title)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)

            }
            .padding()
            .background(Color.backgroundSecondary)
            .cornerRadius(20)
        }
    }
}
