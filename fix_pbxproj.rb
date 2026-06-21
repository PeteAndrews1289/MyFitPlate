require 'xcodeproj'
project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'MyFitPlate' }
live_target = project.targets.find { |t| t.name == 'LiveActivityExtension' }

# File Paths
fasting_attrs_path = 'CalorieBeta/FastingActivityAttributes.swift'
end_fast_intent_path = 'LiveActivity/EndFastIntent.swift'

# Add to Main Group
main_group = project.main_group.find_subpath('CalorieBeta', false)

# Create references
attr_ref = main_group.files.find { |f| f.path == 'FastingActivityAttributes.swift' } || main_group.new_file('FastingActivityAttributes.swift')

# Add to Targets
main_target.add_file_references([attr_ref]) unless main_target.source_build_phase.files.any? { |f| f.file_ref == attr_ref }
live_target.add_file_references([attr_ref]) unless live_target.source_build_phase.files.any? { |f| f.file_ref == attr_ref }

project.save
