import SwiftUI

/// Styling options for Liquid Glass effects
enum LiquidGlassShape {
    case circle
    case capsule
    case roundedRectangle(cornerRadius: CGFloat)
}

/// ViewModifier that applies a frosted liquid glass effect with refraction, specular rim highlight, and depth
struct LiquidGlassModifier: ViewModifier {
    var isEnabled: Bool
    var shape: LiquidGlassShape = .circle
    var tint: Color? = nil
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .background {
                    glassBackground
                }
                .overlay {
                    glassHighlightBorder
                }
                .shadow(
                    color: (tint ?? (isSelected ? .blue : .black)).opacity(isSelected ? 0.45 : 0.22),
                    radius: isSelected ? 6 : 3,
                    x: 0,
                    y: isSelected ? 3 : 1.5
                )
        } else {
            content
        }
    }

    @ViewBuilder
    private var glassBackground: some View {
        switch shape {
        case .circle:
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    (tint ?? Color.white).opacity(tint != nil ? 0.35 : 0.25),
                                    Color.white.opacity(0.12),
                                    (tint ?? Color.black).opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        case .capsule:
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    (tint ?? Color.white).opacity(tint != nil ? 0.35 : 0.25),
                                    Color.white.opacity(0.12),
                                    (tint ?? Color.black).opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        case .roundedRectangle(let radius):
            RoundedRectangle(cornerRadius: radius)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    (tint ?? Color.white).opacity(tint != nil ? 0.35 : 0.25),
                                    Color.white.opacity(0.12),
                                    (tint ?? Color.black).opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
    }

    @ViewBuilder
    private var glassHighlightBorder: some View {
        switch shape {
        case .circle:
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.28),
                            Color.clear,
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        case .capsule:
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.28),
                            Color.clear,
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        case .roundedRectangle(let radius):
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.28),
                            Color.clear,
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        }
    }
}

extension View {
    /// Applies liquid glass frosted background with specular highlights and depth
    func liquidGlass(
        isEnabled: Bool = true,
        shape: LiquidGlassShape = .circle,
        tint: Color? = nil,
        isSelected: Bool = false
    ) -> some View {
        self.modifier(LiquidGlassModifier(isEnabled: isEnabled, shape: shape, tint: tint, isSelected: isSelected))
    }
}
