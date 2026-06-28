require 'xcodeproj'

project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MyFitPlate' }

def add_files_to_group(project, target, dir_path, parent_group)
  Dir.glob("#{dir_path}/*").each do |item_path|
    basename = File.basename(item_path)
    if File.directory?(item_path)
      subgroup = parent_group.groups.find { |g| g.path == basename } || parent_group.new_group(basename, basename)
      add_files_to_group(project, target, item_path, subgroup)
    elsif item_path.end_with?('.swift')
      unless parent_group.files.find { |f| f.path == basename }
        file_ref = parent_group.new_file(basename)
        target.source_build_phase.add_file_reference(file_ref, true)
        puts "Added #{item_path}"
      end
    end
  end
end

calorie_beta = project.main_group.groups.find { |g| g.path == 'CalorieBeta' }
features_group = calorie_beta.groups.find { |g| g.path == 'Features' }
nutrition_group = features_group.groups.find { |g| g.path == 'Nutrition' }

add_files_to_group(project, target, 'CalorieBeta/Features/Nutrition', nutrition_group)

project.save
puts "Project saved."
