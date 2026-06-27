require 'xcodeproj'
require 'fileutils'

project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MyFitPlate' }

main_group = project.main_group.find_subpath('CalorieBeta', false)

# Create nested groups. find_subpath with 'true' creates it if missing.
features_group = main_group.find_subpath('Features', true)
features_group.set_path('Features')
workouts_group = features_group.find_subpath('Workouts', true)
workouts_group.set_path('Workouts')

files_to_move = [
  'WorkoutRoutinesView.swift',
  'WorkoutService.swift',
  'WorkoutModels.swift',
  'WorkoutDashboardViewModel.swift',
  'WorkoutServicing.swift',
  'TodaysNextStepSlider.swift'
]

FileUtils.mkdir_p('CalorieBeta/Features/Workouts')

files_to_move.each do |filename|
  old_path = "CalorieBeta/#{filename}"
  new_path = "CalorieBeta/Features/Workouts/#{filename}"
  
  if File.exist?(old_path)
    FileUtils.mv(old_path, new_path)
    puts "Moved #{filename} to Features/Workouts"
  end

  # Find old reference in main_group
  old_ref = main_group.files.find { |f| f.path == filename }
  if old_ref
    target.source_build_phase.files_references.delete(old_ref)
    old_ref.remove_from_project
  end
  
  # Add new reference to workouts_group
  # new_reference will set the path relative to the group's path
  file_ref = workouts_group.new_reference(filename)
  target.source_build_phase.add_file_reference(file_ref)
  puts "Updated Xcode project for #{filename}"
end

project.save
puts "Project saved."
