import SwiftUI

/// Admin → Announcements → Edit (announcements feature).
///
/// Typed form for one `league_announcements` row. When `id == nil`
/// the form opens empty for a create; otherwise it hydrates from the
/// matching row in `store.adminAnnouncements`.
///
/// Allowlisted fields per the backend handler: title, body, priority,
/// expires_at, is_active, display_order. On Save:
/// - Create path: calls `store.create(...)`.
/// - Update path: sends only the fields that actually changed (so the
///   backend's `admin_audit` diff stays tight).
///
/// Validation:
/// - Title + body must be non-empty after trimming.
/// - `display_order` is a non-negative `Stepper`.
struct AnnouncementEditView: View {
    let id: UUID?
    var store: AnnouncementsStore
    var router: AppRouter

    @Environment(\.dismiss) private var dismiss

    @State private var titleDraft: String = ""
    @State private var bodyDraft: String = ""
    @State private var priorityDraft: LeagueAnnouncement.Priority = .info
    @State private var isActiveDraft: Bool = true
    @State private var displayOrderDraft: Int = 0
    @State private var hasExpiry: Bool = false
    @State private var expiresAtDraft: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var didPopulateFromStore: Bool = false
    @State private var isSaving: Bool = false
    @State private var inlineError: String?

    var body: some View {
        content
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle(isCreate ? "New Announcement" : "Edit Announcement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { saveToolbar }
            .task {
                if id != nil && store.adminAnnouncements.isEmpty {
                    await store.loadAdmin()
                }
                populateDraftIfNeeded()
            }
            .onChange(of: store.adminAnnouncements) { _, _ in
                populateDraftIfNeeded()
            }
            .onDisappear {
                store.clearLastWriteError()
            }
    }

    private var isCreate: Bool { id == nil }

    private var resolvedRow: LeagueAnnouncement? {
        guard let id else { return nil }
        return store.adminAnnouncements.first(where: { $0.id == id })
    }

    // MARK: - Form

    @ViewBuilder
    private var content: some View {
        if !isCreate && resolvedRow == nil && store.isLoadingAdmin {
            LoadingView(message: "Loading announcement…")
        } else if !isCreate && resolvedRow == nil {
            EmptyStateView(
                icon: "megaphone.fill",
                title: "Announcement not found",
                message: "We couldn't find that announcement. Pull to refresh and try again."
            )
        } else {
            Form {
                Section("Content") {
                    TextField("Title", text: $titleDraft)
                        .textInputAutocapitalization(.sentences)

                    VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
                        Text("Body")
                            .font(.caption)
                            .foregroundStyle(XomperColors.textSecondary)
                        TextEditor(text: $bodyDraft)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .background(XomperColors.bgCard.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.sm))
                        Text("Supports **bold** markdown and [links](https://example.com).")
                            .font(.caption2)
                            .foregroundStyle(XomperColors.textMuted)
                    }
                }

                Section("Priority & Visibility") {
                    Picker("Priority", selection: $priorityDraft) {
                        Text("Info").tag(LeagueAnnouncement.Priority.info)
                        Text("Critical").tag(LeagueAnnouncement.Priority.critical)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Active", isOn: $isActiveDraft)
                        .tint(XomperColors.successGreen)

                    Stepper(
                        "Display order: \(displayOrderDraft)",
                        value: $displayOrderDraft,
                        in: 0...999
                    )
                }

                Section("Expiry") {
                    Toggle("Has expiry", isOn: $hasExpiry)
                        .tint(XomperColors.championGold)
                    if hasExpiry {
                        DatePicker(
                            "Expires at",
                            selection: $expiresAtDraft,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }

                if let inlineError {
                    Section {
                        Label(inlineError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(XomperColors.errorRed)
                            .font(.callout)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(XomperColors.bgDark)
        }
    }

    // MARK: - Save toolbar

    @ToolbarContentBuilder
    private var saveToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await save() }
            } label: {
                if isSaving {
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
            .accessibilityHint(canSave ? "Save changes" : "Fill in title and body to enable saving")
        }
    }

    // MARK: - Draft hydration

    private func populateDraftIfNeeded() {
        guard !didPopulateFromStore else { return }
        if isCreate {
            didPopulateFromStore = true
            return
        }
        guard let row = resolvedRow else { return }
        titleDraft = row.title
        bodyDraft = row.body
        priorityDraft = row.priority
        isActiveDraft = row.isActive
        displayOrderDraft = row.displayOrder
        if let expiresAt = row.expiresAt {
            hasExpiry = true
            expiresAtDraft = expiresAt
        } else {
            hasExpiry = false
        }
        didPopulateFromStore = true
    }

    // MARK: - Validation

    private var titleTrimmed: String {
        titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bodyTrimmed: String {
        bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        guard !titleTrimmed.isEmpty, !bodyTrimmed.isEmpty else { return false }
        if isCreate { return true }
        return !changedFields.isEmpty
    }

    // MARK: - Diff for update

    private var changedFields: [String: AdminFieldValue] {
        guard let row = resolvedRow else { return [:] }
        var diff: [String: AdminFieldValue] = [:]

        if titleTrimmed != row.title {
            diff["title"] = .string(titleTrimmed)
        }
        if bodyTrimmed != row.body {
            diff["body"] = .string(bodyTrimmed)
        }
        if priorityDraft != row.priority {
            diff["priority"] = .string(priorityDraft.rawValue)
        }
        if isActiveDraft != row.isActive {
            diff["is_active"] = .bool(isActiveDraft)
        }
        if displayOrderDraft != row.displayOrder {
            diff["display_order"] = .int(displayOrderDraft)
        }
        // expires_at — three transitions to consider:
        //   on → off  → send null
        //   off → on  → send new date string
        //   on → on   → send new date string IF it changed
        let originalExpiry = row.expiresAt
        if hasExpiry {
            if originalExpiry == nil || originalExpiry != expiresAtDraft {
                diff["expires_at"] = .string(Self.iso8601(expiresAtDraft))
            }
        } else if originalExpiry != nil {
            diff["expires_at"] = .null
        }
        return diff
    }

    // MARK: - Save

    private func save() async {
        guard canSave else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        isSaving = true
        inlineError = nil
        defer { isSaving = false }

        do {
            if isCreate {
                _ = try await store.create(
                    title: titleTrimmed,
                    body: bodyTrimmed,
                    priority: priorityDraft,
                    expiresAt: hasExpiry ? expiresAtDraft : nil,
                    isActive: isActiveDraft,
                    displayOrder: displayOrderDraft
                )
            } else if let id {
                _ = try await store.update(id: id, fields: changedFields)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            inlineError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: - ISO helper

    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func iso8601(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }
}
