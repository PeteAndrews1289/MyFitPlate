require 'xcodeproj'
project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first # MyFitPlate
group = project.main_group.find_subpath('CalorieBeta', true)
file_ref = group.new_reference(ARGV[0])
target.source_build_phase.add_file_reference(file_ref)
project.save
