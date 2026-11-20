// macOS application presentation and coordination for setup presentation.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

import SwiftUI

struct SetupPresentation: ViewModifier {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var setup: SetupCoordinator
    let openDevices: () -> Void
    /// Composes the platform view from its current observable state and action bindings.
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $setup.isPresented) {
                SetupGuideView(preferencesStore: preferencesStore, setup: setup, openDevices: openDevices)
            }
            .task { setup.offerFirstRun(hasSavedPhone: !preferencesStore.preferences.rememberedPhones.isEmpty) }
    }
}
