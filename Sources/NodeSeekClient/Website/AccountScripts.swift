enum AccountScripts {
    static let read = #"""
    try {
        const get = async url => {
            const r = await fetch(url, {credentials:'same-origin', cache:'no-store'});
            let j;
            try { j = await r.json(); } catch { throw new Error('请求失败 (' + r.status + ')'); }
            if (!r.ok || j.success === false) throw new Error(j.message === 'USER NOT FOUND' ? '没有找到这位用户，请检查用户编号。' : (j.message || '请求失败 (' + r.status + ')'));
            return j;
        };
        const n = v => {
            const x = Number(v);
            if (v === null || v === undefined || !Number.isFinite(x)) throw new Error('官网数据格式发生变化，请稍后重试');
            return x;
        };
        const optional = v => v === null || v === undefined ? null : n(v);
        const array = v => { if (!Array.isArray(v)) throw new Error('官网没有返回列表，请重试'); return v; };
        const plainText = html => {
            const doc = new DOMParser().parseFromString(String(html), 'text/html');
            doc.querySelectorAll('script,style').forEach(e => e.remove());
            doc.querySelectorAll('img').forEach(e => e.replaceWith(doc.createTextNode(e.alt || '[图片]')));
            doc.querySelectorAll('br,p,div,li').forEach(e => e.append(' '));
            return (doc.body.textContent || '').replace(/\s+/g, ' ').trim();
        };
        let result;
        if (kind === 'security') {
            const [otp, history] = await Promise.all([get('/api/account/otp-status'),get('/api/account/signIn-history')]);
            if (typeof otp.enabled !== 'boolean') throw new Error('无法读取双因素验证状态');
            result = {twoFactorEnabled:otp.enabled, history:array(history.historyIp).map((r,i)=>({id:String(i)+'-'+r.time,ip:r.ip,createdAt:String(r.time)}))};
        } else {
            const j = await get(path);
            if (['topics','replies','collections'].includes(kind)) {
                const rows = array(j[{topics:'discussions',replies:'comments',collections:'collections'}[kind]]);
                result = {items:rows.map(r=>({id:String(r.post_id)+'-'+(r.floor_id||0),postID:n(r.post_id),title:r.title,floor:kind==='replies'?n(r.floor_id):0,excerpt:r.text == null ? null : plainText(r.text),rank:optional(r.rank)})),hasNext:rows.length === 15};
            } else if (kind === 'notices') {
                result = {items:array(j.data).map(r=>({id:n(r.id),viewed:!!r.viewed,postID:n(r.post_id),title:r.title,floor:n(r.floor_id),authorID:n(r.commenter_id),author:r.commenter_name,createdAt:r.created_at})),hasNext:false};
            } else if (kind === 'messages') {
                const peers = new Map();
                for (const r of array(j.msgArray)) {
                    const peer = r.sender_id === userID ? r.receiver_id : r.sender_id;
                    const value = {id:n(peer),latestMessageID:optional(r.id),name:peer===r.sender_id?r.sender_name:r.receiver_name,preview:r.content,isMarkdown:!!r.is_markdown,createdAt:r.created_at,viewed:r.sender_id===userID||!!r.viewed};
                    const previous = peers.get(peer);
                    if (!previous || new Date(value.createdAt)>new Date(previous.createdAt) ||
                        (value.createdAt===previous.createdAt && (value.latestMessageID??0)>(previous.latestMessageID??0))) peers.set(peer,value);
                }
                result = {items:[...peers.values()].sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt)),hasNext:false};
            } else if (kind === 'conversation') {
                const peer = j.talkTo;
                if (!peer || n(peer.member_id) !== memberID) throw new Error('没有找到这位用户的会话');
                result = {peer:{id:n(peer.member_id),name:peer.member_name},items:array(j.msgArray).map(r=>({id:n(r.id),senderID:n(r.sender_id),receiverID:n(r.receiver_id),content:r.content,createdAt:r.created_at,isMarkdown:!!r.is_markdown,viewed:!!r.viewed})).sort((a,b)=>a.id-b.id)};
            } else if (kind === 'credit') {
                const rows = array(j.data);
                result = {items:rows.map((r,i)=>({id:path+'-'+i+'-'+r[3],change:n(r[0]),balance:n(r[1]),reason:String(r[2]),createdAt:String(r[3]),peerID:null})),hasNext:page<Math.min(100,Math.ceil(n(j.total)/20))};
            } else if (kind === 'stardust') {
                const types={system:'系统',admin:'管理',transfer:'转账',upvote:'点赞',buyCode:'购买邀请码'};
                result = {items:array(j.records).map(r=>({id:String(r.id),change:n(r.diff),balance:n(r.result),reason:types[r.type]||r.type,createdAt:r.created_at,peerID:optional(r.peer_id)})),hasNext:!!j.exist_more,cursor:optional(j.cursor)};
            } else if (kind === 'attendance') {
                result = {gain:j.record?optional(j.record.gain):null,order:optional(j.order),createdAt:j.record?.created_at==null?null:String(j.record.created_at),total:n(j.total),items:array(j.list).map((r,i)=>({id:n(r.member_id),name:r.member_name,gain:n(r.gain),rank:(page-1)*50+i+1})),hasNext:page*50<n(j.total)};
            } else if (kind === 'profile') {
                const r=j.detail;
                if (!r || n(r.member_id) !== memberID) throw new Error('没有找到这位用户');
                result = {id:n(r.member_id),name:r.member_name,bio:r.bio??null,readme:r.readme??null,signature:r.signature_markdown??null,createdAt:r.created_at??null,coins:optional(r.coin),stardust:optional(r.stardust),topics:optional(r.nPost),replies:optional(r.nComment),follows:optional(r.follows),fans:optional(r.fans),followed:typeof r.followed==='boolean'?r.followed:null};
            } else if (kind === 'blocks') {
                result = {items:array(j.data).map(r=>({id:n(r.block_member_id),name:r.block_member_name})),hasNext:false};
            } else if (kind === 'homepage') {
                const saved=new Map(array(j.data).map(r=>[r.category,!!r.showInIndex]));
                result={items:array(window.__config__?.allCategory).filter(r=>r.customizable).map(r=>({id:r.key,title:r.cn_text,enabled:saved.has(r.key)?saved.get(r.key):!!r.showInIndex})),hasNext:false};
            } else throw new Error('不支持的账号页面');
        }
        return JSON.stringify(result);
    } catch (e) { return JSON.stringify({__error:e.message||String(e)}); }
    """#

    static let action = #"""
    try {
        const r=await fetch(path,{method:'POST',credentials:'same-origin',headers:{...(body?{'Content-Type':'application/json'}:{}),...headers},...(body?{body}:{})});
        if (path === '/api/account/signOut' && r.ok) return JSON.stringify({success:true});
        let j; try { j=await r.json(); } catch { return JSON.stringify({__error:'官网未返回可读取的数据 ('+r.status+')',__needsWebsite:r.status===403}); }
        if (!r.ok) return JSON.stringify({__error:j.message||'请求失败 ('+r.status+')',__needsWebsite:r.status===403});
        if (j.success !== true) throw new Error(j.message||'操作未成功，请稍后重试');
        return JSON.stringify(j);
    } catch(e) { return JSON.stringify({__error:e.message||String(e)}); }
    """#

    static let uploadAvatar = #"""
    const bytes=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));
    const body=new FormData();
    body.append('token','123456798');body.append('name','avatar');
    body.append('img',new Blob([bytes],{type:'image/png'}),'img.png');
    const response=await fetch('/api/avatar/upload',{method:'POST',credentials:'same-origin',headers:{'x-csrf-challenge':'simple-token'},body});
    let result;try {result=await response.json();} catch {return JSON.stringify({__error:'官网未返回可读取的数据 ('+response.status+')',__needsWebsite:response.status===403});}
    if(!response.ok||result.success!==true) return JSON.stringify({__error:result.message||'头像上传失败 ('+response.status+')',__needsWebsite:response.status===403});
    return JSON.stringify(result);
    """#
    static let request = #"""
    try {
        if(path.startsWith('/api/vote/')||path.startsWith('/api/stardust/')) {
            const text=[method,new URL(path,location.origin).href,navigator.userAgent||'',body||''].join('\n\n');
            const digest=await crypto.subtle.digest('SHA-1',new TextEncoder().encode(text));
            headers={...headers,'x-dynamic-sign':[...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,'0')).join('')};
        }
        if(path==='/api/invite/buyOne') {
            let token=localStorage.getItem('csrf_token');
            if(/^\w+\.\w+$/.test(token||'')){localStorage.setItem('security_token',token);localStorage.removeItem('csrf_token');token=null;}
            if(!token) throw new Error('请先打开官网的邀请页面完成验证，再返回购买。');
            headers={...headers,'x-csrf-challenge':'simple-token','x-csrf-token':token};
        }
        const response = await fetch(path,{method,credentials:'same-origin',cache:'no-store',headers:{...(body ? {'Content-Type':'application/json'} : {}),...headers},...(body?{body}:{})});
        if(response.headers.get('x-security-token')) localStorage.setItem('security_token',response.headers.get('x-security-token'));
        if(response.headers.get('x-csrf-token')) localStorage.setItem('csrf_token',response.headers.get('x-csrf-token'));
        let result;try {result=await response.json()} catch {return JSON.stringify({__error:'官网未返回可读取的数据 ('+response.status+')',__needsWebsite:response.status===403});}
        if(!response.ok||result.success===false) return JSON.stringify({__error:result.message||(response.ok?'官网暂时没有返回这项内容，请稍后重试。':('请求失败 ('+response.status+')')),__needsWebsite:response.status===403});
        return JSON.stringify(result);
    } catch(e) {return JSON.stringify({__error:e.message||String(e)});}
    """#

}
