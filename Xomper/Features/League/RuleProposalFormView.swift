import SwiftUI

struct RuleProposalFormView: View {
    var rulesStore: RulesStore
    let leagueId: String
    let leagueName: String
    let proposerName: String
    let totalRosters: Int
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var description = ""
    @State private var showError = false
    @State private var errorMessage = ""

    @FocusState private var focusedField: Field?

    private enum Field {
        case title, description
    }

    private var isValid: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: XomperTheme.Spacing.lg) {
                    instructionText
                    titleField
                    descriptionField
                }
                .padding(.horizontal, XomperTheme.Spacing.md)
                .padding(.vertical, XomperTheme.Spacing.md)
            }
            .background(XomperColors.bgDark.ignoresSafeArea())
            .navigationTitle("New Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundStyle(XomperColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    submitButton
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var instructionText: some View {
        Text("Propose a rule change for the league. All members will be notified and can vote.")
            .font(.subheadline)
            .foregroundStyle(XomperColors.textSecondary)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Title")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textMuted)

            TextField("Rule title...", text: $title)
                .font(.body)
                .foregroundStyle(XomperColors.textPrimary)
                .padding(XomperTheme.Spacing.md)
                .background(XomperColors.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .description }
                .accessibilityLabel("Proposal title")

            if !title.isEmpty && title.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 {
                Text("Title must be at least 3 characters")
                    .font(.caption2)
                    .foregroundStyle(XomperColors.errorRed)
            }
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: XomperTheme.Spacing.xs) {
            Text("Description")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(XomperColors.textMuted)

            TextField("Describe the rule change...", text: $description, axis: .vertical)
                .font(.body)
                .foregroundStyle(XomperColors.textPrimary)
                .lineLimit(3...8)
                .padding(XomperTheme.Spacing.md)
                .background(XomperColors.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: XomperTheme.CornerRadius.md))
                .focused($focusedField, equals: .description)
                .submitLabel(.done)
                .accessibilityLabel("Proposal description")
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            if rulesStore.isSubmitting {
                ProgressView()
                    .tint(XomperColors.championGold)
            } else {
                Text("Submit")
                    .fontWeight(.semibold)
                    .foregroundStyle(isValid ? XomperColors.championGold : XomperColors.textMuted)
            }
        }
        .disabled(!isValid || rulesStore.isSubmitting)
        .accessibilityLabel("Submit proposal")
    }

    // MARK: - Submit

    private func submit() async {
        let generator = UINotificationFeedbackGenerator()

        let success = await rulesStore.createProposal(
            leagueId: leagueId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            leagueName: leagueName,
            proposerName: proposerName,
            totalRosters: totalRosters
        )

        if success {
            generator.notificationOccurred(.success)
            isPresented = false
        } else {
            generator.notificationOccurred(.error)
            errorMessage = rulesStore.error?.localizedDescription ?? "Failed to submit proposal."
            showError = true
        }
    }
}
