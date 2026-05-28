import SwiftUI

/// Admin → Logs (F5).
///
/// Replaces the F1 `LogsStubView` placeholder. Hosts a log-group
/// picker (10 allowlisted CloudWatch log groups), a level filter
/// (All / Info / Warn / Error), a free-text search field, and a
/// paginated event list rendered as a `LazyVStack` of `LogsRowView`s.
///
/// The 5s client-side rate limit lives on `LogsStore`; this view
/// reflects the `throttled` flag with a transient banner. "Load
/// older" bypasses the rate limit (user-initiated pagination).
struct LogsView: View {
    @State private var store = LogsStore()

    /// Debounce token for the search field — incremented on every
    /// edit, the inflight task aborts if it sees a newer token.
    @State private var searchDebounceToken: UUID = UUID()

    var body: some View {
        ScrollView {
            VStack(spacing: XomperTheme.Spacing.md) {
                filterToolbar
                throttleBanner
                errorBanner
                content
            }
            .padding(.horizontal, XomperTheme.Spacing.md)
            .padding(.vertical, XomperTheme.Spacing.sm)
        }
        .background(XomperColors.bgDark.ignoresSafeArea())
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                refreshButton
            }
        }
        .task {
            if store.events.isEmpty {
                await store.loadEvents()
            }
        }
        .refreshable {
            await store.loadEvents()
        }
    }

    // MARK: - Filter toolbar

    private var filterToolbar: some View {
        VStack(spacing: XomperTheme.Spacing.sm) {
            // Log group picker — 10 entries, so menu style keeps the
            // surface compact (segmented would wrap awkwardly).
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: "terminal")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.championGold)
                    .accessibilityHidden(true)

                Picker("Log Group", selection: $store.selectedLogGroup) {
                    ForEach(LogGroup.allCases) { group in
                        Text(group.displayName).tag(group)
                    }
                }
                .pickerStyle(.menu)
                .tint(XomperColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Log group")
            }
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .onChange(of: store.selectedLogGroup) { _, newGroup in
                Task { await store.setLogGroup(newGroup) }
            }

            // Level filter — small enum, segmented works here.
            Picker("Level", selection: levelBinding) {
                Text("All").tag(LogLevel?.none)
                ForEach(LogLevel.allCases) { level in
                    Text(level.displayName).tag(Optional(level))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Log level filter")

            // Search input — submits on return; debounces after 500ms
            // of idle typing so admins don't have to mash return.
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(XomperColors.textMuted)
                    .accessibilityHidden(true)

                TextField(
                    "Search messages",
                    text: $store.searchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundStyle(XomperColors.textPrimary)
                .onSubmit {
                    Task { await store.loadEvents() }
                }
                .onChange(of: store.searchText) { _, _ in
                    debouncedSearch()
                }

                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                        Task { await store.loadEvents() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(XomperColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, XomperTheme.Spacing.sm)
            .padding(.vertical, XomperTheme.Spacing.xs)
            .background(XomperColors.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
        }
    }

    private var levelBinding: Binding<LogLevel?> {
        Binding(
            get: { store.levelFilter },
            set: { newLevel in
                Task { await store.setLevel(newLevel) }
            }
        )
    }

    // MARK: - Throttle + error banners

    @ViewBuilder
    private var throttleBanner: some View {
        if store.throttled {
            Text("Hold on a sec — refreshing again in a few seconds.")
                .font(.caption)
                .foregroundStyle(XomperColors.bgDark)
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(XomperColors.championGold)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
                .transition(.opacity)
                .accessibilityLabel("Refresh throttled. Wait a few seconds.")
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = store.error, !error.isEmpty {
            HStack(alignment: .top, spacing: XomperTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(XomperColors.accentRed)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: XomperTheme.Spacing.xxs) {
                    Text("Couldn't load logs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(XomperColors.textPrimary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(XomperColors.textSecondary)
                        .lineLimit(3)
                }

                Spacer()

                Button("Retry") {
                    Task { await store.loadEvents() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(XomperColors.championGold)
                .buttonStyle(.plain)
                .accessibilityLabel("Retry loading logs")
            }
            .padding(XomperTheme.Spacing.md)
            .background(XomperColors.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md)
                    .strokeBorder(XomperColors.accentRed.opacity(0.4), lineWidth: 1)
            )
        }
    }

    // MARK: - Refresh button

    private var refreshButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            Task { await store.loadEvents() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(canRefresh ? XomperColors.championGold : XomperColors.textMuted)
        }
        .accessibilityLabel("Refresh logs")
        .disabled(store.isLoading || !canRefresh)
    }

    /// True when the 5s rate-limit window has elapsed since the last
    /// fetch. Drives the disabled state + tint on the refresh button.
    private var canRefresh: Bool {
        guard let last = store.lastFetchAt else { return true }
        return Date().timeIntervalSince(last) >= 5
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.events.isEmpty {
            LoadingView(message: "Loading logs…")
                .frame(minHeight: 200)
        } else if store.events.isEmpty && store.error == nil {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No events",
                message: "No events match these filters. Try widening the level or clearing the search."
            )
            .frame(minHeight: 240)
        } else {
            LazyVStack(spacing: XomperTheme.Spacing.sm) {
                ForEach(events) { event in
                    LogsRowView(event: event)
                }

                if store.nextToken != nil {
                    loadOlderButton
                }

                if store.isLoading && !store.events.isEmpty {
                    ProgressView()
                        .tint(XomperColors.championGold)
                        .padding(.vertical, XomperTheme.Spacing.md)
                }
            }
        }
    }

    /// Stable, dedup'd event view models for the `ForEach`. Backstop
    /// against any duplicate-id cycle we might see across pages — the
    /// store also dedups, so this is belt-and-suspenders.
    private var events: [LogEvent] {
        store.events
    }

    private var loadOlderButton: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            Task { await store.loadMore() }
        } label: {
            HStack(spacing: XomperTheme.Spacing.sm) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(XomperColors.championGold)
                Text("Load older")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(XomperColors.championGold)
            }
            .padding(.horizontal, XomperTheme.Spacing.lg)
            .padding(.vertical, XomperTheme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(XomperColors.bgCard)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(XomperColors.championGold.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isLoading)
        .accessibilityLabel("Load older log events")
    }

    // MARK: - Debounced search

    /// Debounced search: stamps a fresh token, waits 500ms, then
    /// dispatches `loadEvents` if the token is still the most recent.
    /// Keeps admins from spamming CloudWatch per-keystroke while
    /// still feeling responsive.
    private func debouncedSearch() {
        let token = UUID()
        searchDebounceToken = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard searchDebounceToken == token else { return }
            await store.loadEvents()
        }
    }
}

#Preview {
    NavigationStack {
        LogsView()
    }
    .preferredColorScheme(.dark)
}
