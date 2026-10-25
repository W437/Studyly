import SwiftUI

/// Squad: one plan, four seats.
/// - The owner (bought Squad) sees the seats and members, invites a friend (a single-use code, shared as a link with
///   the code), and can remove a member.
/// - A member (a seat on a friend's Squad) sees whose Squad it is, and can leave.
/// - Without Squad: what it is ("You + 3 friends, $2.08 each a month"), the plans, and "Have a code?".
///
/// Seats live on the server, so managing them needs an account; a build without accounts says so.
///
/// Harness: `CRAMLESS_PLAN=squad` (an owner) with `CRAMLESS_ACCOUNT=apple`; `CRAMLESS_SQUAD=member` shows a seat on
/// Maya's Squad; `CRAMLESS_SQUAD=invite` makes an invite at once.
struct SquadView: View {
    enum Role: Equatable { case owner, member, none }

    @Environment(AppModel.self) private var app
    @State private var members: SquadMembers?
    @State private var loadError: String?
    @State private var invite: SquadInvite?
    @State private var inviting = false
    @State private var inviteError: String?
    @State private var removing: SquadMember?
    @State private var confirmingLeave = false
    @State private var busy = false

    private var hasAccounts: Bool { app.config.aiMode != .local }

    var role: Role {
        #if DEBUG
        if TestHarness.value("CRAMLESS_SQUAD") == "member" { return .member }
        #endif
        return Self.role(allowsSeats: app.purchases.allows(.squadSeats), plan: app.purchases.plan)
    }

    /// Bought Squad: the owner. A Squad plan without the purchase: a seat on a friend's. Anything else: no Squad.
    static func role(allowsSeats: Bool, plan: Plan) -> Role {
        if allowsSeats { return .owner }
        if plan == .squad { return .member }
        return .none
    }

