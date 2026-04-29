import SwiftUI

/// Slide-out navigation drawer. Overlays the leading edge of the screen.
/// Width: `min(screenWidth * 0.82, 320)`.
///
/// The drawer is a pure menu — every row calls `navStore.select(_:)` which
/// (a) pops the inner router stack to root, (b) sets `currentDestination`,
/// and (c) closes the drawer, all in a single animation.
struct DrawerView: View {
    let navStore: NavigationStore
    let router: AppRouter

    /// Signed-in user's avatar / display name / email for the profile card.
    let avatarID: String?
    let displayName: String?
    let email: String?

    // MARK: - Section model

    /// Drawer sections (top-to-bottom). `Settings` is pinned separately to the
    /// bottom of the panel and is not in this list.
    private let sections: [TraySection] = [
        TraySection(
            title: "Compete",
            entries: [.standings, .matchups, .playoffs]
        ),
        TraySection(
            title: "History",
            entries: [.draftHistory, .matchupHistory, .worldCup]
        ),
        TraySection(
            title: "Roster",
            entries: [.myTeam, .taxiSquad, .teamAnalyzer]
        ),
        TraySection(
            title: "Rules",
            entries: [.rulebook, .scoring, .leagueSettings, .ruleProposals]
        ),
    ]

    // MARK: - Layout

    private let drawerWidth: CGFloat = {
        let screenWidth = UIScreen.main.bounds.width
        return min(screenWidth * 0.82, 320)
    }()

    // MARK: - Body

    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                drawerPanel
                    .gesture(closeDragGesture)
                Spacer(minLength: 0)
            }
        }
        .offset(x: navStore.isDrawerOpen ? 0 : -drawerWidth)
    }

    // MARK: - Panel

    private var drawerPanel: some View {
        VStack(spacing: 0) {
            TrayProfileCard(
                avatarID: avatarID,
                displayName: displayName,
                email: email,
                action: { navStore.select(.profile, router: router) }
            )
            .padding(.horizontal, 16)
            .padding(.top, 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

            // Pinned Settings footer.
            Divider()
                .overlay(Color.white.opacity(0.08))

            VStack(spacing: 6) {
                TrayItem(
                    destination: .settings,
                    isSelected: navStore.currentDestination == .settings,
                    action: { navStore.select(.settings, router: router) }
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .frame(width: drawerWidth)
        .background(
            LinearGradient(
                colors: [
                    XomperColors.bgDark,
                    XomperColors.bgCard.opacity(0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .vertical)
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
                .ignoresSafeArea(edges: .vertical)
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func sectionView(_ section: TraySection) -> some View {
        if let title = section.title {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.textMuted)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
        }

        ForEach(section.entries, id: \.self) { dest in
            TrayItem(
                destination: dest,
                isSelected: navStore.currentDestination == dest,
                action: { navStore.select(dest, router: router) }
            )
        }
    }

    // MARK: - Close drag

    /// Drag the open drawer leftward to dismiss. Mirrors `MainShell`'s edge
    /// swipe to open: requires a clearly horizontal drag past a small threshold
    /// so it doesn't fight scrolls inside the drawer's row list.
    private var closeDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onEnded { value in
                guard navStore.isDrawerOpen else { return }
                let pulledLeft = value.translation.width < -60
                let mostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                guard pulledLeft, mostlyHorizontal else { return }
                navStore.closeDrawer()
            }
    }
}
