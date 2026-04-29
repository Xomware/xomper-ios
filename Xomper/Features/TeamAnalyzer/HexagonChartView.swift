import SwiftUI

/// Custom Path-based radar chart with 6 axes (QB / RB / WR / TE /
/// Bench / Taxi). SwiftUI Charts (iOS 17) doesn't ship a polar chart
/// type, so this is a Canvas-driven render. Two polygons can be drawn
/// at once for opponent comparison; the second one overlays in a
/// translucent contrasting color.
struct HexagonChartView: View {
    /// Primary team's per-axis values, in canonical order
    /// (QB, RB, WR, TE, Bench, Taxi).
    let primary: [TeamAnalysis.HexAxis]
    /// Optional comparison team. When nil, only the primary polygon
    /// renders.
    let comparison: [TeamAnalysis.HexAxis]?
    /// League-wide max per axis label, used to normalize each polygon
    /// vertex against. Falls back to local max when an axis isn't in
    /// the dictionary.
    let axisMaxes: [String: Int]

    /// Axis label color treatment.
    private let primaryColor = XomperColors.championGold
    private let comparisonColor = Color.cyan

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: size / 2)
            let radius = size / 2 * 0.78  // leave room for labels

            ZStack {
                gridPolygons(center: center, radius: radius)
                axisLines(center: center, radius: radius)

                if let comparison {
                    polygon(
                        for: comparison,
                        center: center,
                        radius: radius,
                        color: comparisonColor
                    )
                }
                polygon(
                    for: primary,
                    center: center,
                    radius: radius,
                    color: primaryColor
                )

                axisLabels(center: center, radius: radius)
            }
            .frame(width: geo.size.width, height: size)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Grid

    private func gridPolygons(center: CGPoint, radius: CGFloat) -> some View {
        Canvas { ctx, _ in
            let levels: [CGFloat] = [0.25, 0.5, 0.75, 1.0]
            for level in levels {
                let path = hexPath(center: center, radius: radius * level)
                ctx.stroke(
                    path,
                    with: .color(XomperColors.surfaceLight.opacity(0.35)),
                    lineWidth: level == 1.0 ? 1.5 : 1.0
                )
            }
        }
    }

    private func axisLines(center: CGPoint, radius: CGFloat) -> some View {
        Canvas { ctx, _ in
            for i in 0..<6 {
                var path = Path()
                path.move(to: center)
                path.addLine(to: vertex(center: center, radius: radius, index: i))
                ctx.stroke(
                    path,
                    with: .color(XomperColors.surfaceLight.opacity(0.25)),
                    lineWidth: 1
                )
            }
        }
    }

    // MARK: - Team polygon

    private func polygon(
        for axes: [TeamAnalysis.HexAxis],
        center: CGPoint,
        radius: CGFloat,
        color: Color
    ) -> some View {
        let points: [CGPoint] = axes.enumerated().map { idx, axis in
            let max = axisMaxes[axis.label] ?? axis.value
            let normalized = max > 0 ? CGFloat(axis.value) / CGFloat(max) : 0
            let r = radius * normalized
            return vertex(center: center, radius: r, index: idx)
        }
        return Canvas { ctx, _ in
            var path = Path()
            for (i, p) in points.enumerated() {
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(0.28)))
            ctx.stroke(path, with: .color(color), lineWidth: 2)

            for p in points {
                let dot = Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
                ctx.fill(dot, with: .color(color))
            }
        }
    }

    // MARK: - Labels

    private func axisLabels(center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            ForEach(Array(primary.enumerated()), id: \.offset) { idx, axis in
                let labelRadius = radius * 1.18
                let p = vertex(center: center, radius: labelRadius, index: idx)
                Text(axis.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.textSecondary)
                    .position(x: p.x, y: p.y)
            }
        }
    }

    // MARK: - Geometry helpers

    /// Vertex i of a hexagon, starting from straight up (12 o'clock)
    /// and rotating clockwise. -π/2 puts axis 0 at top.
    private func vertex(center: CGPoint, radius: CGFloat, index: Int) -> CGPoint {
        let angle = (CGFloat(index) * .pi / 3) - (.pi / 2)
        return CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    private func hexPath(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for i in 0..<6 {
            let p = vertex(center: center, radius: radius, index: i)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}
