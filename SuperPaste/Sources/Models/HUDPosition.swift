import SwiftUI

/// Position of the HUD on screen
enum HUDPosition: String, CaseIterable, Identifiable {
    case topRight = "topRight"
    case topLeft = "topLeft"
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topRight: return "Top Right"
        case .topLeft: return "Top Left"
        case .bottomRight: return "Bottom Right"
        case .bottomLeft: return "Bottom Left"
        }
    }

    var icon: String {
        switch self {
        case .topRight: return "arrow.up.right"
        case .topLeft: return "arrow.up.left"
        case .bottomRight: return "arrow.down.right"
        case .bottomLeft: return "arrow.down.left"
        }
    }

    /// Calculate the origin point for the HUD window
    func origin(hudSize: CGSize, screenFrame: CGRect, margin: CGFloat = 16) -> CGPoint {
        switch self {
        case .topRight:
            return CGPoint(
                x: screenFrame.maxX - hudSize.width - margin,
                y: screenFrame.maxY - hudSize.height - margin
            )
        case .topLeft:
            return CGPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.maxY - hudSize.height - margin
            )
        case .bottomRight:
            return CGPoint(
                x: screenFrame.maxX - hudSize.width - margin,
                y: screenFrame.minY + margin
            )
        case .bottomLeft:
            return CGPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.minY + margin
            )
        }
    }
}
