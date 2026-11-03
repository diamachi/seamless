import SwiftUI

struct SetupPresentation: ViewModifier {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var setup: SetupCoordinator
    let openDevices: () -> Void
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $setup.isPresented) {
                SetupGuideView(preferencesStore: preferencesStore, setup: setup, openDevices: openDevices)
            }
            .task { setup.offerFirstRun(hasSavedPhone: !preferencesStore.preferences.rememberedPhones.isEmpty) }
    }
}
