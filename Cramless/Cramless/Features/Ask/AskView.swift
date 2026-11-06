import SwiftUI

/// The Ask tab: a new chat with Cap until the first question, then that chat. The title holds the course menu, chat history and a new chat
/// sit beside it, and Cap's style is in the composer.
///
/// Harness (DEBUG), read once: `CRAMLESS_ASK=demo` opens a worked conversation (bold, a table, citations, a quick
/// check and its answer); `stream` asks a question and holds Cap's answer mid-way; `asked` asks it and lets it
/// finish (with `CRAMLESS_CONSENT=0`: the offline answer and the Cloud AI offer); `latest` opens the most recent
/// chat. `CRAMLESS_AGE=teen` shows an under-18 account (hints first, locked), `CRAMLESS_TUTOR=explain` starts on
/// Just explain, `CRAMLESS_ASK_MODE=open` opens Cap's style in the composer, and `CRAMLESS_SCROLL=top` starts a long chat at its top
/// (`AskDemo.applyLaunchState`).
struct AskView: View {
    @Environment(AppModel.self) private var app
    @State private var threadID: UUID?
    @State private var courseID: UUID?
    @State private var started = false
    @State private var deleting: DeleteRequest?

    var body: some View {
        let _ = app.revision
        let thread = app.thread(threadID).flatMap { $0.modelContext != nil ? $0 : nil }
        ChatPane(threadID: $threadID, pendingCourseID: $courseID)
            .navigationTitle("Ask Cap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ChatHistoryMenu(current: threadID, onOpen: { id in withAnimation(CLMotion.settle) { threadID = id } },
                                    onDeleteAll: { deleting = .all })
                    if let thread {
                        ChatActionsMenu(thread: thread, onDelete: { deleting = .one(thread.id) })
                    }
                    Button {
                        CLHaptics.tap()
                        withAnimation(CLMotion.settle) { threadID = nil }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(thread == nil)
                    .accessibilityLabel("New chat")
                }
            }
            .modifier(DeleteChatConfirmation(request: $deleting) { request in
                if case .one(let id) = request, id == threadID { threadID = nil }
                if case .all = request { threadID = nil }
            })
            .task {
                guard !started else { return }
                started = true
                courseID = app.defaultChatCourseID
                #if DEBUG
                applyHarness()
                #endif
            }
    }

    #if DEBUG
    private func applyHarness() {
        AskDemo.applyLaunchState(app)
        if let script = TestHarness.once("CRAMLESS_ASSISTANT") {
            threadID = AskDemo.assistant(script, app: app, courseID: courseID)
            return
        }
        guard let hook = TestHarness.once("CRAMLESS_ASK") else { return }
        switch hook {
        case "demo":
            threadID = AskDemo.conversation(app: app)?.id
        case "stream", "asked":
            app.setTutorMode(.explain)
            if hook == "stream" { AskStreams.shared.freezeAfterPieces = 15 }
            let thread = app.startChat(courseID: courseID)
            threadID = thread.id
            AskStreams.shared.ask("What's the difference between mitosis and cytokinesis?", in: thread, app: app)
        case "latest":
            threadID = app.chatThreads().first?.id
        default:
            break
        }
    }
    #endif
}

/// One chat, pushed (from Explain my mistake's follow-up, a deep link, the harness).
///
/// Harness (DEBUG): `CRAMLESS_CHAT=demo` adds the worked conversation to the chat shown.
struct ChatView: View {
    let threadID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var current: UUID?
    @State private var deleting: DeleteRequest?

    init(threadID: UUID) {
        self.threadID = threadID
        _current = State(initialValue: threadID)
    }

