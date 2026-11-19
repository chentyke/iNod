import NodeSeekCore
import NodeSeekClient
import SwiftUI

struct FeedView: View {
    var isSearch = false
    var recommended = false
    var isLinkedPage = false
    var selectedPostID: Int? = nil
    @Environment(\.openPost) private var openPost
    @Environment(\.openMemberDestination) private var openMember
    @Environment(AccountSession.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if targetEnvironment(macCatalyst)
    @Environment(MacToolbarModel.self) private var macToolbar: MacToolbarModel?
    #endif
    @AppStorage("showsBlockedContent") private var showsBlocked = false
    private var categories: CategoryStore { account.categories }
    /// The list column's width, which the Mac toolbar search field follows.
    @State private var listWidth: CGFloat = 0
    @State private var posts: [PostSummary] = []
    @State private var pinnedPosts: [PostSummary] = []
    @State private var category = ""
    @State private var sort = FeedSort.replyTime
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var page = 1
    @State private var hasNextPage = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: LoadFailure?
    @State private var nextPageError: String?
    @State private var showsVerification = false
    @State private var showsSignIn = false
    @State private var collectionError: (postID: Int, collected: Bool, revision: Int, message: String)?
    @State private var showsCollectionError = false
    @State private var refreshID = UUID()
    @State private var loadID = UUID()
    @State private var loadedKey: SiteRequestKey?
    @State private var loadedRefreshID: UUID?
    @State private var showsCategories = false
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var actionSymbolSize = 20.0
    @State private var showsEditor = false
    @State private var openingNewPost = false
    @State private var newPostError: String?
    @State private var showsNewPostError = false

    init(
        isSearch: Bool = false,
        recommended: Bool = false,
        initialCategory: String = "",
        initialSort: FeedSort = .replyTime,
        initialQuery: String = "",
        isLinkedPage: Bool = false,
        selectedPostID: Int? = nil
    ) {
        self.isSearch = isSearch
        self.recommended = recommended
        self.isLinkedPage = isLinkedPage
        self.selectedPostID = selectedPostID
        _category = State(initialValue:initialCategory); _sort = State(initialValue:initialSort)
        _query = State(initialValue:initialQuery); _submittedQuery = State(initialValue:initialQuery)
    }

    private var requestKey: String { "\(showsBlocked)|\(category)|\(sort.rawValue)|\(submittedQuery)|\(refreshID)|\(account.revision)" }
    private var feedKind: String { showsBlocked ? "feed-including-blocked" : "feed" }
    private var firstPageKey: SiteRequestKey {
        account.website.feedKey(route(page: 1), includeBlocked: showsBlocked, viewerID: account.user?.id)
    }
    private var showsSortInCategoryPicker: Bool { !isSearch && !isLinkedPage }
    /// The community home on a Mac keeps New Post and its category in the sidebar and search in the toolbar over the list, not a row above it.
    private var usesMacToolbar: Bool {
        #if targetEnvironment(macCatalyst)
        !isSearch && !isLinkedPage && !recommended
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isSearch {
                postList
                    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索帖子")
                    .navigationTitle("搜索")
                    .toolbar(.visible,for:.navigationBar)
                    .hidesTabBarWhenPushed()
            } else if isLinkedPage {
                postList.navigationTitle(recommended ? "推荐阅读" : (categories.items.first { $0.id == category }?.title ?? "社区"))
                    .toolbar(.visible,for:.navigationBar).hidesTabBarWhenPushed()
            } else {
                postList
                    .navigationTitle("社区")
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSearch {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("搜索选项", systemImage: "ellipsis") {
                        searchOptions
                    }
                }
            } else if recommended {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: NodeSeekRoute.recommended(page: 1).url) {
                        Label("分享推荐阅读", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        // With a sidebar the category heads it under New Post and search sits in the toolbar over the list, filling the
        // strip above it; a narrow window folds the sidebar into a tab bar, so New Post and the category join search there.
        .macToolbar(.sidebar, items: usesMacToolbar && showsMacSidebar ? [macCategoryItem] : [])
        .macToolbar(.leading, items: usesMacToolbar ? (showsMacSidebar ? [macSearchItem] : [macSearchItem, macCategoryItem, macComposeItem]) : [])
        #if targetEnvironment(macCatalyst)
        .onChange(of: macToolbar?.composeRequests) { if usesMacToolbar { openingNewPost = true } }
        #endif
        .onSubmit(of: .search, submitSearch)
        .onChange(of: query) { if query.isEmpty { submittedQuery = "" } }
        .refreshable { await load(reset: true, force: true) }
        .menuRefreshable { await load(reset: true, force: true) }
        .task(id: requestKey) { await load(reset: true) }
        .task(id: account.revision) { if !recommended { await categories.refresh() } }
        .task(id: openingNewPost) {
            if openingNewPost { await openNewPost() }
        }
        .onDisappear { openingNewPost = false }
        .sheet(isPresented: $showsVerification, onDismiss: { refreshID = UUID() }) { WebsiteView(initialURL: NodeSeekRoute.home.url) }
        .sheet(isPresented: $showsSignIn) { SignInView() }
        .alert("无法打开发帖编辑器", isPresented: $showsNewPostError) {
            Button("重试") { openingNewPost = true }
            Button("取消", role: .cancel) { }
        } message: { Text(newPostError ?? "") }
        .alert("收藏操作未完成", isPresented: $showsCollectionError, presenting: collectionError) { failure in
            Button("重试") {
                guard account.revision == failure.revision else { return }
                Task { await setCollection(failure.collected, for: failure.postID) }
            }
            Button("取消", role: .cancel) { }
        } message: { failure in
            Text(failure.message)
        }
        .sheet(isPresented: $showsCategories) {
            CategoryPicker(selection: $category, sort: showsSortInCategoryPicker ? $sort : nil)
        }
        .sheet(isPresented: $showsEditor) {
            ForumEditorView(request: .init(mode: .newPost, seed: EditorDraft(category: category.isEmpty ? "daily" : category))) { result in
                refreshID = UUID()
                if let redirect = result.redirect, let address = PostAddress(redirect) { openPost(address.summary) }
            }
        }
    }

    @ViewBuilder private var searchOptions: some View {
        NavigationLink(value: AppDestination.memberSearch) { Label("搜索用户", systemImage: "person.crop.circle.badge.magnifyingglass") }
        if let url = googleURL { Link("在 Google 搜索", destination: url) }
    }

    private func submitSearch() {
        submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearchFocused = false
    }

    private var searchAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }

    private func openSearch() {
        withAnimation(searchAnimation) {
            isSearchExpanded = true
        } completion: {
            if isSearchExpanded { isSearchFocused = true }
        }
    }

    private func closeSearch() {
        isSearchFocused = false
        withAnimation(searchAnimation) { isSearchExpanded = false }
        query = ""
        submittedQuery = ""
    }

    private var googleURL: URL? {
        guard !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }
        var c = URLComponents(string:"https://www.google.com/search")
        c?.queryItems = [URLQueryItem(name:"q",value:"site:www.nodeseek.com " + query)]
        return c?.url
    }

    private var postList: some View {
        let matchesVisibility = loadedKey?.kind == feedKind
        let isSwitchingVisibility = !matchesVisibility && (!isSearch || !submittedQuery.isEmpty)
        return List {
            if let error, hasContent {
                // A failed refresh keeps the posts already on screen and notes the problem above them.
                LoadFailureBanner(failure: error, isRetrying: isLoading) { refreshID = UUID() }
                    .listRowInsets(EdgeInsets(top: 4, leading: SeekLayout.gutter, bottom: 6, trailing: SeekLayout.gutter))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                if matchesVisibility {
                    if pinnedPosts.count > 1 {
                        PinnedPostCarousel(posts: pinnedPosts, card: postButton)
                            .id(loadedKey)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    } else if let post = pinnedPosts.first {
                        postRow(post)
                    }
                }
                ForEach(matchesVisibility ? posts : []) { post in
                    postRow(post)
                }
                if (isLoading && !isLoadingMore) || isSwitchingVisibility {
                    // Keep the current list visible while refreshing.
                    if isSwitchingVisibility || (posts.isEmpty && pinnedPosts.isEmpty) {
                        HStack { Spacer(); ProgressView("正在加载"); Spacer() }.listRowSeparator(.hidden)
                    }
                } else if isSearch && submittedQuery.isEmpty {
                    ContentUnavailableView("搜索社区帖子", systemImage: "magnifyingglass", description: Text("输入标题或关键词。"))
                        .listRowSeparator(.hidden)
                } else if hasNextPage && error == nil && loadedKey == firstPageKey && loadedRefreshID == refreshID {
                    LoadMoreRow(error: nextPageError) {
                        await load(reset: false, force: nextPageError != nil)
                    }
                    .id(page)
                } else if posts.isEmpty && pinnedPosts.isEmpty && error == nil {
                    if recommended {
                        ContentUnavailableView("暂无推荐阅读", systemImage: "rosette", description: Text("下拉刷新以重新获取社区精选主题。"))
                            .listRowSeparator(.hidden)
                    } else {
                        ContentUnavailableView("没有找到帖子", systemImage: "magnifyingglass", description: Text("换个关键词，或浏览其他版块。"))
                            .listRowSeparator(.hidden)
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)
        }
        .listStyle(.plain)
        .overlay {
            if let error, !hasContent, !isSwitchingVisibility {
                LoadFailureView(failure: error, isRetrying: isLoading,
                                offersWebsite: account.website.needsWebsite,
                                websiteURL: recommended ? NodeSeekRoute.recommended(page: 1).url : NodeSeekRoute.home.url,
                                retry: { refreshID = UUID() }, verify: { showsVerification = true })
            }
        }
        .seekCanvas(margins: .keepsGutter)
        .contentMargins(.vertical, recommended ? 8 : 6, for: .scrollContent)
        // On a Mac the filter row's controls live in the window toolbar and sidebar, so the list starts right under the toolbar.
        .modifier(OptionalFeedFilterBar(isEnabled: !recommended && !usesMacToolbar) { filterBar })
        .modifier(MacToolbarFadeIf(isEnabled: usesMacToolbar))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { listWidth = $0 }
        // An open search folds away once the reader scrolls, taps outside it or leaves the page;
        // a search with results only drops the keyboard.
        .scrollDismissesKeyboard(.immediately)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { foldSearchIfEmpty() }
        }
        .gesture(TapGesture().onEnded { foldSearchIfEmpty() },
                 including: isSearchExpanded && !isSearch ? .all : .subviews)
        .onAppear { isSearchFocused = false }
        .onDisappear {
            isSearchFocused = false
            foldSearchIfEmpty()
        }
        #if DEBUG
        .modifier(UITestPostOpener(posts: posts, isEnabled: !isSearch && !recommended && !isLinkedPage))
        #endif
    }

    private var hasContent: Bool { !posts.isEmpty || !pinnedPosts.isEmpty }

    private func foldSearchIfEmpty() {
        guard isSearchExpanded else { return }
        isSearchFocused = false
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { closeSearch() }
    }

    private func postRow(_ post: PostSummary) -> some View {
        postButton(post)
            .postCardRow()
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                collectionButton(for: post.id).tint(.seekGreen)
            }
    }

    private func selectPost(_ post: PostSummary) {
        isSearchFocused = false
        foldSearchIfEmpty()
        openPost(post)
    }

    private func postButton(_ post: PostSummary) -> some View {
        let isSelected = selectedPostID == post.id
        return Button { selectPost(post) } label: { PostRow(post: post, isSelected: isSelected) }
            .buttonStyle(.seekCard)
            .hoverEffect(.highlight)
            .postTransitionSource(post)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                Button("阅读全文", systemImage: "doc.text") { selectPost(post) }
                if let id = post.authorID {
                    Button { openMember(.profile(id)) } label: {
                        Label("查看作者主页", systemImage: "person.crop.circle")
                    }
                }
                collectionButton(for: post.id)
                ShareLink(item: post.url)
            } preview: {
                PostPreview(post: post)
                    .environment(account)
            }
    }

