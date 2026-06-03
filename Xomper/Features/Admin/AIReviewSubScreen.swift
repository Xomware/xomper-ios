import SwiftUI

/// Admin → AI Review sub-screen. Hosts the pre-F1 `AdminView` content
/// **verbatim**: the three trigger cards (Post-Draft, Preseason, Weekly
/// with week-override stepper), the legacy test-sender card, the
/// filter bar, and the activity feed.
///
/// This view was carved out of `AdminView` in F1 so the admin home
/// could become a `NavigationLink` menu. The trigger / feed UX must
/// look identical to the pre-refactor screen — reviewers should pixel-
/// diff a recording against the previous AdminView.
///
/// `AdminStore` is **injected** from `MainShell` (F2 hoist) so the
/// preview view route can read the same instance — without the hoist a
/// pushed `AIReviewPreviewView` would see an empty `lastPreviewsByType`
/// dictionary because `AIReviewSubScreen`'s `@State` doesn't survive
/// the navigation push.
struct AIReviewSubScreen: View {
    var authStore: AuthStore
    var leagueStore: LeagueStore
    /// F2: hoisted from `@State` to an injected dependency so the
    /// pushed `AIReviewPreviewView` can read the same preview state.
    /// Keeping the `store` label (rather than renaming to `adminStore`)
    /// preserves every existing call site inside the view body. We
    /// use `@Bindable` so the existing `$store.foo` binding sites
    /// (toggles, pickers, stepper) keep compiling.
    @Bindable var store: AdminStore
    /// F2: needed so the trigger cards can navigate to the new
    /// `adminAIReviewPreview(reportType:)` route after a successful
    /// dry-run populates `store.lastPreviewsByType`.
    var router: AppRouter

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("AI Review")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: callerSleeperId) {
                await store.refresh(sleeperUserId: callerSleeperId)
                await store.loadPostDraftLatest()
                await store.loadPreseasonLatest()
                await store.loadWeeklyLatest()
                await store.loadWeekPreviewLatest()
            }
            .refreshable {
                await store.refresh(sleeperUserId: callerSleeperId)
                await store.loadPostDraftLatest()
                await store.loadPreseasonLatest()
                await store.loadWeeklyLatest()
                await store.loadWeekPreviewLatest()
            }
    }

    private var callerSleeperId: String {
        authStore.sleeperUserId ?? ""
    }

    private var callerEmail: String? {
        authStore.session?.user.email
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: XomperTheme.Spacing.md) {
                postDraftTriggerCard

                preseasonTriggerCard

                weeklyTriggerCard

                weekPreviewTriggerCard

                testSenderCard

                if let result = store.lastTestResult {
                    Text(result)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.hasPrefix("✓") ? XomperColors.successGreen : XomperColors.errorRed)
                        .padding(.horizontal, XomperTheme.Spacing.md)
                }

                filterBar

                if store.isLoading && store.entries.isEmpty {
                    LoadingView(message: "Loading activity…")
                        .padding(.top, XomperTheme.Spacing.xl)
                } else if let error = store.lastError, store.entries.isEmpty {
                    ErrorView(message: error) {
                        Task { await store.refresh(sleeperUserId: callerSleeperId) }
                    }
                } else if store.entries.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "No activity",
                        message: "No push or email sends recorded in the last 7 days for the current filters."
                    )
                    .padding(.top, XomperTheme.Spacing.lg)
                } else {
                    ForEach(store.entries) { entry in
                        activityRow(entry)
                    }
                }
            }
            .padding(.vertical, XomperTheme.Spacing.sm)
            .padding(.bottom, XomperTheme.Spacing.xl)
        }
    }

    // MARK: - Post-Draft AI Review trigger

    private var postDraftTriggerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Post-Draft AI Review")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Text(postDraftStatusLine)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            Toggle(isOn: $store.postDraftDryRun) {
                Text("Dry run (admin-only delivery)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(XomperColors.championGold)
            .disabled(store.isTriggeringPostDraft)

            HStack(spacing: XomperTheme.Spacing.sm) {
                Button {
                    Task { await triggerPostDraft(force: false) }
                } label: {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        if store.isTriggeringPostDraft {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(XomperColors.bgDark)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                        }
                        Text(primaryButtonLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.sm)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .frame(minHeight: 32)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)
                .disabled(store.isTriggeringPostDraft)

                if store.postDraftLatest != nil {
                    Button {
                        Task { await triggerPostDraft(force: true) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                            Text("Regenerate (force)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(XomperColors.championGold)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .frame(minHeight: 32)
                        .overlay(
                            Capsule()
                                .strokeBorder(XomperColors.championGold.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .disabled(store.isTriggeringPostDraft)
                }

                Spacer(minLength: 0)
            }

            if let result = store.postDraftResult {
                Text(postDraftResultLine(result))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.successGreen)
            } else if let error = store.postDraftError {
                Text("✗ \(error.localizedDescription)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.errorRed)
            }

            previewsButton(for: .postDraft)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private var postDraftStatusLine: String {
        guard let latest = store.postDraftLatest else {
            return "No report yet — first run will be dry-run."
        }
        let isDryRun = latest.metadata["dry_run"] == "true"
        let dateStr = formattedShortDate(latest.createdAt)
        if isDryRun {
            return "Last dry-run completed at \(dateStr)."
        } else {
            return "Broadcast on \(dateStr)."
        }
    }

    private var primaryButtonLabel: String {
        if store.postDraftLatest == nil {
            // No prior report — first run is always dry-run.
            return "Generate Dry Run"
        }
        return store.postDraftDryRun ? "Generate Dry Run" : "Generate & Broadcast"
    }

    private func postDraftResultLine(_ result: AIReviewTriggerResponse) -> String {
        if result.dryRun {
            let count = result.deliveryCount
            return "✓ Generated! \(count) dry-run \(count == 1 ? "delivery" : "deliveries") sent."
        } else {
            return "✓ Broadcast complete — \(result.deliveryCount) \(result.deliveryCount == 1 ? "email" : "emails") sent."
        }
    }

    private func triggerPostDraft(force: Bool) async {
        do {
            _ = try await store.triggerPostDraft(
                dryRun: store.postDraftDryRun,
                force: force
            )
        } catch {
            // Error already surfaced via store.postDraftError.
        }
    }

    private func formattedShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Preseason AI Review trigger

    private var preseasonTriggerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Preseason AI Review")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Text(preseasonStatusLine)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            Toggle(isOn: $store.preseasonDryRun) {
                Text("Dry run (admin-only delivery)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(XomperColors.championGold)
            .disabled(store.isTriggeringPreseason)

            HStack(spacing: XomperTheme.Spacing.sm) {
                Button {
                    Task { await triggerPreseason(force: false) }
                } label: {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        if store.isTriggeringPreseason {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(XomperColors.bgDark)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                        }
                        Text(preseasonPrimaryButtonLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.sm)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .frame(minHeight: 32)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)
                .disabled(store.isTriggeringPreseason)

                if store.preseasonLatest != nil {
                    Button {
                        Task { await triggerPreseason(force: true) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                            Text("Regenerate (force)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(XomperColors.championGold)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .frame(minHeight: 32)
                        .overlay(
                            Capsule()
                                .strokeBorder(XomperColors.championGold.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .disabled(store.isTriggeringPreseason)
                }

                Spacer(minLength: 0)
            }

            if let result = store.preseasonResult {
                Text(preseasonResultLine(result))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.successGreen)
            } else if let error = store.preseasonError {
                Text("✗ \(error.localizedDescription)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.errorRed)
            }

            previewsButton(for: .preseason)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private var preseasonStatusLine: String {
        guard let latest = store.preseasonLatest else {
            return "No report yet — first run will be dry-run."
        }
        let isDryRun = latest.metadata["dry_run"] == "true"
        let dateStr = formattedShortDate(latest.createdAt)
        if isDryRun {
            return "Last dry-run completed at \(dateStr)."
        } else {
            return "Broadcast on \(dateStr)."
        }
    }

    private var preseasonPrimaryButtonLabel: String {
        if store.preseasonLatest == nil {
            // No prior report — first run is always dry-run.
            return "Generate Dry Run"
        }
        return store.preseasonDryRun ? "Generate Dry Run" : "Generate & Broadcast"
    }

    private func preseasonResultLine(_ result: AIReviewTriggerResponse) -> String {
        if result.dryRun {
            let count = result.deliveryCount
            return "✓ Generated! \(count) dry-run \(count == 1 ? "delivery" : "deliveries") sent."
        } else {
            return "✓ Broadcast complete — \(result.deliveryCount) \(result.deliveryCount == 1 ? "email" : "emails") sent."
        }
    }

    private func triggerPreseason(force: Bool) async {
        do {
            _ = try await store.triggerPreseason(
                dryRun: store.preseasonDryRun,
                force: force
            )
        } catch {
            // Error already surfaced via store.preseasonError.
        }
    }

    // MARK: - Weekly AI Review trigger

    /// Binding for the "Override week" toggle. Backed by
    /// `store.weeklyWeekOverride` — `nil` means "let the backend
    /// resolve current week", non-nil means "send this week
    /// explicitly". Flipping ON seeds a sensible default (1) so the
    /// stepper has somewhere to start.
    private var weeklyOverrideEnabled: Binding<Bool> {
        Binding(
            get: { store.weeklyWeekOverride != nil },
            set: { newValue in
                if newValue {
                    if store.weeklyWeekOverride == nil {
                        store.weeklyWeekOverride = 1
                    }
                } else {
                    store.weeklyWeekOverride = nil
                }
            }
        )
    }

    /// Binding wrapping the optional `weeklyWeekOverride` for the
    /// Stepper. Stepper only renders when the override toggle is ON,
    /// so a nil read here is treated as 1 defensively.
    private var weeklyWeekBinding: Binding<Int> {
        Binding(
            get: { store.weeklyWeekOverride ?? 1 },
            set: { store.weeklyWeekOverride = $0 }
        )
    }

    private var weeklyTriggerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly AI Review")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Text(weeklyStatusLine)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            Toggle(isOn: $store.weeklyDryRun) {
                Text("Dry run (admin-only delivery)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(XomperColors.championGold)
            .disabled(store.isTriggeringWeekly)

            Toggle(isOn: weeklyOverrideEnabled) {
                Text("Override week (default = current)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(XomperColors.championGold)
            .disabled(store.isTriggeringWeekly)

            if store.weeklyWeekOverride != nil {
                Stepper(value: weeklyWeekBinding, in: 1...18) {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Text("Week")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(XomperColors.textPrimary)
                        Text("\(store.weeklyWeekOverride ?? 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(XomperColors.championGold)
                            .monospacedDigit()
                    }
                }
                .disabled(store.isTriggeringWeekly)
            }

            HStack(spacing: XomperTheme.Spacing.sm) {
                Button {
                    Task { await triggerWeekly(force: false) }
                } label: {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        if store.isTriggeringWeekly {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(XomperColors.bgDark)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                        }
                        Text(weeklyPrimaryButtonLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.sm)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .frame(minHeight: 32)
                    .background(XomperColors.championGold)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)
                .disabled(store.isTriggeringWeekly)

                if store.weeklyLatest != nil {
                    Button {
                        Task { await triggerWeekly(force: true) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                            Text("Regenerate (force)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(XomperColors.championGold)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .frame(minHeight: 32)
                        .overlay(
                            Capsule()
                                .strokeBorder(XomperColors.championGold.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .disabled(store.isTriggeringWeekly)
                }

                Spacer(minLength: 0)
            }

            if let result = store.weeklyResult {
                Text(weeklyResultLine(result))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.successGreen)
            } else if let error = store.weeklyError {
                Text("✗ \(error.localizedDescription)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.errorRed)
            }

            previewsButton(for: .weekly)
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private var weeklyStatusLine: String {
        guard let latest = store.weeklyLatest else {
            return "No report yet — first run will be dry-run."
        }
        let isDryRun = latest.metadata["dry_run"] == "true"
        let dateStr = formattedShortDate(latest.createdAt)
        if isDryRun {
            return "Last dry-run (\(latest.period)) completed at \(dateStr)."
        } else {
            return "Broadcast (\(latest.period)) on \(dateStr)."
        }
    }

    private var weeklyPrimaryButtonLabel: String {
        if store.weeklyLatest == nil {
            // No prior report — first run is always dry-run.
            return "Generate Dry Run"
        }
        return store.weeklyDryRun ? "Generate Dry Run" : "Generate & Broadcast"
    }

    private func weeklyResultLine(_ result: AIReviewTriggerResponse) -> String {
        if result.dryRun {
            let count = result.deliveryCount
            return "✓ Generated! \(count) dry-run \(count == 1 ? "delivery" : "deliveries") sent."
        } else {
            return "✓ Broadcast complete — \(result.deliveryCount) \(result.deliveryCount == 1 ? "email" : "emails") sent."
        }
    }

    private func triggerWeekly(force: Bool) async {
        do {
            _ = try await store.triggerWeekly(
                week: store.weeklyWeekOverride,
                dryRun: store.weeklyDryRun,
                force: force
            )
        } catch {
            // Error already surfaced via store.weeklyError.
        }
    }

    // MARK: - Phase 2 Week Preview trigger

    private var weekPreviewTriggerCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Week Preview (Wed newsletter)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.errorRed)
                Text(weekPreviewStatusLine)
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            Toggle(isOn: $store.weekPreviewDryRun) {
                Text("Dry run (admin-only delivery)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(XomperColors.errorRed)
            .disabled(store.isTriggeringWeekPreview)

            Toggle(isOn: weekPreviewOverrideEnabled) {
                Text("Override week (default = upcoming)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(XomperColors.errorRed)
            .disabled(store.isTriggeringWeekPreview)

            if store.weekPreviewWeekOverride != nil {
                Stepper(value: weekPreviewWeekBinding, in: 1...18) {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        Text("Week")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(XomperColors.textPrimary)
                        Text("\(store.weekPreviewWeekOverride ?? 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(XomperColors.errorRed)
                            .monospacedDigit()
                    }
                }
                .disabled(store.isTriggeringWeekPreview)
            }

            HStack(spacing: XomperTheme.Spacing.sm) {
                Button {
                    Task { await triggerWeekPreview(force: false) }
                } label: {
                    HStack(spacing: XomperTheme.Spacing.xs) {
                        if store.isTriggeringWeekPreview {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(XomperColors.bgDark)
                        } else {
                            Image(systemName: "calendar.badge.clock")
                                .font(.caption2)
                        }
                        Text(weekPreviewPrimaryButtonLabel)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(XomperColors.bgDark)
                    .padding(.horizontal, XomperTheme.Spacing.sm)
                    .padding(.vertical, XomperTheme.Spacing.xs)
                    .frame(minHeight: 32)
                    .background(XomperColors.errorRed)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressableCard)
                .disabled(store.isTriggeringWeekPreview)

                if store.weekPreviewLatest != nil {
                    Button {
                        Task { await triggerWeekPreview(force: true) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                            Text("Regenerate (force)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(XomperColors.errorRed)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .frame(minHeight: 32)
                        .overlay(
                            Capsule()
                                .strokeBorder(XomperColors.errorRed.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.pressableCard)
                    .disabled(store.isTriggeringWeekPreview)
                }

                Spacer(minLength: 0)
            }

            if let result = store.weekPreviewResult {
                Text(weekPreviewResultLine(result))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.successGreen)
            } else if let error = store.weekPreviewError {
                Text("✗ \(error.localizedDescription)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(XomperColors.errorRed)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.errorRed.opacity(0.3), lineWidth: 1)
        )
    }

    private var weekPreviewOverrideEnabled: Binding<Bool> {
        Binding(
            get: { store.weekPreviewWeekOverride != nil },
            set: { newValue in
                if newValue {
                    if store.weekPreviewWeekOverride == nil {
                        store.weekPreviewWeekOverride = 1
                    }
                } else {
                    store.weekPreviewWeekOverride = nil
                }
            }
        )
    }

    private var weekPreviewWeekBinding: Binding<Int> {
        Binding(
            get: { store.weekPreviewWeekOverride ?? 1 },
            set: { store.weekPreviewWeekOverride = $0 }
        )
    }

    private var weekPreviewStatusLine: String {
        if let latest = store.weekPreviewLatest {
            return "Last preview: \(latest.period) · \(formattedShortDate(latest.createdAt))"
        }
        return "No week-preview row yet — fires Wed 9am ET in production."
    }

    private var weekPreviewPrimaryButtonLabel: String {
        if store.isTriggeringWeekPreview {
            return "Firing…"
        }
        return store.weekPreviewLatest == nil ? "Generate" : "Regenerate"
    }

    private func weekPreviewResultLine(_ result: AIReviewTriggerResponse) -> String {
        if result.dryRun {
            return "✓ Dry run complete — delivered to admin only."
        }
        return "✓ Broadcast complete — \(result.deliveryCount) \(result.deliveryCount == 1 ? "email" : "emails") sent."
    }

    private func triggerWeekPreview(force: Bool) async {
        do {
            _ = try await store.triggerWeekPreview(
                week: store.weekPreviewWeekOverride,
                dryRun: store.weekPreviewDryRun,
                force: force
            )
        } catch {
            // Error already surfaced via store.weekPreviewError.
        }
    }

    // MARK: - Preview entry point (F2)

    /// Gold outline capsule shown under each trigger card when
    /// `store.lastPreviewsByType[reportType]` is non-empty. Tapping
    /// pushes the F2 preview screen onto the existing nav stack.
    @ViewBuilder
    private func previewsButton(for reportType: AIReportType) -> some View {
        if let previews = store.lastPreviewsByType[reportType], !previews.isEmpty {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                router.navigate(to: .adminAIReviewPreview(reportType: reportType))
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("View \(previews.count) previews")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(XomperColors.championGold)
                .padding(.horizontal, XomperTheme.Spacing.sm)
                .padding(.vertical, XomperTheme.Spacing.xs)
                .frame(minHeight: 32)
                .overlay(
                    Capsule()
                        .strokeBorder(XomperColors.championGold.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel("View \(previews.count) email previews for \(reportType.displayName)")
            .accessibilityHint("Double tap to review what would be broadcast.")
        }
    }

    // MARK: - Test sender

    private var testSenderCard: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Test sender")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(XomperColors.championGold)
                Text("Fire any production template back to your account. Push titles arrive prefixed with 🧪.")
                    .font(.caption)
                    .foregroundStyle(XomperColors.textSecondary)
            }

            ForEach(AdminTestKind.allCases) { kind in
                HStack(spacing: XomperTheme.Spacing.xs) {
                    Text(kind.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                    Spacer()

                    Button {
                        Task {
                            await store.sendTest(
                                kind: kind,
                                sleeperUserId: callerSleeperId,
                                email: kind.hasEmail ? callerEmail : nil,
                                channels: kind.hasEmail ? ["push", "email"] : ["push"]
                            )
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.hasEmail ? "paperplane.fill" : "iphone.gen3")
                                .font(.caption2)
                            Text(kind.hasEmail ? "Push + email" : "Push")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(XomperColors.bgDark)
                        .padding(.horizontal, XomperTheme.Spacing.sm)
                        .padding(.vertical, XomperTheme.Spacing.xs)
                        .frame(minHeight: 32)
                        .background(XomperColors.championGold)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.pressableCard)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.lg)
                .strokeBorder(XomperColors.championGold.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Activity · last 7 days")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(XomperColors.textMuted)

            HStack(spacing: XomperTheme.Spacing.sm) {
                Picker("Channel", selection: $store.filterKind) {
                    ForEach(AdminStore.KindFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Status", selection: $store.filterStatus) {
                    ForEach(AdminStore.StatusFilter.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }
            .onChange(of: store.filterKind) { _, _ in
                Task { await store.refresh(sleeperUserId: callerSleeperId) }
            }
            .onChange(of: store.filterStatus) { _, _ in
                Task { await store.refresh(sleeperUserId: callerSleeperId) }
            }
        }
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    // MARK: - Activity row

    private func activityRow(_ entry: AdminNotificationLogEntry) -> some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            HStack(spacing: XomperTheme.Spacing.xs) {
                Image(systemName: entry.isPush ? "iphone.gen3" : "envelope.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.isPush ? Color.cyan : XomperColors.championGold)
                Text(entry.isPush ? "PUSH" : "EMAIL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(XomperColors.textSecondary)
                    .tracking(0.5)
                Text(entry.isSuccess ? "✓" : "✗")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(entry.isSuccess ? XomperColors.successGreen : XomperColors.errorRed)
                Spacer()
                Text(formattedTimestamp(entry.date))
                    .font(.caption2)
                    .foregroundStyle(XomperColors.textMuted)
                    .monospacedDigit()
            }

            if entry.isPush {
                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                }
                if let body = entry.body, !body.isEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(2)
                }
                if let userId = entry.userId, !userId.isEmpty {
                    Text("user: \(userId)")
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .monospacedDigit()
                }
            } else {
                if let subject = entry.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                        .lineLimit(1)
                }
                if let recipient = entry.recipient, !recipient.isEmpty {
                    Text(recipient)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(1)
                }
                if let snippet = entry.bodySnippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption2)
                        .foregroundStyle(XomperColors.textMuted)
                        .lineLimit(2)
                }
            }

            if let err = entry.error, !err.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(XomperColors.errorRed)
                    .lineLimit(2)
            }
        }
        .padding(XomperTheme.Spacing.md)
        .background(XomperColors.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                .strokeBorder(
                    entry.isSuccess ? Color.clear : XomperColors.errorRed.opacity(0.4),
                    lineWidth: entry.isSuccess ? 0 : 1
                )
        )
        .padding(.horizontal, XomperTheme.Spacing.md)
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm:ss a"
        return formatter.string(from: date)
    }
}
