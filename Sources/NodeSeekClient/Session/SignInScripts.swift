enum SignInScripts {
    // Public Turnstile application key used by the site's sign-in page.
    static let document = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <style>body{margin:0;background:transparent}#verification{display:flex;justify-content:center;padding:8px 0}</style>
    <script>
    window.__verification={state:'loading',token:''};
    function verificationReady(){
        try {
            window.__verification={state:'pending',token:''};
            window.__widget=turnstile.render('#verification',{
                sitekey:'0x4AAAAAAAaNy7leGjewpVyR',theme:'auto',
                callback:token=>{window.__verification={state:'ready',token};},
                'expired-callback':()=>{window.__verification={state:'expired',token:''};},
                'timeout-callback':()=>{window.__verification={state:'expired',token:''};},
                'error-callback':()=>{window.__verification={state:'error',token:''};}
            });
        }catch{window.__verification={state:'error',token:''};}
    }
    function resetVerification(){
        if(window.turnstile&&window.__widget!==undefined){window.__verification={state:'pending',token:''};turnstile.reset(window.__widget);}
        else{
            window.__verification={state:'loading',token:''};
            document.getElementById('turnstile-loader')?.remove();
            const script=document.createElement('script');script.id='turnstile-loader';script.async=true;
            script.src='https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=verificationReady';
            script.onerror=()=>{window.__verification={state:'error',token:''};};document.head.append(script);
        }
    }
    </script>
    <script id="turnstile-loader" src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=verificationReady" async defer onerror="window.__verification={state:'error',token:''}"></script>
    </head><body><div id="verification"></div></body></html>
    """#

    static let submit = #"""
    try {
        if(location.origin!=='https://www.nodeseek.com')throw new Error('登录页面地址不正确，请重新打开。');
        const headers={'Content-Type':'application/json',...(token?{'x-captcha-token':token,'x-captcha-source':'turnstile'}:{})};
        const response=await fetch('/api/account/signIn',{method:'POST',credentials:'same-origin',cache:'no-store',headers,body,signal:AbortSignal.timeout(15000)});
        let result;try{result=await response.json();}catch{throw new Error('官网未返回可读取的数据 ('+response.status+')，请使用官网登录。');}
        if(typeof result.success!=='boolean')throw new Error(result.message||'官网返回了无法读取的登录结果。');
        return JSON.stringify(result);
    }catch(e){return JSON.stringify({__error:e.name==='TimeoutError'?'登录请求超时，请检查登录状态后再试。':e.message||String(e)});}
    """#
}
