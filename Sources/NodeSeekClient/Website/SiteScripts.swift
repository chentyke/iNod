enum SiteScripts {
    // Selectors and fields read from the live NodeSeek website on 2026-10-15.
    static func feed(includeBlocked: Bool = false) -> String {
        #"""
        const includeBlocked = \#(includeBlocked);
        const clean = e => e?.textContent?.trim() || '';
        const count = value => parseInt(String(value ?? '').replace(/,/g, ''), 10) || 0;
        const categories = window.__config__?.allCategory ?? [];
        const categoryName = key => categories.find(c => c.key === key)?.cn_text || '';
        const current = new URL(location.href);
        const currentPage = Number(current.pathname.match(/page-(\d+)/)?.[1] || current.searchParams.get('page') || 1);
        // The website renders the carousel from rotateTopics after the page loads.
        const topics = window.__config__?.rotateTopics;
        const isFeed = current.pathname === '/' || current.pathname.startsWith('/categories/');
        const showsCarousel = isFeed && currentPage === 1 && Array.isArray(topics);
        const pinnedIDs = new Set();
        const pinnedPosts = (showsCarousel ? topics : []).flatMap(topic => {
            const id = Number(topic?.postId);
            if (!Number.isSafeInteger(id) || id <= 0 || pinnedIDs.has(id) || (!includeBlocked && topic.blocked)) return [];
            const title = typeof topic.titleText === 'string' ? topic.titleText.trim() : '';
            if (!title) return [];
            pinnedIDs.add(id);
            const categoryKey = topic.category || '';
            return [{
                id, title, author: topic.op?.name || '', authorID: Number(topic.op?.uid) || null,
                avatar: topic.op?.avatar || '', category: topic.categoryWord || categoryName(categoryKey), categoryKey,
                views: count(topic.views), replies: count(topic.comments), activityDate: topic.lastCommentDate || '',
                pinned: true, rank: Number(topic.rank) || null
            }];
        });
        const postSelector = '.post-list-item:not(.topic-carousel-item)' + (includeBlocked ? '' : ':not(.blocked-post)');
        const posts = [...document.querySelectorAll(postSelector)].flatMap(item => {
            const link = item.querySelector('.post-title a[href^="/post-"]');
            const match = link?.getAttribute('href')?.match(/^\/post-(\d+)-\d+/);
            if (!match || pinnedIDs.has(Number(match[1]))) return [];
            const category = item.querySelector('.post-category, a[href^="/categories/"]');
            const categoryKey = category?.getAttribute('href')?.split('/').pop() || item.dataset.category || '';
            const lock = item.querySelector('.post-title use[href="#lock"]');
            const rank = Number(clean(lock?.closest('span')).match(/\d+/)?.[0]) || null;
            const number = selector => count(clean(item.querySelector(selector)));
            return [{
                id: Number(match[1]), title: clean(link),
                author: clean(item.querySelector('.info-author a')),
                authorID: Number(item.querySelector('.info-author a')?.getAttribute('href')?.match(/\/space\/(\d+)/)?.[1]) || null,
                avatar: item.querySelector('.avatar-normal')?.getAttribute('src') || '',
                category: clean(category) || categoryName(categoryKey), categoryKey,
                views: number('.info-views span'), replies: number('.info-comments-count span'),
                activityDate: item.querySelector('time')?.getAttribute('datetime') || '',
                pinned: !!item.querySelector('[title="置顶"]'), rank
            }];
        });
        const hasNextPage = [...document.querySelectorAll('[aria-label="pagination"] a')].some(a => {
            const url = new URL(a.getAttribute('href'), location.origin);
            return Number(url.pathname.match(/page-(\d+)/)?.[1] || url.searchParams.get('page') || 1) > currentPage;
        }) || !!document.querySelector('a.pager-next');
        return JSON.stringify({posts, pinnedPosts, hasNextPage});
        """#
    }

    static let thread = #"""
    const post = window.__config__?.postData;
    if (!post) throw new Error('没有找到帖子内容');
    return JSON.stringify({...post, views: String(post.views), comments: post.comments.filter(c => !c.blocked)});
    """#

    static let article = #"""
    const openingPost = window.__config__?.postData?.comments?.find(comment => comment.floorIndex === 0);
    if (typeof openingPost?.markdown === 'string' && openingPost.markdown.trim()) {
        return JSON.stringify(openingPost.markdown);
    }
    const root = document.querySelector('article.post-content') ?? document.querySelector('article')
        ?? document.querySelector('#nsk-body-left-block, #nsk-frame-block');
    if (!root) throw new Error('官网暂未返回页面内容');
    root.querySelectorAll('script,style,.user-card').forEach(e => e.remove());
    root.querySelectorAll('a[href]').forEach(a => {
        const url = URL.parse(a.getAttribute('href'), location.href);
        if (url && ['https:', 'http:'].includes(url.protocol)) {
            a.replaceWith(document.createTextNode('[' + a.textContent.trim() + '](' + url.href + ')'));
        }
    });
    const markdown = [...root.querySelectorAll('h1,h2,h3,p,li')].map(e => {
        const text = e.textContent.trim();
        return text ? (/^H/.test(e.tagName) ? '## ' : e.tagName === 'LI' ? '- ' : '') + text : '';
    }).filter(Boolean).join('\n\n');
    if (!markdown) throw new Error('官网暂未返回页面内容');
    return JSON.stringify(markdown);
    """#

    private static let postAccess = #"""
    const forumBody = document.querySelector('#nsk-body-left') ?? document.querySelector('#nsk-body');
    if (forumBody && !forumBody.querySelector('.nsk-post, .post-content')) {
        const message = forumBody.textContent.replace(/\s+/g, ' ');
        const rank = message.match(/查看本帖需要\s*Lv\s*(\d+)/i);
        if (rank?.[1] === '255' || message.includes('本帖已经被用户设为私有')) {
            return JSON.stringify({__postAccess:'private'});
        }
        if (rank || (message.includes('权限不足') && message.includes('升级您的用户等级'))) {
            return JSON.stringify({__postAccess:'level', rank:rank ? Number(rank[1]) : null});
        }
        if (message.includes('需要注册用户才能查看')) {
            return JSON.stringify({__postAccess:'signIn'});
        }
    }
    """#

    static let readiness = #"""
    const source = window.__config__?.user;
    const number = value => value !== null && value !== undefined && value !== '' && Number.isFinite(Number(value)) ? Number(value) : null;
    const user = source ? {
        id: number(source.member_id), name: source.member_name,
        coins: number(source.coin), stardust: number(source.stardust),
        topicCount: number(source.nPost), commentCount: number(source.nComment),
        canCustomizeStyle: !!window.__config__.enableCustomedStyle && (number(source.rank)>=2||source.roles?.includes('dev')===true),
        collectionCount: number(source.collectionCount), forumRank: number(source.rank), unreadCount: number(source.unViewedCount?.all)
    } : null;
    return JSON.stringify({
        ready: !!window.__config__ && document.readyState !== 'loading',
        user
    });
    """#

    // Parse the server-rendered document without running its scripts, images, or ads.
    static func document(_ extraction: String, checkingPostAccess: Bool = false) -> String {
        #"""
        try {
            const response = await fetch(path, {credentials:'same-origin', cache:'no-store'});
            if (response.headers.get('cf-mitigated') === 'challenge') {
                return JSON.stringify({__error:'官网需要完成验证，请打开官网后重试。',__needsWebsite:true});
            }
            const checkingPostAccess = \#(checkingPostAccess);
            if (!response.ok && !checkingPostAccess) return JSON.stringify({__status:response.status,__error:'官网请求失败 ('+response.status+')',__needsWebsite:response.status===403});
            const document = new DOMParser().parseFromString(await response.text(), 'text/html');
            \#(checkingPostAccess ? postAccess : "")
            const isForumPage = !!document.querySelector('#nsk-body');
            if (!response.ok) return JSON.stringify({__status:response.status,__error:'官网请求失败 ('+response.status+')',__needsWebsite:response.status===403 && !isForumPage});
            const encoded = document.querySelector('script#temp-script[type="application/json"]')?.textContent.trim();
            if (!encoded && checkingPostAccess && isForumPage) {
                throw new Error('官网没有返回可读取的帖子内容。');
            }
            if (!encoded) return JSON.stringify({__error:'官网需要完成验证，请打开官网后重试。',__needsWebsite:true});
            const config = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(encoded), c=>c.charCodeAt(0))));
            if (!config || typeof config !== 'object' || !Array.isArray(config.allCategory)) throw new Error('官网数据格式发生变化');
            const window = {__config__:config};
            const location = new URL(response.url);
            const content = (() => {
        """# + extraction + #"""
            })();
            const authentication = (() => {
        """# + readiness + #"""
            })();
            return {content, authentication};
        } catch(e) { return JSON.stringify({__error:e.message||String(e)}); }
        """#
    }

    /// Reads the document the page has just loaded, in the same shape as `document(_:)`.
    static func loadedDocument(_ extraction: String) -> String {
        #"""
        try {
            const content = (() => {
        """# + extraction + #"""
            })();
            const authentication = (() => {
        """# + readiness + #"""
            })();
            return {content, authentication};
        } catch(e) { return JSON.stringify({__error:e.message||String(e)}); }
        """#
    }

    static let post = #"""
    const response = await fetch(path, {
        method: 'POST', credentials: 'same-origin',
        headers: {'Content-Type': 'application/json', ...(token ? {'csrf-token': token} : {})},
        body: body
    });
    let result;try {result=await response.json();} catch {return JSON.stringify({__error:'官网未返回可读取的数据 ('+response.status+')',__needsWebsite:response.status===403});}
    if (!response.ok || result.success === false) return JSON.stringify({__error:result.message||'请求失败 ('+response.status+')',__needsWebsite:response.status===403});
    return JSON.stringify(result);
    """#

    static let get = #"""
    const response = await fetch(path, {credentials: 'same-origin', cache: 'no-store'});
    let result;try {result=await response.json();} catch {return JSON.stringify({__error:'官网未返回可读取的数据 ('+response.status+')',__needsWebsite:response.status===403});}
    if (!response.ok || result.success === false) return JSON.stringify({__error:result.message||'请求失败 ('+response.status+')',__needsWebsite:response.status===403});
    return JSON.stringify(result);
    """#
}
