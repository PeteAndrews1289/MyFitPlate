require 'xcodeproj'

project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
main_target = project.targets.find { |t| t.name == 'MyFitPlate' }
main_group = project.main_group.find_subpath('CalorieBeta', true)

# Remove old file
old_file_ref = main_group.files.find { |f| f.path == 'AIChatBotView.swift' || f.name == 'AIChatBotView.swift' }
if old_file_ref
  main_target.source_build_phase.files_references.delete(old_file_ref)
  old_file_ref.remove_from_project
  puts "Removed old AIChatBotView.swift from project"
else
  puts "Warning: Could not find old AIChatBotView.swift in project"
end

# Create or find Features/Maia group
features_group = main_group.find_subpath('Features', true)
maia_group = features_group.find_subpath('Maia', true)
maia_group.set_source_tree('<group>')
maia_group.set_path('Features/Maia')

# Add new files to group and target
new_files = [
  'Features/Maia/AIChatbotView.swift',
  'Features/Maia/AIChatbotViewModel.swift',
  'Features/Maia/AIChatModels.swift',
  'Features/Maia/AIChatComponents.swift'
]

new_files.each do |file_path|
  file_ref = maia_group.files.find { |f| f.path == File.basename(file_path) || f.name == File.basename(file_path) }
  unless file_ref
    file_ref = maia_group.new_file(File.basename(file_path))
    main_target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{file_path} to project"
  else
    puts "#{file_path} already in project"
  end
end

project.save
puts "Project saved successfully."
