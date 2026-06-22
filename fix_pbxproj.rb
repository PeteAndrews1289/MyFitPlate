require 'xcodeproj'
project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MyFitPlate' }
group = project.main_group.find_subpath('CalorieBeta', false)

# Remove the broken references
broken_refs = group.files.select { |f| f.path == 'CalorieBeta/RecipeLoggingView.swift' || f.path == 'CalorieBeta/AIMenuSelectionView.swift' }
broken_refs.each do |ref|
  target.source_build_phase.files_references.delete(ref)
  ref.remove_from_project
end

# Add the correct references
['RecipeLoggingView.swift', 'AIMenuSelectionView.swift'].each do |file_path|
  file_ref = group.new_reference(file_path)
  target.add_file_references([file_ref])
end

project.save