    private func collectionButton(for postID: Int) -> some View {
        let isCollected = account.collections.status(postID) == true
        return Button(isCollected ? "取消收藏" : "收藏", systemImage: isCollected ? "bookmark.slash" : "bookmark") {
            Task { await setCollection(!isCollected, for: postID) }
        }
        .disabled(account.collections.updating.contains(postID))
    }

    private func setCollection(_ collected: Bool, for postID: Int) async {
        do {
            if try await account.confirmSignedIn() {
                try await account.collections.setCollected(collected, postID: postID)
            } else {
                showsSignIn = true
            }
        } catch is CancellationError {
        } catch {
            collectionError = (postID, collected, account.revision, SiteError.displayMessage(for: error))
            showsCollectionError = true
        }
    }

    private func openNewPost() async {
        defer { if !Task.isCancelled { openingNewPost = false } }
        do {
            try await account.withConfirmedSignIn(onSignedOut: { showsSignIn = true }) { _ in
                showsEditor = true
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            newPostError = SiteError.displayMessage(for: error)
            showsNewPostError = true
        }
    }

    private var filterBar: some View {
        let categoryTitle = categories.items.first { $0.id == category }?.title ?? category
        let sortSelection = showsSortInCategoryPicker ? nil : $sort
        return FeedFilterBar(category: categoryTitle, sort: sortSelection, onCategories: { showsCategories = true },
                             isSearchExpanded: isSearchExpanded) {
            FeedSearchBar(query: $query, isExpanded: isSearchExpanded, focus: $isSearchFocused,
                          onSubmit: submitSearch, onOpen: openSearch, onClose: closeSearch)
        } actions: {
            if !isSearch { newPostButton }
        }
    }

    private var showsMacSidebar: Bool {
        #if targetEnvironment(macCatalyst)
        macToolbar?.tracksSidebar ?? true
        #else
        false
        #endif
    }

    private var macComposeItem: MacToolbarItem {
        MacToolbarItem(id: MacToolbarItem.composeID, label: "发布帖子", systemImage: "square.and.pencil",
                       isEnabled: !openingNewPost) { openingNewPost = true }
    }

    private var macSearchItem: MacToolbarItem {
        // Beside the sidebar the field sits alone over the list, so it spans the cards below it.
        let cardWidth = min(listWidth - 2 * SeekLayout.gutter, SeekLayout.readableWidth)
        return MacToolbarItem(id: "search", label: "搜索帖子", systemImage: "magnifyingglass",
                              kind: .search(prompt: "搜索帖子", text: query),
                              width: showsMacSidebar && cardWidth > 0 ? cardWidth.rounded() : nil,
                              action: submitSearch, onTextChange: { query = $0 })
    }

    private var macCategoryItem: MacToolbarItem {
        let categoryTitle = categories.items.first { $0.id == category }?.title ?? category
        var sections: [[MacToolbarMenuEntry]] = []
        if showsSortInCategoryPicker {
            sections.append(FeedSort.allCases.map { option in
                MacToolbarMenuEntry(id: "sort.\(option.rawValue)", title: option.title, isOn: sort == option) { sort = option }
            })
        }
        sections.append(categories.items.map { item in
            MacToolbarMenuEntry(id: "category.\(item.id)", title: item.title, systemImage: item.symbol,
                                isOn: category == item.id) { category = item.id }
        })
        return MacToolbarItem(id: "category", label: "选择版块，当前\(categoryTitle)", systemImage: "line.3.horizontal.decrease",
                              kind: .menu(title: categoryTitle, sections: sections))
    }

    private var newPostButton: some View {
        let size = min(actionSymbolSize, 32)
        return Button {
            openingNewPost = true
        } label: {
            FeedSearchSymbol(alternate: .add, progress: 1)
                .stroke(style: StrokeStyle(lineWidth: size * 0.095, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("发布帖子")
        .keyboardShortcut("n", modifiers: .command)
        .disabled(openingNewPost)
        .glassEffect(.clear.tint(.black).interactive(), in: .circle)
    }

    private func route(page: Int) -> NodeSeekRoute {
        if recommended { return .recommended(page: page) }
        if submittedQuery.isEmpty { return .feed(category: category, sort: sort, page: page) }
        return .search(query: submittedQuery, category: category, sort: sort, page: page)
    }

    private func load(reset: Bool, force: Bool = false) async {
        let key = firstPageKey
        let request = requestKey
        let force = force || (loadedRefreshID != nil && loadedRefreshID != refreshID)
        if reset {
            if !force, loadedKey == key, !posts.isEmpty || !pinnedPosts.isEmpty { return }
        } else {
            guard !isLoading, hasNextPage, error == nil, loadedKey == key, loadedRefreshID == refreshID else { return }
        }
        let operation = UUID()
        loadID = operation
        defer {
            if loadID == operation {
                isLoading = false
                isLoadingMore = false
            }
        }
        nextPageError = nil
        if isSearch && submittedQuery.isEmpty {
            posts = []
            pinnedPosts = []
            error = nil
            hasNextPage = false
            return
        }
        let requestedPage = reset ? 1 : page + 1
        let route = route(page: requestedPage)
        loadedRefreshID = refreshID
        if reset {
            if loadedKey != key { posts = []; pinnedPosts = []; hasNextPage = false; page = 1 }
            if posts.isEmpty, pinnedPosts.isEmpty, let cached: FeedPage = account.website.cached(key: key) {
                posts = cached.posts; pinnedPosts = cached.pinnedPosts; hasNextPage = cached.hasNextPage
            }
            loadedKey = key
        }
        isLoading = true
        isLoadingMore = !reset
        error = nil
        let sessionRevision = account.revision
        do {
            let result = try await account.website.feed(route,includeBlocked:showsBlocked,force:force)
            try Task.checkCancellation()
            guard loadID == operation, requestKey == request else { return }
            account.synchronizeAfterRequest(expectedRevision: sessionRevision)
            guard account.revision == sessionRevision else { return }
            if reset {
                posts = result.posts
                pinnedPosts = result.pinnedPosts
            } else {
                var pinnedIDs = Set(pinnedPosts.map(\.id))
                let newPins = result.pinnedPosts.filter { pinnedIDs.insert($0.id).inserted }
                if !newPins.isEmpty {
                    pinnedPosts += newPins
                    posts.removeAll { pinnedIDs.contains($0.id) }
                }
                var existingIDs = pinnedIDs
                existingIDs.formUnion(posts.map(\.id))
                posts += result.posts.filter { existingIDs.insert($0.id).inserted }
            }
            page = requestedPage
            hasNextPage = result.hasNextPage
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, loadID == operation, requestKey == request else { return }
            account.synchronizeAfterRequest(expectedRevision: sessionRevision)
            if reset { self.error = LoadFailure(error) }
            else { nextPageError = SiteError.displayMessage(for: error) }
        }
    }
}

private struct MacToolbarFadeIf: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled { content.fadesUnderMacToolbar() } else { content }
    }
}

private struct OptionalFeedFilterBar<Bar: View>: ViewModifier {
    let isEnabled: Bool
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        if isEnabled {
            content.safeAreaBar(edge: .top, spacing: 0, content: bar)
        } else {
            content
        }
    }
}