    var body: some View {
        let _ = app.revision
        let thread = app.thread(current).flatMap { $0.modelContext != nil ? $0 : nil }
        Group {
            if thread != nil {
                ChatPane(threadID: $current, pendingCourseID: .constant(nil), showsEmptyState: false,
                         title: thread?.title ?? String(localized: "Chat"))
            } else {
                VStack(spacing: 12) {
                    CapView(pose: .sleep, size: 140)
                    Text("This chat was deleted.").clFont(.headline).foregroundStyle(CLColor.ink)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clScreenBackground()
            }
        }
        .navigationTitle(thread?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let thread {
                ToolbarItem(placement: .topBarTrailing) {
                    ChatActionsMenu(thread: thread, onDelete: { deleting = .one(thread.id) })
                }
            }
        }
        .modifier(DeleteChatConfirmation(request: $deleting) { _ in dismiss() })
        #if DEBUG
        .task {
            AskDemo.applyLaunchState(app)
            if TestHarness.once("CRAMLESS_CHAT") == "demo", let thread { AskDemo.extend(thread, app: app) }
        }
        #endif
    }
}

// MARK: - Toolbar menus

/// The chat history: recent chats to open, and deleting them all.
struct ChatHistoryMenu: View {
    let current: UUID?
    let onOpen: (UUID) -> Void
    let onDeleteAll: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let _ = app.revision
        let threads = app.chatThreads().filter { !$0.messages.isEmpty }
        Menu {
            if threads.isEmpty {
                Text("Your chats with Cap appear here.")
            } else {
                Section("Recent chats") {
                    ForEach(threads.prefix(15)) { thread in
                        Button {
                            CLHaptics.select()
                            onOpen(thread.id)
                        } label: {
                            Text(thread.title.isEmpty ? "Chat" : thread.title)
                            Text(subtitle(thread))
                            Image(systemName: thread.id == current ? "checkmark"
                                  : thread.messages.contains { $0.contextItemID != nil } ? "exclamationmark.bubble" : "bubble.left")
                        }
                    }
                }
                Section {
                    Button("Delete all chats", systemImage: "trash", role: .destructive, action: onDeleteAll)
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .accessibilityLabel("Chat history")
    }

    private func subtitle(_ thread: ChatThread) -> String {
        var parts = [AskEmptyState.when(thread.updatedAt, now: app.now)]
        if let course = app.liveCourse(thread.courseID) { parts.append(course.name) }
        return parts.joined(separator: " · ")
    }
}

/// Make cards from the chat, or delete it.
struct ChatActionsMenu: View {
    let thread: ChatThread
    let onDelete: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let hasAnswers = thread.modelContext != nil && thread.messages.contains { $0.role == .assistant }
        Menu {
            Button("Make cards from this chat", systemImage: "rectangle.stack.badge.plus") {
                app.router.present(.makeCards(threadID: thread.id))
            }
            .disabled(!hasAnswers)
            Button("What Cap can do", systemImage: "wand.and.stars") {
                app.router.push(.settingsPage(.assistant), on: .ask)
            }
            Button("Delete chat", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Chat actions")
    }
}

enum DeleteRequest: Hashable {
    case one(UUID)
    case all
}

/// "Delete this chat?" with what it means: gone from this iPhone, cards made from it stay.
struct DeleteChatConfirmation: ViewModifier {
    @Binding var request: DeleteRequest?
    let onDeleted: (DeleteRequest) -> Void

    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                                   titleVisibility: .visible, presenting: request) { request in
            Button(request == .all ? "Delete all chats" : "Delete chat", role: .destructive) {
                delete(request)
            }
        } message: { _ in
            Text("Chats are kept only on this iPhone, so this can't be undone. Cards you made from them stay.")
        }
    }

    private var title: String { request == .all ? "Delete every chat?" : "Delete this chat?" }

    private func delete(_ request: DeleteRequest) {
        switch request {
        case .one(let id):
            AskStreams.shared.discard(id)
            if let thread = app.thread(id) { app.deleteChat(thread) }
        case .all:
            for thread in app.chatThreads() { AskStreams.shared.discard(thread.id) }
            app.deleteAllChats()
        }
        CLHaptics.commit()
        onDeleted(request)
        app.router.toast(request == .all ? "Chats deleted" : "Chat deleted", systemImage: "trash", tone: .neutral)
    }
}
