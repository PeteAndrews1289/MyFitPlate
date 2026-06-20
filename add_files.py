from pbxproj import XcodeProject
project = XcodeProject.load('MyFitPlate.xcodeproj/project.pbxproj')
project.add_file('CalorieBeta/DependencyContainer.swift', force=False)
project.add_file('CalorieBeta/ShimmerModifier.swift', force=False)
project.add_file('CalorieBeta/HapticFeedback.swift', force=False)
project.save()
