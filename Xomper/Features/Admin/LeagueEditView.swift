import SwiftUI

/// Admin → Tables → Leagues → Edit (F4).
///
/// Typed form for a single `whitelisted_leagues` row. Allowlisted
/// fields per the backend handler: league_name + is_active +
/// is_dynasty + has_taxi. `whitelisted_league_id` surfaces as a
/// read-only LabeledContent (immutable join key — admins need to
/// see it but can't edit it).
///
/// Submit sends only the fields the admin actually changed.
struct LeagueEditView: View {
    let leagueId: String
    var store: AdminTablesStore
    var router: AppRouter

    @Environment(\.dismiss) private var dismiss

    @State private var leagueNameDraft: String = ""
    @State private var isActiveDraft: Bool = false
    @State private var isDynastyDraft: Bool = false
    @State private var hasTaxiDraft: Bool = false
    @State private var didPopulateFromStore = false

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Edit League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { saveToolbar }
            .task {
                if store.leagues.isEmpty {
                    await store.loadLeagues()
                }
                populateDraftIfNeeded()
            }
            .onChange(of: store.leagues) { _, _ in
                populateDraftIfNeeded()
            }
            .onDisappear {
                store.clearLastSaveResult()
            }
    }

    private var resolvedLeague: WhitelistedLeague? {
        store.leagues.first(where: { $0.leagueId == leagueId })
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingLeagues && resolvedLeague == nil {
            LoadingView(message: "Loading league…")
        } else if let league = resolvedLeague {
            Form {
                Section("League") {
                    LabeledContent("League ID", value: league.leagueId)
                        .foregroundStyle(XomperColors.textSecondary)

                    LabeledContent("Season", value: league.season)
                        .foregroundStyle(XomperColors.textSecondary)

                    TextField("League name", text: $leagueNameDraft)
                        .textInputAutocapitalization(.words)

                    if leagueNameTrimmedEmpty {
                        Text("League name can't be empty")
                            .font(.caption)
                            .foregroundStyle(XomperColors.errorRed)
                    }
                }

                Section("Settings") {
                    Toggle("Active", isOn: $isActiveDraft)
                        .tint(XomperColors.successGreen)
                    Toggle("Dynasty", isOn: $isDynastyDraft)
                        .tint(XomperColors.championGold)
                    Toggle("Has taxi", isOn: $hasTaxiDraft)
                        .tint(XomperColors.championGold)
                }

                if let success = store.lastSaveSuccess, !success.isEmpty {
                    Section {
                        Label("Saved", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(XomperColors.successGreen)
                    }
                }

                if let error = store.lastSaveError, !error.isEmpty {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(XomperColors.errorRed)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(XomperColors.bgDark)
        } else {
            EmptyStateView(
                icon: "building.2.crop.circle.badge.questionmark",
                title: "League not found",
                message: "We couldn't find that league. Pull to refresh the list and try again."
            )
        }
    }

    // MARK: - Save toolbar

    @ToolbarContentBuilder
    private var saveToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await save() }
            } label: {
                if store.isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(XomperColors.championGold)
                } else {
                    Text("Save")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(canSave ? XomperColors.championGold : XomperColors.textMuted)
                }
            }
            .disabled(!canSave)
            .accessibilityHint(canSave ? "Save changes" : "Make a valid change to enable saving")
        }
    }

    // MARK: - Draft management

    private func populateDraftIfNeeded() {
        guard !didPopulateFromStore, let league = resolvedLeague else { return }
        leagueNameDraft = league.leagueName
        isActiveDraft = league.isActive
        isDynastyDraft = league.isDynasty
        hasTaxiDraft = league.hasTaxi
        didPopulateFromStore = true
    }

    // MARK: - Validation + diff

    private var leagueNameTrimmedEmpty: Bool {
        leagueNameDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var changedFields: [String: AdminFieldValue] {
        guard let league = resolvedLeague else { return [:] }
        var diff: [String: AdminFieldValue] = [:]

        let trimmedName = leagueNameDraft.trimmingCharacters(in: .whitespaces)
        if trimmedName != league.leagueName {
            diff["league_name"] = .string(trimmedName)
        }
        if isActiveDraft != league.isActive {
            diff["is_active"] = .bool(isActiveDraft)
        }
        if isDynastyDraft != league.isDynasty {
            diff["is_dynasty"] = .bool(isDynastyDraft)
        }
        if hasTaxiDraft != league.hasTaxi {
            diff["has_taxi"] = .bool(hasTaxiDraft)
        }
        return diff
    }

    private var canSave: Bool {
        guard !store.isSaving else { return false }
        guard didPopulateFromStore else { return false }
        guard !leagueNameTrimmedEmpty else { return false }
        return !changedFields.isEmpty
    }

    // MARK: - Save

    private func save() async {
        guard canSave else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        await store.updateLeague(leagueId: leagueId, fields: changedFields)
        if store.lastSaveError == nil {
            dismiss()
        }
    }
}
