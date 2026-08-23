import SwiftUI

/// The upgrade, as a sheet, put in front of somebody who has just walked into a
/// locked door.
///
/// Everything it shows lives in `PlusPurchaseView`, which is also the Plus tab
/// and the last page of the intake. This is the presentation, not the pitch:
/// a navigation bar, a way out, and a dismissal once the purchase lands.
///
/// Weekly leads, which is unusual and deliberate. Almost every subscription app
/// leads with an annual plan because almost every subscription app is used for
/// years; this one is used for six to thirteen weeks and is then genuinely
/// finished. A weekly price is the honest one for a need that ends, and lifetime
/// sits underneath because the document vault is the part that does not.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlusPurchaseView(placement: .sheet) { dismiss() }
                .navigationTitle("Baby Docs Plus")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    PaywallView()
}
