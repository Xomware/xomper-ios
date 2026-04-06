import SwiftUI

// MARK: - XStroke

private struct XStroke: Shape {
    let topLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.1
        if topLeft {
            path.move(to: CGPoint(x: inset, y: inset))
            path.addQuadCurve(
                to: CGPoint(x: rect.width - inset, y: rect.height - inset),
                control: CGPoint(x: rect.midX + rect.width * 0.05, y: rect.midY - rect.height * 0.05)
            )
        } else {
            path.move(to: CGPoint(x: rect.width - inset, y: inset))
            path.addQuadCurve(
                to: CGPoint(x: inset, y: rect.height - inset),
                control: CGPoint(x: rect.midX - rect.width * 0.05, y: rect.midY - rect.height * 0.05)
            )
        }
        return path
    }
}

// MARK: - Paint (splash / long loads)

struct XomperLoaderPaint: View {
    var size: CGFloat = 60

    @State private var stroke1: CGFloat = 0
    @State private var stroke2: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        Image("XomperLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .mask {
                ZStack {
                    XStroke(topLeft: true)
                        .trim(from: 0, to: stroke1)
                        .stroke(style: StrokeStyle(lineWidth: size * 0.35, lineCap: .round))
                    XStroke(topLeft: false)
                        .trim(from: 0, to: stroke2)
                        .stroke(style: StrokeStyle(lineWidth: size * 0.35, lineCap: .round))
                }
            }
            .opacity(opacity)
            .onAppear { animate() }
            .accessibilityLabel("Loading")
    }

    private func animate() {
        stroke1 = 0; stroke2 = 0; opacity = 1
        withAnimation(.easeOut(duration: 0.5)) { stroke1 = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.5)) { stroke2 = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            withAnimation(.easeIn(duration: 0.4)) { opacity = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { animate() }
    }
}

// MARK: - Pulse (medium loads)

struct XomperLoaderPulse: View {
    var size: CGFloat = 40

    @State private var isPulsing = false

    var body: some View {
        Image("XomperLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(isPulsing ? 1.15 : 0.85)
            .opacity(isPulsing ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
            .accessibilityLabel("Loading")
    }
}

// MARK: - Spin (quick loads)

struct XomperLoaderSpin: View {
    var size: CGFloat = 36

    @State private var rotation: Double = 0

    var body: some View {
        Image("XomperLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotation)
            .onAppear { rotation = 360 }
            .accessibilityLabel("Loading")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        XomperColors.bgDark.ignoresSafeArea()
        VStack(spacing: 40) {
            VStack(spacing: 8) {
                XomperLoaderPaint(size: 80)
                Text("Paint").font(.caption).foregroundStyle(XomperColors.textSecondary)
            }
            VStack(spacing: 8) {
                XomperLoaderPulse(size: 60)
                Text("Pulse").font(.caption).foregroundStyle(XomperColors.textSecondary)
            }
            VStack(spacing: 8) {
                XomperLoaderSpin(size: 50)
                Text("Spin").font(.caption).foregroundStyle(XomperColors.textSecondary)
            }
        }
    }
}