    var body: some View {
        let role = self.role
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch role {
                case .owner: owner
                case .member: member
                case .none: pitch
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 6)
            .padding(.bottom, 40)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .clScreenBackground()
        .navigationTitle("Squad")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: role) { await load(role) }
        .confirmationDialog(removing.map { "Remove \($0.name) from your Squad?" } ?? "",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { member in
            Button("Remove \(member.name)", role: .destructive) { remove(member) }
        } message: { member in
            Text("\(member.name) goes back to the free plan at once and their seat opens for someone else. Everything they've studied stays theirs.")
        }
        .confirmationDialog("Leave \(ownerName)'s Squad?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave Squad", role: .destructive, action: leave)
        } message: {
            Text("You'll go back to the free plan. Everything you've studied stays on your iPhone and in your account.")
        }
    }

    // MARK: Owner

    private var owner: some View {
        let list = members?.members ?? []
        let seats = members?.seats ?? StoreCatalog.squadSeats
        return VStack(alignment: .leading, spacing: 0) {
            SeatsCard(members: list, seats: seats, loading: members == nil && loadError == nil)
                .padding(.top, 10)
            if let loadError { errorLine(loadError).padding(.top, 12) }
            if !list.isEmpty {
                CLSectionHeader(title: "Members")
                CLList {
                    ForEach(list) { m in
                        MemberRow(member: m, isYou: m.isOwner, joined: m.joinedAt) {
                            if !m.isOwner {
                                Button("Remove") { removing = m }
                                    .buttonStyle(.cl(.destructive, size: .small, fullWidth: false))
                                    .disabled(busy)
                                    .accessibilityLabel("Remove \(m.name)")
                            }
                        }
                    }
                }
            }
            CLSectionHeader(title: "Invite a friend")
            inviteSection(open: max(0, seats - list.count), knowsSeats: members != nil)
            Text("Each friend studies with their own account and their own notes. A seat can be given to someone else at any time.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func inviteSection(open: Int, knowsSeats: Bool) -> some View {
        if !hasAccounts {
            SettingsInfoCard(icon: "iphone", title: "Accounts aren't set up in this build",
                             text: "Seats live in your account, so invites can't be made here.")
                .clCard(padding: 0)
        } else if !app.account.isSignedIn {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sign in first, so your friends' seats stay with your account on any iPhone.")
                    .clFont(.subheadline).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
                SignInPanel()
            }
            .clCard()
        } else if let invite {
            InviteCard(invite: invite)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(open == 0 && knowsSeats ? "All four seats are taken. Remove a member to invite someone new."
                     : "A code works once, for one friend. Share it as a link, or read it out.")
                    .clFont(.subheadline).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
                Button(action: makeInvite) {
                    ZStack {
                        Label("Invite a friend", systemImage: "person.badge.plus").opacity(inviting ? 0 : 1)
                        if inviting { ProgressView().tint(CLColor.onFill) }
                    }
                }
                .buttonStyle(.cl(.primary))
                .disabled(inviting || (open == 0 && knowsSeats))
                if let inviteError { errorLine(inviteError) }
            }
            .clCard()
        }
    }

    // MARK: Member

    private var member: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: -10) {
                    ForEach(Array((members?.members ?? []).prefix(4).enumerated()), id: \.offset) { i, m in
                        InitialsAvatar(name: m.name, size: 46, fill: SeatsCard.fill(i))
                            .overlay(Circle().stroke(CLColor.surface, lineWidth: 3))
                    }
                }
                .accessibilityHidden(true)
                Text("You're on \(ownerName)'s Squad").clFont(.brandTitle(26)).foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Every Pro feature, on \(ownerName)'s plan. Your studying, notes and progress are your own.")
                    .clFont(.subheadline).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
            }
            .clCard()
            .padding(.top, 10)
            if let loadError { errorLine(loadError).padding(.top, 12) }
            if let list = members?.members, !list.isEmpty {
                CLSectionHeader(title: "In this Squad")
                CLList {
                    ForEach(list) { m in
                        MemberRow(member: m, isYou: false, joined: m.joinedAt) { EmptyView() }
                    }
                }
            }
            SettingsGroup(title: nil, footer: "You'll go back to the free plan. Everything you've studied stays.") {
                SettingsActionRow(icon: "rectangle.portrait.and.arrow.right", title: "Leave Squad", destructive: true, busy: busy) {
                    confirmingLeave = true
                }
            }
            .padding(.top, 26)
        }
    }

    // MARK: No Squad

    private var pitch: some View {
        let price = app.purchases.price(for: .squad)
        let isPro = app.purchases.plan == .pro
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                SquadHeroArt()
                    .frame(maxWidth: .infinity)
                CLEyebrow(text: "Squad", color: CLColor.mintInk)
                Text("You + 3 friends, \(price.perSeatPerMonth) each a month")
                    .clFont(.brandTitle(28))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(isPro ? "You're on Pro. With Squad, three friends get every Pro feature too, on one plan."
                     : "One plan, four people, every Pro feature. \(price.display) a year in all"
                        + (app.purchases.trialDays(for: .squad).map { ", with \($0) days free." } ?? "."))
                    .clFont(.callout)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 11) {
                    PaywallBenefitRow(symbol: "sparkles", text: "Everyone gets every Pro feature")
                    PaywallBenefitRow(symbol: "link", text: "Invite friends with a link or a code")
                    PaywallBenefitRow(symbol: "person.crop.circle", text: "Each friend keeps their own account and notes")
                }
                .padding(.top, 4)
                Button("See Squad") {
                    CLHaptics.tap()
                    app.router.present(.paywall(.feature(PaidFeature.squadSeats.paywallLine)))
                }
                .buttonStyle(.cl(.primary))
                .padding(.top, 8)
            }
            .clCard(padding: 20)
            .padding(.top, 10)

            CLList {
                NavigationLinkRow(icon: "ticket", tint: .mint, title: "Have a code?",
                                  subtitle: "Join a friend's Squad") {
                    app.router.present(.squadRedeem(code: nil))
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: Helpers

    private var ownerName: String {
        members?.members.first(where: \.isOwner)?.name ?? "your friend"
    }

    private func errorLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .clFont(.footnoteEmphasis)
            .foregroundStyle(CLColor.roseInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func load(_ role: Role) async {
        guard role != .none, hasAccounts else { return }
        do {
            members = try await app.squadMembers()
            loadError = nil
        } catch {
            loadError = RelayError.message(for: error)
        }
        #if DEBUG
        if role == .owner, TestHarness.once("CRAMLESS_SQUAD") == "invite" { makeInvite() }
        #endif
    }

    private func makeInvite() {
        inviting = true
        inviteError = nil
        Task {
            do {
                let made = try await app.createSquadInvite()
                CLHaptics.success()
                withAnimation(CLMotion.settle) { invite = made }
            } catch {
                inviteError = RelayError.message(for: error)
            }
            inviting = false
        }
    }

    private func remove(_ member: SquadMember) {
        busy = true
        Task {
            do {
                let updated = try await app.removeSquadMember(member.id)
                CLHaptics.commit()
                withAnimation(CLMotion.settle) { members = updated }
                app.router.toast("\(member.name) left your Squad. A seat is open.", systemImage: "person.badge.minus", tone: .neutral)
            } catch {
                loadError = RelayError.message(for: error)
            }
            busy = false
        }
    }

    private func leave() {
        guard let id = app.account.userID else {
            loadError = RelayError.unauthorized.friendlyMessage
            return
        }
        busy = true
        Task {
            do {
                _ = try await app.removeSquadMember(id)
                CLHaptics.commit()
                app.router.toast("You left the Squad. You're on the free plan.", systemImage: "person.badge.minus", tone: .neutral)
            } catch {
                loadError = RelayError.message(for: error)
            }
            busy = false
        }
    }
}

/// The four seats as circles: a face for each member, a dashed ring for each open seat.
private struct SeatsCard: View {
    let members: [SquadMember]
    let seats: Int
    let loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Squad").clFont(.title2).foregroundStyle(CLColor.ink)
                Spacer()
                if !loading {
                    Text("\(members.count) of \(seats) seats").clFont(.number(17, .bold)).foregroundStyle(CLColor.ink2)
                }
            }
            HStack(spacing: 12) {
                ForEach(0..<max(seats, members.count), id: \.self) { i in
                    VStack(spacing: 6) {
                        if i < members.count {
                            InitialsAvatar(name: members[i].name, size: 54, fill: Self.fill(i))
                        } else {
                            Circle()
                                .strokeBorder(CLColor.ink4, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                .frame(width: 54, height: 54)
                                .overlay(Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(CLColor.ink3))
                        }
                        Text(i < members.count ? (members[i].isOwner ? "You" : members[i].name) : "Open")
                            .clFont(.caption)
                            .foregroundStyle(i < members.count ? CLColor.ink : CLColor.ink3)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .redacted(reason: loading ? .placeholder : [])
                }
            }
            Text("Everyone in your Squad gets every Pro feature.")
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
        }
        .clCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(loading ? "Your Squad, loading" :
            "Your Squad: \(members.count) of \(seats) seats taken. \(members.map(\.name).joined(separator: ", "))."))
    }

    static func fill(_ index: Int) -> Color {
        [CLColor.tangerine, CLColor.sky, CLColor.mint, CLColor.sun][index % 4]
    }
}

