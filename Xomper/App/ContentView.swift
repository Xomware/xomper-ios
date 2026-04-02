import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            XomperColors.bgDark
                .ignoresSafeArea()

            VStack(spacing: XomperTheme.Spacing.lg) {
                Image(systemName: "football.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(XomperColors.championGold)

                Text("Xomper")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(XomperColors.textPrimary)

                Text("Fantasy Football Companion")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textSecondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
