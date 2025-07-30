import SwiftUI

struct ChatBoxShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let cornerRadius: CGFloat = 35
        let tailWidth: CGFloat = 30
        let tailHeight: CGFloat = 20

        // Start at the top-left corner
        path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
        
        // Top edge
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        
        // Top-right corner
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tailHeight - cornerRadius))
        
        // Bottom-right corner before tail
        path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - tailHeight - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        
        // Bottom edge until the tail starts
        let tailStartX = rect.midX + tailWidth / 2
        path.addLine(to: CGPoint(x: tailStartX, y: rect.maxY - tailHeight))
        
        // The "speaking" tail
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: tailStartX - tailWidth, y: rect.maxY - tailHeight))

        // Bottom edge after tail
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - tailHeight))
        
        // Bottom-left corner
        path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - tailHeight - cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        
        // Top-left corner
        path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius), radius: cornerRadius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        path.closeSubpath()
        
        return path
    }
}
