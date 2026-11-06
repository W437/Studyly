import SwiftUI

extension View {
    /// Harness (DEBUG): `CRAMLESS_SCROLL=<section>` scrolls a long screen to one of its sections once it appears, so
    /// headless screenshots can show the lower half. Sections: Library `recent`, `bring`; source `questions`; page `questions`; exam `topics`,
    /// `plan`, `materials`, `path` (How it's gone); progress `week`, `exams`, `fading`, `mixups`, `more`; streak `heatmap`, `milestones`,
    /// `freezes`; Settings ▸ What Cap can do `added`. course `tabs` (its tabs have their own hooks: see `CourseView`). A no-op in release builds.
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
