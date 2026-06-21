require 'xcodeproj'
project = Xcodeproj::Project.open('MyFitPlate.xcodeproj')
project.root_object.main_group.children.each do |child|
  if child.class.name.include?('Synchronized')
    puts "Synchronized Group: #{child.path || child.name}"
  else
    puts "Normal Group: #{child.path || child.name}"
  end
end
