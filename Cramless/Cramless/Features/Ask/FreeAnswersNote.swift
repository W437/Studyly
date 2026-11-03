import SwiftUI

/// "3 free answers left today": a quiet count under Ask's header once the day's free Cloud AI answers run low (3 or fewer). Nothing
/// when Cloud AI is off, the plan is paid, or plenty are left; Cap goes on answering from the notes after the last one.
struct FreeAnswersNote: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let line = SessionCopy.freeAnswersLeft(app.ai.freeCloudUsesLeft(for: .tutor)) {
            Text(line)
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
                .padding(.horizontal, 4)
        }
    }
}
