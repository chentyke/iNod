import NodeSeekCore
import NodeSeekClient
import SwiftUI

enum ThreadPresentation {
    /// Pushed onto a single-column feed with the card zoom transition and floating back bar.
    case zoom
    /// Pushed from notifications, a profile or another thread with a standard navigation bar.
    case pushed
    /// Shown side by side with the feed on iPad, with a floating author/menu bar and no back arrow.
    case splitDetail
}

struct ThreadView: View {
    let post: PostSummary
    private let presentation: ThreadPresentation
    private let sharedTabRow: ReaderTabRow?
    private let onClose: (() -> Void)?
    @Environment(AccountSession.self) private var account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.openMemberDestination) private var openMember
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("showsBlockedContent") private var showsBlocked = false
    @State private var detail: PostDetail?
    @State private var createdDate: Date?
    @State private var page = 1
    @State private var firstLoadedPage = 1
    @State private var lastLoadedPage = 1
    @State private var totalPages = 1
    @State private var requestedCommentPage: Int?
    @State private var commentPageErrors: [Int: String] = [:]
    @State private var error: (any Error)?
    @State private var isLoading = true
    @State private var showsVerification = false
    @State private var showsSignIn = false
    @State private var isWritingReply = false
    @State private var pendingReply: ThreadReplyRequest?
    @State private var editorRequest: EditorRequest?
    @State private var collectionError: (collected: Bool, revision: Int, message: String)?
    @State private var showsCollectionError = false
    @State private var requestedFloor: Int?
    @State private var scrollPosition = ScrollPosition(idType: Int.self)
    /// The floor a link or notification opened, held at the top until the reader scrolls. On a tall screen the
    /// earlier-page loader is already visible above it, and the replies it inserts would push the floor away.
    @State private var heldFloor: Int?
    @State private var openingEditor = false
    @State private var refreshID = UUID()
    @State private var loadedKey: SiteRequestKey?
    @State private var loadedRefreshID: UUID?
    @State private var loadID = UUID()
    @State private var busyCommentID: Int?
    @State private var expandedActionsCommentID: Int?
    @State private var reactionToPrepare: (commentID: Int, reaction: CommentReaction)?
    @State private var pendingReaction: PendingReaction?
    @State private var showsReactionConfirmation = false
    @State private var actionError: String?
    @State private var showsActionError = false
    @State private var gallery: ImageGallery?
    @State private var replyImagePages: [Task<ImageGallery.ReplyImages, Never>] = []
    @State private var openingGallery: Task<Void, Never>?

    private var accessError: PostAccessError? { error as? PostAccessError }
    private var isCollected: Bool { account.collections.status(post.id) == true }
    private var threadKind: String { showsBlocked ? "thread-including-blocked" : "thread" }
    /// The Mac puts back, reply and the post menu in its window toolbar, so the page keeps no bars of its own.
    private var usesMacToolbar: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
    private var usesFloatingTopBar: Bool { !usesMacToolbar && (presentation == .zoom || presentation == .splitDetail) }
    private var usesNavigationBar: Bool { !usesMacToolbar && !usesFloatingTopBar }

    init(
        post: PostSummary,
        initialPage: Int = 1,
        initialFloor: Int? = nil,
        usesZoomTransition: Bool = false,
        presentation: ThreadPresentation? = nil,
        sharedTabRow: ReaderTabRow? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.post = post
        self.sharedTabRow = sharedTabRow
        self.presentation = presentation ?? (usesZoomTransition ? .zoom : .pushed)
        self.onClose = onClose
        _page = State(initialValue: max(1, initialPage))
        _requestedFloor = State(initialValue: initialFloor)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    ThreadHeader(post: post, detail: detail, createdDate: createdDate, showsRank: accessError == nil || accessError == .signInRequired,
                                 showsAuthor: usesMacToolbar)
                    if let accessError {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(accessError.localizedDescription, image: .inkRestrictedPost)
                                .font(.headline)
                            if case .levelRequired = accessError, let level = account.user?.level {
                                Text("当前等级 Lv \(level)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            if accessError == .signInRequired {
                                Button("登录") { showsSignIn = true }.buttonStyle(.seekPill)
                            }
                        }
                        .padding(20)
                    } else if let error {
                        if detail == nil {
                            LoadFailureView(failure: LoadFailure(error), isRetrying: isLoading,
                                            offersWebsite: account.website.needsWebsite, websiteURL: post.url,
                                            retry: { refreshID = UUID() }, verify: { showsVerification = true })
                                .padding(.top, 12).padding(.bottom, 32)
                        } else {
                            LoadFailureBanner(failure: LoadFailure(error), isRetrying: isLoading) { refreshID = UUID() }
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                    }
                    if isLoading && detail == nil {
                        ProgressView("正在读取帖子").frame(maxWidth: .infinity).padding(40)
                    }
                    if let original = detail?.comments.first(where: { $0.floorIndex == 0 }), showsBlocked || !original.blocked {
                        commentView(original, showsHeader: false)
                    }
                }.seekCard(padding: 0).id(0)
                if let detail {
                    SeekSectionTitle(title: "讨论")
                        .padding(.horizontal, 4).padding(.top, 8)
                    if !isLoading, error == nil, firstLoadedPage > 1 {
                        commentsLoader(for: firstLoadedPage - 1, loadingEarlier: true)
                    }
                    ForEach(visibleReplies(in: detail), id: \.floorIndex) { comment in
                        commentView(comment)
                    }
                    if !isLoading && error == nil {
                        if lastLoadedPage < totalPages {
                            commentsLoader(for: lastLoadedPage + 1, loadingEarlier: false)
                        } else if totalPages > 1 {
                            Text("没有更多评论了").font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: SeekLayout.readableWidth).frame(maxWidth: .infinity)
            .padding(.horizontal, SeekLayout.gutter).padding(.vertical, 12)
            .background(TopOverscrollLock())
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollPosition($scrollPosition)
        .fadesUnderMacToolbar()
        // An open reaction dock folds away once the reader scrolls or taps anywhere outside it.
        // Touch tracking is left out so a tap on the dock's own buttons isn't cancelled.
        .onScrollPhaseChange { _, phase in
            if phase == .interacting || phase == .decelerating || phase == .animating { foldActionDock() }
            if phase == .interacting { heldFloor = nil }
        }
        .gesture(TapGesture().onEnded { foldActionDock() },
                 including: expandedActionsCommentID != nil ? .all : .subviews)
        .seekCanvas(margins: .keepsGutter, in: .scrollView)
        .environment(\.forumDocumentURL,NodeSeekRoute.thread(id:post.id,page:page).url)
        .environment(\.openURL, OpenURLAction { url in
            switch ForumLink.parse(url.absoluteString) {
            case .native(.post(let address)) where address.id == post.id:
                if let floor = address.floor, floor >= 0 {
                    jumpToFloor(floor)
                } else {
                    openURL(url)
                }
            case .native(.mention(let name)):
                if let id = memberID(matching: name) {
                    openMember(.profile(id))
                } else {
                    openURL(url)
                }
            default:
                openURL(url)
            }
            return .handled
        })
        .onChange(of: isLoading) { _, loading in
            if !loading, error == nil, detail?.postPage == page, let floor = requestedFloor {
                if !scrollToFloor(floor) { showMissingFloor() }
                requestedFloor = nil
            }
        }
        .contentMargins(.bottom, usesMacToolbar ? 24 : 0, for: .scrollContent)
        .id(page)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(usesNavigationBar ? .visible : .hidden, for: .navigationBar)
        .macToolbar(.leading, items: presentation == .splitDetail ? [] : [
            MacToolbarItem(id: "back", label: "返回", image: .inkBack, isNavigational: true) { dismiss() }
        ])
        .macToolbar(.trailing, items: macToolbarItems)
        .hidesTabBarWhenPushed()
        .safeAreaBar(edge: .top, spacing: 0) {
            if usesFloatingTopBar {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        if presentation == .zoom {
                            ThreadBackButton { dismiss() }
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                        }
                        ThreadAuthorBar(post: post, detail: detail, maximumWidth: sharedTabRow?.authorWidth)
                        Spacer(minLength: 0)
                        Menu {
                            postMenuItems
                        } label: {
                            Image(.inkPostActions)
                                .font(.headline.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.seekGreen)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("更多")
                    }
                    .padding(.horizontal, SeekLayout.gutter)
                    .padding(.vertical, sharedTabRow != nil ? 0 : (presentation == .splitDetail ? 10 : 4))
                    .readableColumn()
                }
            }
        }
        .safeAreaPadding(.top, sharedTabRow?.topInset ?? 0)
        .ignoresSafeArea(.container, edges: sharedTabRow == nil ? [] : .top)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !usesMacToolbar || pendingReply != nil || isWritingReply {
                ThreadActionBar(
                    post: post,
                    threadTitle: detail?.title ?? post.title,
                    canReply: detail != nil,
                    showsReply: accessError == nil,
                    isCollected: isCollected,
                    isUpdatingCollection: account.collections.updating.contains(post.id),
                    request: $pendingReply,
                    isWriting: $isWritingReply,
                    onCollection: {
                        let collected = !isCollected
                        Task { await setCollection(collected) }
                    },
                    onSignIn: { showsSignIn = true },
                    onPublished: { refreshID = UUID() }
                )
                .padding(.horizontal, 20)
                .readableColumn()
                .padding(.bottom, 12)
            }
        }
        .toolbar {
            if usesNavigationBar {
                ToolbarItem(placement: .topBarLeading) {
                    ThreadAuthorBar(post: post, detail: detail)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("更多", image: .inkPostActions) {
                        postMenuItems
                    }
                }
            }
        }
        .task(id: "\(post.id)|\(showsBlocked)|\(page)|\(refreshID)|\(account.revision)") { await load() }
        .menuRefreshable { await load(force: true) }
        .task(id: requestedCommentPage) {
            if let requestedCommentPage { await loadCommentPage(requestedCommentPage) }
        }
        .task(id: reactionToPrepare?.commentID) {
            if let reactionToPrepare { await prepare(reactionToPrepare.reaction, commentID: reactionToPrepare.commentID) }
        }
        .onDisappear {
            openingGallery?.cancel()
            requestedCommentPage = nil
            pendingReply = nil
            isWritingReply = false
            reactionToPrepare = nil
        }
        .sheet(isPresented: $showsVerification, onDismiss: { refreshID = UUID() }) {
            WebsiteView(initialURL: post.url)
        }
        .sheet(isPresented: $showsSignIn, onDismiss: {
            if accessError == .signInRequired, account.isLoggedIn { refreshID = UUID() }
        }) { SignInView() }
        .sheet(item: $editorRequest) { request in
            ForumEditorView(request: request) { _ in refreshID = UUID() }
        }
        .fullScreenCover(item: $gallery) { ImageViewer(gallery: $0) }
        .alert("操作未完成", isPresented: $showsActionError) {
            Button("知道了", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .alert("收藏操作未完成", isPresented: $showsCollectionError, presenting: collectionError) { failure in
            Button("重试") {
                guard account.revision == failure.revision else { return }
                Task { await setCollection(failure.collected) }
            }
            Button("取消", role: .cancel) { }
        } message: { failure in
            Text(failure.message)
        }
    }

    private func memberID(matching name: String) -> Int? {
        guard let detail else { return nil }
        if detail.op.name.caseInsensitiveCompare(name) == .orderedSame { return detail.op.uid }
        return detail.comments.first { $0.poster.name.caseInsensitiveCompare(name) == .orderedSame }?.poster.uid
    }

    private func jumpToFloor(_ floor: Int) {
        if scrollToFloor(floor) {
            requestedFloor = nil
            return
        }
        let targetPage = PostAddress.page(forFloor: floor)
        if targetPage > totalPages || (firstLoadedPage...lastLoadedPage).contains(targetPage) {
            showMissingFloor()
        } else {
            requestedFloor = floor
            scrollPosition = ScrollPosition(idType: Int.self)
            page = targetPage
        }
    }

    private func scrollToFloor(_ floor: Int) -> Bool {
        guard detail?.comments.contains(where: { $0.floorIndex == floor && (showsBlocked || !$0.blocked) }) == true else { return false }
        scrollPosition.scrollTo(id: floor, anchor: .top)
        heldFloor = floor
        return true
    }

    private func showMissingFloor() {
        actionError = "没有找到这条回复。"
        showsActionError = true
    }

    private var macToolbarItems: [MacToolbarItem] {
        var items: [MacToolbarItem] = []
        if accessError == nil {
            items.append(MacToolbarItem(id: MacToolbarItem.replyID,
                                        label: account.signInStatus == .signedOut ? "登录后回复" : "写回复",
                                        image: .inkReply,
                                        isEnabled: detail != nil && pendingReply == nil) { pendingReply = .write })
        }
        items.append(MacToolbarItem(id: MacToolbarItem.collectionID, label: isCollected ? "取消收藏" : "收藏",
                                    image: isCollected ? .inkSavedPost : .inkSavePost,
                                    isEnabled: !account.collections.updating.contains(post.id)) {
            let collected = !isCollected
            Task { await setCollection(collected) }
        })
        items.append(MacToolbarItem(id: "share", label: "分享帖子", image: .inkSharePost, kind: .share(post.url)))
        var menu: [[MacToolbarMenuEntry]] = [[]]
        if let detail, detail.op.uid == account.user?.id, detail.locked != true, !openingEditor {
            menu[0].append(MacToolbarMenuEntry(id: "edit", title: "编辑帖子", image: .inkEditPost) {
                Task { await openPostEditor() }
            })
        }
        menu[0].append(MacToolbarMenuEntry(id: "website", title: "在官网查看", image: .inkWebsite) { Browser.open(post.url) })
        if let onClose {
            menu.append([MacToolbarMenuEntry(id: "close", title: "关闭帖子", image: .inkClose) { onClose() }])
        }
        items.append(MacToolbarItem(id: "more", label: "更多", image: .inkPostActions, kind: .menu(title: nil, sections: menu)))
        return items
    }

    @ViewBuilder private var postMenuItems: some View {
        if let detail, detail.op.uid == account.user?.id {
            Button("编辑帖子", image: .inkEditPost) { Task { await openPostEditor() } }
                .disabled(detail.locked == true || openingEditor)
        }
        Button("在官网查看", image: .inkWebsite) { Browser.open(post.url) }
        if let onClose {
            Divider()
            Button("关闭帖子", image: .inkClose) { onClose() }
        }
    }

    private func commentView(_ comment: ForumComment, showsHeader: Bool = true) -> some View {
        CommentView(comment: comment, showsHeader: showsHeader, isAuthor: comment.poster.uid == detail?.op.uid, isBusy: busyCommentID == comment.id || reactionToPrepare?.commentID == comment.id, actionsDisabled: busyCommentID != nil || reactionToPrepare != nil || isLoading, canEdit: comment.poster.uid == account.user?.id && detail?.locked != true, canPin: comment.floorIndex > 0 && detail?.op.uid == account.user?.id, actionsExpanded: actionsExpanded(for: comment), pendingReaction: $pendingReaction, showsReactionConfirmation: $showsReactionConfirmation, onReply: { quote in
            pendingReply = .respond(ThreadReplyTarget(name: comment.poster.name, floor: comment.floorIndex,
                                                       quote: quote ? comment.markdown : nil))
            foldActionDock()
        }, onEdit: { edit(comment) }, onPin: {
            Task { await pin(comment) }
        }, onOpenImages: { images in
            openImages(images, from: comment)
        }, onConfirmReaction: { pending in Task { await submit(pending) } }) { reaction in
            guard busyCommentID == nil, reactionToPrepare == nil, !comment.hasReacted(reaction) else { return }
            reactionToPrepare = (comment.id, reaction)
        }
    }

    private func actionsExpanded(for comment: ForumComment) -> Binding<Bool> {
        Binding {
            expandedActionsCommentID == comment.id
        } set: { expanded in
            if expanded { expandedActionsCommentID = comment.id }
            else if expandedActionsCommentID == comment.id { expandedActionsCommentID = nil }
        }
    }

    private func foldActionDock() {
        guard expandedActionsCommentID != nil else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.2)) { expandedActionsCommentID = nil }
    }

    private func visibleReplies(in detail: PostDetail) -> [ForumComment] {
        detail.replies.filter { showsBlocked || !$0.blocked }
    }

    private func openImages(_ images: ImageGallery, from comment: ForumComment) {
        openingGallery?.cancel()
        guard comment.floorIndex > 0, let detail else { gallery = images; return }
        let replyIDs = visibleReplies(in: detail).map(\.id)
        guard let index = replyIDs.firstIndex(of: comment.id) else { return }
        let pages = replyImagePages
        let key = loadedKey
        let revision = account.revision
        let kind = threadKind
        openingGallery = Task {
            let result = await images.includingReplies(replyIDs, at: index, from: pages)
            guard !Task.isCancelled, loadedKey == key, account.revision == revision, threadKind == kind else { return }
            gallery = result
        }
    }

    private func setDetail(_ value: PostDetail?) {
        if value == nil {
            openingGallery?.cancel()
            for page in replyImagePages { page.cancel() }
        }
        replyImagePages = value.map { [ImageGallery.prepareReplyImages(visibleReplies(in: $0))] } ?? []
        detail = value
    }

    private func openPostEditor() async {
        guard !openingEditor else { return }; openingEditor = true; defer { openingEditor = false }
        do {
            let first = try await account.website.thread(id:post.id,page:1)
            guard first.op.uid == account.user?.id,first.locked != true,let original = first.comments.first(where:{ $0.floorIndex == 0 }) else { throw SiteError.message("这篇帖子暂时不能编辑。") }
            editorRequest = .init(mode:.editPost(postID:post.id,originalRank:first.rank ?? 0),seed:EditorDraft(title:first.title,content:original.markdown,category:first.category ?? "daily",rank:first.rank ?? 0))
        } catch { actionError = SiteError.displayMessage(for: error); showsActionError = true }
    }

    private func edit(_ comment: ForumComment) {
        let mode: EditorMode = comment.floorIndex == 0 ? .editPost(postID: post.id, originalRank: detail?.rank ?? 0) : .editComment(commentID: comment.id)
        editorRequest = .init(mode: mode, seed: EditorDraft(title: detail?.title ?? post.title, content: comment.markdown, category: detail?.category ?? "daily", rank: detail?.rank ?? 0))
    }
    private func pin(_ comment: ForumComment) async {
        guard let userID = account.user?.id, detail?.op.uid == userID, busyCommentID == nil else { return }
        busyCommentID = comment.id
        defer { busyCommentID = nil }
        do {
            let _: ReactionResponse = try await account.website.perform(.pinComment(id: comment.id, pinned: comment.pined == true), userID: userID)
            page = 1; refreshID = UUID(); await account.refresh(force: true)
        } catch { actionError = SiteError.displayMessage(for: error); showsActionError = true }
    }
    private func setCollection(_ collected: Bool) async {
        do {
            if try await account.confirmSignedIn() {
                try await account.collections.setCollected(collected, postID: post.id)
            } else {
                showsSignIn = true
            }
        } catch is CancellationError {
        } catch {
            collectionError = (collected, account.revision, SiteError.displayMessage(for: error))
            showsCollectionError = true
        }
    }

    private func prepare(_ reaction: CommentReaction, commentID: Int) async {
        defer { if !Task.isCancelled { reactionToPrepare = nil } }
        do {
            try await account.withConfirmedSignIn(onSignedOut: { showsSignIn = true }) { _ in
                let revision = account.revision
                if let detail, !detail.comments.contains(where: { $0.id == commentID && !$0.hasReacted(reaction) }) { return }
                if reaction == .upvote {
                    await submit(PendingReaction(commentID: commentID, reaction: reaction, cost: 0, accountRevision: revision))
                } else {
                    let cost = reaction == .like ? try await account.website.chickenCost() : 2
                    try Task.checkCancellation()
                    guard account.revision == revision, account.signInStatus == .signedIn else { return }
                    pendingReaction = PendingReaction(commentID: commentID, reaction: reaction, cost: cost, accountRevision: revision)
                    showsReactionConfirmation = true
                }
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            actionError = SiteError.displayMessage(for: error)
            showsActionError = true
        }
    }

    private func submit(_ pending: PendingReaction) async {
        guard busyCommentID == nil, accessError == nil, account.revision == pending.accountRevision,
              account.signInStatus == .signedIn, let userID = account.user?.id else { return }
        if let detail, !detail.comments.contains(where: { $0.id == pending.commentID && !$0.hasReacted(pending.reaction) }) { return }
        busyCommentID = pending.commentID
        defer { busyCommentID = nil }
        do {
            if pending.reaction == .like {
                let cost = try await account.website.chickenCost()
                guard account.revision == pending.accountRevision, account.signInStatus == .signedIn else { return }
                if cost > pending.cost {
                    pendingReaction = PendingReaction(commentID: pending.commentID, reaction: pending.reaction, cost: cost, accountRevision: pending.accountRevision)
                    showsReactionConfirmation = true
                    return
                }
            }
            try Task.checkCancellation()
            let response = try await account.website.react(commentID: pending.commentID, postID: post.id, reaction: pending.reaction, userID: userID)
            guard account.revision == pending.accountRevision else { return }
            if let count = response.current, let indices = detail?.comments.indices {
                for index in indices where detail?.comments[index].id == pending.commentID {
                    detail?.comments[index].apply(pending.reaction, count: count)
                }
            }
            account.updateCoins(response.coin)
            pendingReaction = nil
            Task { await account.refresh(force: true) }
        } catch is CancellationError {
        } catch {
            actionError = SiteError.displayMessage(for: error)
            showsActionError = true
            await account.refresh()
        }
    }

    private func commentsLoader(for page: Int, loadingEarlier: Bool) -> some View {
        ThreadCommentsLoader(page: page, loadingEarlier: loadingEarlier, error: commentPageErrors[page],
                             canLoad: requestedFloor == nil && requestedCommentPage == nil) {
            guard requestedCommentPage == nil else { return }
            requestedCommentPage = page
        }
    }

    private func loadCommentPage(_ requestedPage: Int) async {
        let generation = loadID
        defer {
            if !Task.isCancelled, loadID == generation, requestedCommentPage == requestedPage {
                requestedCommentPage = nil
            }
        }
        let kind = threadKind
        let loadingEarlier = requestedPage == firstLoadedPage - 1
        guard loadedKey?.kind == kind, detail != nil, !isLoading, requestedPage > 0,
              loadingEarlier || (requestedPage == lastLoadedPage + 1 && requestedPage <= totalPages) else { return }
        let sessionRevision = account.revision
        let force = commentPageErrors.removeValue(forKey: requestedPage) != nil
        do {
            let result = try await account.website.thread(id: post.id, page: requestedPage, includeBlocked: showsBlocked, force: force)
            try Task.checkCancellation()
            guard loadID == generation, requestedCommentPage == requestedPage, threadKind == kind,
                  account.revision == sessionRevision else { return }
            account.synchronizeAfterRequest(expectedRevision: sessionRevision)
            guard account.revision == sessionRevision else { return }
            guard result.postId == post.id, result.postPage == requestedPage else { throw SiteError.invalidResponse }
            var existingIDs = Set(detail?.comments.map(\.id) ?? [])
            let comments = result.comments.filter { existingIDs.insert($0.id).inserted }
            let replies = comments.filter { $0.floorIndex > 0 && (showsBlocked || !$0.blocked) }
            replyImagePages.append(ImageGallery.prepareReplyImages(replies))
            if loadingEarlier {
                detail?.comments.insert(contentsOf: comments, at: 0)
                firstLoadedPage = requestedPage
                if let heldFloor {
                    // The position still names the held floor, so scrolling to it again would change nothing.
                    // Clear it, then scroll back once the inserted replies are laid out.
                    scrollPosition = ScrollPosition(idType: Int.self)
                    Task { scrollPosition.scrollTo(id: heldFloor, anchor: .top) }
                }
                if let date = comments.first(where: { $0.floorIndex == 0 })?.time.date { createdDate = date }
            } else {
                detail?.comments.append(contentsOf: comments)
                lastLoadedPage = requestedPage
            }
            totalPages = max(result.postPageCount, lastLoadedPage)
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, loadID == generation, requestedCommentPage == requestedPage, threadKind == kind else { return }
            account.synchronizeAfterRequest(expectedRevision: sessionRevision)
            guard account.revision == sessionRevision else { return }
            if let accessError = error as? PostAccessError { showAccessError(accessError) }
            else { commentPageErrors[requestedPage] = SiteError.displayMessage(for: error) }
        }
    }

    private func showAccessError(_ error: PostAccessError) {
        setDetail(nil)
        createdDate = nil
        self.error = error
    }

    private func load(force: Bool = false) async {
        let key = account.website.threadKey(id: post.id, page: page, includeBlocked: showsBlocked, viewerID: account.user?.id)
        let force = force || (loadedRefreshID != nil && loadedRefreshID != refreshID)
        if !force, loadedKey == key, loadedRefreshID == refreshID, detail != nil, error == nil { return }
        let operation = UUID()
        loadID = operation
        requestedCommentPage = nil
        commentPageErrors.removeAll()
        if loadedKey != key { setDetail(nil) }
        loadedKey = key
        if detail == nil, let cached: PostDetail = account.website.cached(key: key) { setDetail(cached) }
        if let date = detail?.comments.first(where: { $0.floorIndex == 0 })?.time.date { createdDate = date }
        firstLoadedPage = detail?.postPage ?? page
        lastLoadedPage = firstLoadedPage
        totalPages = detail?.postPageCount ?? page
        loadedRefreshID = refreshID
        isLoading = true
        error = nil
        defer { if loadID == operation { isLoading = false } }
        let sessionRevision = account.revision
        let collectionRevision = account.collections.revision
        do {
            let result = try await account.website.thread(id: post.id, page: page, includeBlocked: showsBlocked,
                                                          force: force, summary: post)
            try Task.checkCancellation()
            guard loadID == operation, threadKind == key.kind else { return }
            account.synchronizeAfterRequest(expectedRevision: sessionRevision)
            guard account.revision == sessionRevision else { return }
            setDetail(result)
            account.collections.observe([post.id], collected: result.collected == true, expectedRevision: collectionRevision)
            if let date = result.comments.first(where: { $0.floorIndex == 0 })?.time.date { createdDate = date }
            firstLoadedPage = result.postPage
            lastLoadedPage = result.postPage
            totalPages = result.postPageCount
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled, loadID == operation, threadKind == key.kind else { return }
            account.synchronizeAfterRequest(expectedRevision: sessionRevision)
            guard account.revision == sessionRevision else { return }
            if let accessError = error as? PostAccessError { showAccessError(accessError) }
            else { self.error = error }
        }
    }
}
