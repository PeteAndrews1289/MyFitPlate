require 'xcodeproj'
project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'MyFitPlate' }
main_group = project.main_group.find_subpath('CalorieBeta', false)

attr_ref = main_group.files.find { |f| f.path == 'FastingManager.swift' } || main_group.new_file('FastingManager.swift')
main_target.add_file_references([attr_ref]) unless main_target.source_build_phase.files.any? { |f| f.file_ref == attr_ref }

project.save
