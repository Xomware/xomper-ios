import SwiftUI

/// Admin → Tables → Users → Edit (F4).
///
/// Typed form for a single `whitelisted_users` row. Allowlisted
/// fields per the backend handler: email + display_name + is_admin +
/// is_active. Submit sends only the fields that actually changed —
/// the backend writes one `admin_audit` row with the field-level
/// diff.
///
/// Validation:
/// - Email matches a simple RFC 5322 regex (same one the F1 backend
///   handler uses). Inline error blocks Save.
/// - Display name must be non-empty after trimming whitespace.
struct UserEditView: View {
    let userId: String
    var store: AdminTablesStore
    var router: AppRouter

    @Environment(\.dismiss) private var dismiss

    @State private var emailDraft: String = ""
    @State private var displayNameDraft: String = ""
    @State private var isAdminDraft: Bool = false
    @State private var isActiveDraft: Bool = false
    @State private var didPopulateFromStore = false

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("Edit User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { saveToolbar }
            .task {
                if store.users.isEmpty {
                    await store.loadUsers()
                }
                populateDraftIfNeeded()
            }
            .onChange(of: store.users) { _, _ in
                populateDraftIfNeeded()
            }
            .onDisappear {
                store.clearLastSaveResult()
            }
    }

    private var resolvedUser: WhitelistedUser? {
        store.users.first(where: { $0.updateKey == userId })
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoadingUsers && resolvedUser == nil {
            LoadingView(message: "Loading user…")
        } else if let user = resolvedUser {
            Form {
                Section("Identity") {
                    LabeledContent("Sleeper ID", value: user.sleeperUserId ?? "—")
                        .foregroundStyle(XomperColors.textSecondary)

                    TextField("Email", text: $emailDraft)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if !emailIsValid {
                        Text("Enter a valid email address")
                            .font(.caption)
                            .foregroundStyle(XomperColors.errorRed)
                    }

                    TextField("Display name", text: $displayNameDraft)
                        .textInputAutocapitalization(.words)

                    if displayNameTrimmedEmpty {
                        Text("Display name can't be empty")
                            .font(.caption)
                            .foregroundStyle(XomperColors.errorRed)
                    }
                }

                Section("Permissions") {
                    Toggle("Admin", isOn: $isAdminDraft)
                        .tint(XomperColors.championGold)
                    Toggle("Active", isOn: $isActiveDraft)
                        .tint(XomperColors.successGreen)
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
                icon: "person.fill.questionmark",
                title: "User not found",
                message: "We couldn't find that user. Pull to refresh the list and try again."
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
        guard !didPopulateFromStore, let user = resolvedUser else { return }
        emailDraft = user.email
        displayNameDraft = user.displayName ?? ""
        isAdminDraft = user.isAdmin
        isActiveDraft = user.isActive
        didPopulateFromStore = true
    }

    // MARK: - Validation + diff

    private var emailIsValid: Bool {
        AdminValidation.isValidEmail(emailDraft)
    }

    private var displayNameTrimmedEmpty: Bool {
        displayNameDraft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var changedFields: [String: AdminFieldValue] {
        guard let user = resolvedUser else { return [:] }
        var diff: [String: AdminFieldValue] = [:]

        let trimmedEmail = emailDraft.trimmingCharacters(in: .whitespaces)
        let trimmedName = displayNameDraft.trimmingCharacters(in: .whitespaces)

        if trimmedEmail != user.email {
            diff["email"] = .string(trimmedEmail)
        }
        if trimmedName != (user.displayName ?? "") {
            diff["display_name"] = .string(trimmedName)
        }
        if isAdminDraft != user.isAdmin {
            diff["is_admin"] = .bool(isAdminDraft)
        }
        if isActiveDraft != user.isActive {
            diff["is_active"] = .bool(isActiveDraft)
        }
        return diff
    }

    private var canSave: Bool {
        guard !store.isSaving else { return false }
        guard didPopulateFromStore else { return false }
        guard emailIsValid, !displayNameTrimmedEmpty else { return false }
        return !changedFields.isEmpty
    }

    // MARK: - Save

    private func save() async {
        guard canSave else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        await store.updateUser(userId: userId, fields: changedFields)
        if store.lastSaveError == nil {
            // Dismiss back to the users list on success — the list is
            // mutated in place so the next render reflects the change.
            dismiss()
        }
    }
}

// MARK: - Validation helper

/// Shared validation primitives for the F4 admin edit forms. Email
/// regex mirrors what the backend handler enforces — the iOS form
/// just gives faster feedback. Server-side allowlist + regex is the
/// hard backstop.
enum AdminValidation {
    /// Simplified RFC 5322 email regex. Same shape the F1 backend
    /// handler uses for the test-email recipient guard.
    static let emailRegex = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#

    static func isValidEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: emailRegex, options: .regularExpression) != nil
    }
}