/// A member: their face, their name, when they joined.
private struct MemberRow<Trailing: View>: View {
    let member: SquadMember
    let isYou: Bool
    let joined: Date
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: member.name, size: 38, fill: member.isOwner ? CLColor.tangerine : CLColor.sky)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isYou ? "\(member.name) (you)" : member.name).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                    if member.isOwner { CLPill(text: "Owner", tone: .mint) }
                }
                Text("Joined \(joined.formatted(.dateTime.month(.abbreviated).day()))")
                    .clFont(.footnote).foregroundStyle(CLColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: CLMetrics.rowMinHeight)
    }
}

/// An invite just made: the code, when it stops working, and sharing it.
private struct InviteCard: View {
    let invite: SquadInvite
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your invite code").clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink2)
            Text(invite.code)
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospaced())
                .foregroundStyle(CLColor.ink)
                .textSelection(.enabled)
                .accessibilityLabel(Text("Code: \(invite.code.map { String($0) }.joined(separator: " "))"))
            Text("Works once, for one friend, until \(invite.expiresAt.formatted(.dateTime.month(.wide).day())).")
                .clFont(.subheadline).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let url = URL(string: invite.url) {
                    ShareLink(item: url, subject: Text("Join my Capling Squad"),
                              message: Text("Join my Capling Squad: tap the link, or enter code \(invite.code) in Settings, Squad.")) {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.cl(.primary, size: .medium))
                }
                Button {
                    UIPasteboard.general.string = invite.code
                    CLHaptics.select()
                    withAnimation(CLMotion.pop) { copied = true }
                } label: {
                    Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
            }
        }
        .clCard()
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }
}

/// Four friends, Cap among them.
private struct SquadHeroArt: View {
    var body: some View {
        HStack(spacing: -14) {
            CapFace(size: 64).overlay(RoundedRectangle(cornerRadius: 64 * 0.32, style: .continuous).stroke(CLColor.surface, lineWidth: 3))
            ForEach(["Priya", "Jordan", "Sam"], id: \.self) { name in
                InitialsAvatar(name: name, size: 60, fill: [CLColor.sky, CLColor.mint, CLColor.sun][["Priya", "Jordan", "Sam"].firstIndex(of: name) ?? 0])
                    .overlay(Circle().stroke(CLColor.surface, lineWidth: 3))
            }
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}
