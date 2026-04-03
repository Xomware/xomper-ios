#!/bin/sh
# Xcode Cloud post-clone script

cd "$CI_PRIMARY_REPOSITORY_PATH"
PBXPROJ="Xomper.xcodeproj/project.pbxproj"

# 1. Build number — Xcode Cloud auto-increments CI_BUILD_NUMBER
if [ -n "$CI_BUILD_NUMBER" ]; then
    echo "Setting build number to $CI_BUILD_NUMBER"
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER/g" "$PBXPROJ"
fi

# 2. Marketing version — MAJOR.BUILD (e.g., 1.1, 1.2, 1.3...)
# Set MAJOR via env var when ready for 2.x
MAJOR="${APP_VERSION_MAJOR:-1}"
MARKETING_VERSION="${MAJOR}.${CI_BUILD_NUMBER:-0}"
echo "Setting marketing version to $MARKETING_VERSION"
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $MARKETING_VERSION/g" "$PBXPROJ"

# 3. Generate Config.swift from environment variables
CONFIG_PATH="$CI_PRIMARY_REPOSITORY_PATH/Xomper/Config/Config.swift"
echo "Generating Config.swift..."

cat > "$CONFIG_PATH" << EOF
import Foundation

enum Config {
    static let supabaseURL = "${SUPABASE_URL}"
    static let supabaseAnonKey = "${SUPABASE_ANON_KEY}"
    static let oauthCallbackURL = "xomper://login-callback"
    static let apiGatewayURL = "${API_GATEWAY_URL}"
    static let whitelistedLeagueId = "${WHITELISTED_LEAGUE_ID}"

    static var isConfigured: Bool {
        !supabaseURL.contains("YOUR_") && !supabaseAnonKey.contains("YOUR_")
    }
}
EOF

echo "Config.swift generated"
