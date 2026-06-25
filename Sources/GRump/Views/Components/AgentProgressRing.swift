import SwiftUI

/// A minimal circular progress ring that fills based on agent step progress.
/// Shows only the ring with no text — hover tooltip provides details.
struct AgentProgressRing: View {
    @EnvironmentObject var themeManager: ThemeManager
    var step: Int?
    var maxStep: Int?

    @State private var rotationAngle: Double = 0

    private var progress: Double {
        guard let step = step, let max = maxStep, max > 0 else { return 0 }
        return min(Double(step) / Double(max), 1.0)
    }

    private var isIndeterminate: Bool {
        step == nil || maxStep == nil || maxStep == 0
    }

    private let ringSize: CGFloat = 22
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(themeManager.palette.effectiveAccent.opacity(0.15), lineWidth: lineWidth)

            if isIndeterminate {
                // Spinning indeterminate ring
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        themeManager.palette.effectiveAccent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            rotationAngle = 360
                        }
                    }
            } else {
                // Determinate progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        themeManager.palette.effectiveAccent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityLabel(isIndeterminate ? "Thinking" : "Step \(step ?? 0) of \(maxStep ?? 0)")
    }
}
