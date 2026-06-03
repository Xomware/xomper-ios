import SwiftUI

struct AvatarView: View {
    let avatarID: String?
    var size: CGFloat = XomperTheme.AvatarSize.md
    var isTeam: Bool = false

    /// Sleeper exposes both `/avatars/<id>` (full) and `/avatars/thumbs/<id>`
    /// (~80px). For the xl profile avatar use the full asset so it
    /// doesn't render pixelated.
    private var imageURL: URL? {
        guard let avatarID, !avatarID.isEmpty else { return nil }
        let path = size >= XomperTheme.AvatarSize.lg
            ? "https://sleepercdn.com/avatars/\(avatarID)"
            : "https://sleepercdn.com/avatars/thumbs/\(avatarID)"
        return URL(string: path)
    }

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        fallbackIcon
                    case .empty:
                        ProgressView()
                            .tint(XomperColors.textMuted)
                    @unknown default:
                        fallbackIcon
                    }
                }
                // Force the AsyncImage state machine to reset when the
                // URL changes from nil (pre-bootstrap) to a real URL.
                // Without this, SwiftUI sometimes holds onto the empty
                // phase and the avatar never appears.
                .id(imageURL)
            } else {
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(XomperColors.surfaceLight, lineWidth: 1)
        )
        .accessibilityLabel(isTeam ? "Team avatar" : "User avatar")
    }

    private var fallbackIcon: some View {
        ZStack {
            XomperColors.bgCardHover

            Image(systemName: isTeam ? "football.fill" : "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(XomperColors.textMuted)
        }
    }
}

// MARK: - Player Image Variant

struct PlayerImageView: View {
    let playerID: String
    var size: CGFloat = XomperTheme.AvatarSize.md

    private var imageURL: URL? {
        URL(string: "https://sleepercdn.com/content/nfl/players/thumb/\(playerID).jpg")
    }

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                fallbackIcon
            case .empty:
                ProgressView()
                    .tint(XomperColors.textMuted)
            @unknown default:
                fallbackIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(XomperColors.surfaceLight, lineWidth: 1)
        )
        .accessibilityLabel("Player photo")
    }

    private var fallbackIcon: some View {
        ZStack {
            XomperColors.bgCardHover

            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(XomperColors.textMuted)
        }
    }
}

#Preview {
    HStack(spacing: XomperTheme.Spacing.md) {
        AvatarView(avatarID: nil, size: 40)
        AvatarView(avatarID: "some-avatar-id", size: 56)
        PlayerImageView(playerID: "6794", size: 48)
    }
    .padding()
    .background(XomperColors.bgDark)
    .preferredColorScheme(.dark)
}
