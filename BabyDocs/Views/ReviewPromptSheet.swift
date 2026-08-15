import SwiftUI
import UIKit

/// Lets Settings open the funnel without going through passive eligibility, and
/// keeps the sheet itself owned by one place so two triggers cannot stack two
/// sheets on top of each other.
@MainActor
@Observable
final class ReviewPromptCoordinator {
    static let shared = ReviewPromptCoordinator()

    enum Presentation {
        case enjoymentPrompt
        case feedbackOnly
    }

    var pendingPresentation: Presentation?

    private init() {}

    func requestEnjoymentPrompt() {
        pendingPresentation = .enjoymentPrompt
    }

    func requestFeedback() {
        pendingPresentation = .feedbackOnly
    }

    func clear() {
        pendingPresentation = nil
    }
}

/// Returned when the sheet closes, so the host knows whether to fire the native
/// `requestReview()` and which cooldown the tracker is already in.
enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case feedbackSubmitted
    case openedWriteReview
    /// Said yes, then closed the pitch without opening the store. The host may
    /// call `requestReview()` once, which Apple may or may not honour.
    case enjoyedMaybeLater
}

/// The enjoyment gate.
///
/// Three steps, and the branch is the entire point: nobody is sent to the App
/// Store without first saying the app is working for them, and anybody who says
/// it is not gets a mail draft instead of a rating box. Apple's
/// `requestReview()` is only ever reached down the yes branch.
///
/// Styled like the rest of the app rather than like a promotion: no gradient, no
/// coloured hero. Colour in Baby Docs means one thing, how close a door is to
/// closing, and a review ask is not a closing door.
struct ReviewPromptSheet: View {
    enum Step {
        case enjoyment
        case reviewPitch
        case feedback
    }

    let initialStep: Step
    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    init(initialStep: Step = .enjoyment, onFinish: @escaping (ReviewPromptDismissOutcome) -> Void) {
        self.initialStep = initialStep
        self.onFinish = onFinish
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .enjoyment: enjoymentContent
                case .reviewPitch: reviewPitchContent
                case .feedback: feedbackContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { handleNotNow() }
                }
            }
        }
        .presentationDetents(step == .feedback ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var navigationTitle: String {
        switch step {
        case .enjoyment: "Is this helping?"
        case .reviewPitch: "One favour"
        case .feedback: "Tell us what is missing"
        }
    }

    private var enjoymentContent: some View {
        VStack(spacing: AppTheme.looseSpacing) {
            glyph("checkmark.seal")

            Text("You have got paperwork in before the date closed. That is the whole job, and it is worth knowing whether Baby Docs is actually the reason.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: AppTheme.spacing) {
                Button("Yes, it is helping") { step = .reviewPitch }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                Button("Not really") { step = .feedback }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, AppTheme.margin + 8)
        .padding(.bottom, AppTheme.looseSpacing)
    }

    private var reviewPitchContent: some View {
        VStack(spacing: AppTheme.spacing) {
            glyph("star")

            Text("Baby Docs is written by one person, has no account and no server, and every deadline in it is free. The one thing that decides whether another family finds it is the App Store page.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("A short, honest review takes about a minute.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: AppTheme.spacing) {
                Button("Write a review") {
                    ReviewPromptTracker.markOpenedWriteReview()
                    UIApplication.shared.open(AppStoreReviewLinks.writeReviewURL)
                    finish(.openedWriteReview)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button("Maybe later") {
                    ReviewPromptTracker.markSoftDeferred()
                    finish(.enjoyedMaybeLater)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, AppTheme.margin + 8)
        .padding(.bottom, AppTheme.looseSpacing)
    }

    private var feedbackContent: some View {
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
                    in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                )
                .focused($feedbackFocused)

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
        .onAppear { feedbackFocused = true }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 40, weight: .regular))
            .foregroundStyle(.secondary)
            .padding(.top, AppTheme.spacing)
    }

    private var trimmedFeedback: String {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleNotNow() {
        ReviewPromptTracker.markShown()
        finish(.notNow)
    }

    private func sendFeedback() {
        guard !trimmedFeedback.isEmpty, let url = Self.feedbackMailURL(body: trimmedFeedback) else { return }
        ReviewPromptTracker.markFeedbackSubmitted()
        UIApplication.shared.open(url)
        finish(.feedbackSubmitted)
    }

    private func finish(_ outcome: ReviewPromptDismissOutcome) {
        onFinish(outcome)
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
        ReviewPromptSheet { _ in }
    }
}
