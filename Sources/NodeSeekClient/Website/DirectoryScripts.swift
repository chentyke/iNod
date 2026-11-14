enum DirectoryScripts {
    static let read =
        #"""
        const links=[...document.querySelectorAll(location.pathname==='/providers'?'.provider a[href]':'a[title][href]')];
        const seen=new Set();
        return JSON.stringify(links.flatMap(a=>{
            if(!a.querySelector('img')||a.closest('footer,header'))return [];
            const title=a.title||a.textContent.trim(),url=new URL(a.getAttribute('href'),location.origin);
            if(!title||!['http:','https:'].includes(url.protocol)||seen.has(url.href))return [];
            if(location.pathname==='/friends'&&url.origin===location.origin)return [];
            seen.add(url.href);const image=a.querySelector('img')?.getAttribute('src');
            return [{title,url:url.href,image:image?new URL(image,location.origin).href:null}];
        }));
        """#

}
