require 'xcodeproj'
project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MyFitPlateTests' }
group = project.main_group.find_subpath('MyFitPlateTests', true)

ARGV.each do |file_name|
  file_ref = group.new_reference(file_name)
  target.source_build_phase.add_file_reference(file_ref)
end

project.save
