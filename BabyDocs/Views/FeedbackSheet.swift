import SwiftUI
import UIKit

/// Support, and only support.
///
/// This used to be the second step of an enjoyment gate: a question that sent
/// happy people to the App Store and unhappy people here. That is the pattern
/// App Review forbids, so the branch is gone and what is left is the half that
/// was always worth having. Anyone can open this at any time, whatever they
/// think of the app, and nothing in it leads to a rating.
///
/// Styled like the rest of the app rather than like a promotion: no gradient, no
/// coloured hero. Colour in Baby Docs means one thing, how close a door is to
/// closing, and a feedback form is not a closing door.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing) {
                    Text("A rule that was wrong for your state, a deadline we do not have, a link that went nowhere. Whatever it is, it goes straight to the person who writes the rules.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $feedbackText)
                        .frame(minHeight: 150)
                        .padding(AppTheme.tightSpacing)
                        .background(
                            AppTheme.surface,
                            in: AppTheme.cardShape
                        )
                        .focused($feedbackFocused)
                        .accessibilityLabel("Feedback")
                        .accessibilityHint("Describe what is missing or incorrect")

                    Text("This opens your mail app with a draft. Nothing is sent from inside Baby Docs, and nothing about your household goes with it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Send feedback", action: sendFeedback)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .disabled(trimmedFeedback.isEmpty)
                }
                .padding(.horizontal, AppTheme.margin + 8)
                .padding(.bottom, AppTheme.looseSpacing)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Tell us what is missing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedFeedback: String {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendFeedback() {
        guard !trimmedFeedback.isEmpty, let url = Self.feedbackMailURL(body: trimmedFeedback) else { return }
        UIApplication.shared.open(url)
        dismiss()
    }

    /// A `mailto:` draft rather than an in-app form, so feedback needs no
    /// endpoint and this app keeps having no server.
    static func feedbackMailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "jackwallner+babydocs@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Baby Docs feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        FeedbackSheet()
    }
}
