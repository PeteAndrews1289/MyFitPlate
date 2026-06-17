import WidgetKit
import SwiftUI

@main
struct LiveActivityBundle: WidgetBundle {
    var body: some Widget {
        // Use the struct name we defined in LiveActivity.swift
        WorkoutActivityWidget()
        
        // If you have other widgets (like a home screen widget), add them here:
        // MyHomeScreenWidget()
    }
}
