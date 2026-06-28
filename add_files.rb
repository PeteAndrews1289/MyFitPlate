require 'xcodeproj'

project_path = 'MyFitPlate.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'MyFitPlate' }

# Find the main group for CalorieBeta
calorie_beta = project.main_group.groups.find { |g| g.path == 'CalorieBeta' }
core_group = calorie_beta.groups.find { |g| g.path == 'Core' }

# Find or create DependencyInjection group
di_group = core_group.groups.find { |g| g.path == 'DependencyInjection' }
unless di_group
  di_group = core_group.new_group('DependencyInjection', 'DependencyInjection')
end

# Add all .swift files
Dir.glob('CalorieBeta/Core/DependencyInjection/*.swift').each do |file_path|
  basename = File.basename(file_path)
  # Check if already added
  unless di_group.files.find { |f| f.path == basename }
    file_ref = di_group.new_file(basename)
    target.source_build_phase.add_file_reference(file_ref, true)
    puts "Added #{basename}"
  end
end

project.save
puts "Project saved."
