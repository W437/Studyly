import SwiftUI

extension View {
    /// Harness (DEBUG): `CRAMLESS_SCROLL=<section>` scrolls a long screen to one of its sections once it appears, so
    /// headless screenshots can show the lower half. Sections: Library `bring`; course `exams`, `topics`, `sources`,
    /// `questions`; source `questions`; page `questions`; exam `path`, `topics`, `plan`, `materials`; progress
    /// `streak`, `week`, `memory`, `topics`; streak `freezes`. A no-op in release builds.
    func harnessScroll(_ proxy: ScrollViewProxy) -> some View {
        #if DEBUG
        return task {
            guard let section = TestHarness.value("CRAMLESS_SCROLL") else { return }
            try? await Task.sleep(for: .milliseconds(700))
            proxy.scrollTo(section, anchor: .top)
        }
        #else
        return self
        #endif
    }
}
