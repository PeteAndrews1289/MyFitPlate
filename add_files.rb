require 'xcodeproj'
project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MyFitPlate' }
group = project.main_group.find_subpath('CalorieBeta', true)

['CalorieBeta/RecipeLoggingView.swift', 'CalorieBeta/AIMenuSelectionView.swift'].each do |file_path|
  file_ref = group.new_reference(file_path)
  target.add_file_references([file_ref])
end

project.save
