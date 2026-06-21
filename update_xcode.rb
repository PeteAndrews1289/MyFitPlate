require 'xcodeproj'
project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'MyFitPlate' }
live_target = project.targets.find { |t| t.name == 'LiveActivityExtension' }
widget_target = project.targets.find { |t| t.name == 'CalorieWidgetExtension' }

# File Paths
fasting_attrs_path = 'CalorieBeta/FastingActivityAttributes.swift'
fasting_widget_path = 'LiveActivity/FastingActivityWidget.swift'
end_fast_intent_path = 'LiveActivity/EndFastIntent.swift'

# Add to Main Group
main_group = project.main_group.find_subpath('CalorieBeta', true)
live_group = project.main_group.find_subpath('LiveActivity', true)

attr_ref = main_group.files.find { |f| f.path == fasting_attrs_path } || main_group.new_file(fasting_attrs_path)
widget_ref = live_group.files.find { |f| f.path == fasting_widget_path } || live_group.new_file(fasting_widget_path)
intent_ref = live_group.files.find { |f| f.path == end_fast_intent_path } || live_group.new_file(end_fast_intent_path)

# Add to Targets
main_target.add_file_references([attr_ref, intent_ref])
live_target.add_file_references([attr_ref, widget_ref, intent_ref])
widget_target.add_file_references([attr_ref]) if widget_target

project.save
