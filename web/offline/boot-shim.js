/* 在站点 index.html 的 head 最前面执行，早于 jquery 与 min.js。
 *
 * 站点把数据请求写成绝对路径（/getWeapon.php、/data/json/enemies-min.json），
 * 放到子目录下会打到域根。这里把它们改回本地文件，其余请求原样放行。
 * 顺带把语言设成中文，使 localeLang 生效。
 */
(function () {
  var nativeFetch = window.fetch;
  var MAP = null;

  window.lang = 'zh';

  function parse(u) {
    try { return new URL(String(u), location.href); } catch (e) { return null; }
  }

  function empty(body) {
    return Promise.resolve(new Response(body || '', { status: 200 }));
  }

  /// iOS 包里 fetch 不可用（自定义 scheme 不在 Fetch API 允许的 scheme 之列），
  /// 数据改由 site/data-bundle.js 预注入。这里在内存里造响应，一个字节都不走网络。
  function inlineBody(raw) {
    var D = window.__WF_INLINE;
    if (!D) return null;
    if (raw.indexOf('enemies-min.json') !== -1) {
      return JSON.stringify(D.enemies || []);
    }
    if (raw.indexOf('getWeapon.php') !== -1) {
      var name = '';
      try { name = new URL(String(raw), location.href).searchParams.get('name') || ''; } catch (e) {}
      var w = (D.weapons || {})[name];
      return JSON.stringify(w || { error: 'no weapon ' + name });
    }
    return null;
  }

  window.fetch = function (input, init) {
    var raw = typeof input === 'string' ? input : (input && input.url) || '';

    var inline = inlineBody(raw);
    if (inline !== null) return empty(inline);

    var url = parse(raw);
    var href = url ? url.href : raw;

    if (href.indexOf('getWeapon.php') !== -1) {
      var name = (url && url.searchParams.get('name')) || '';
      if (!MAP) MAP = window.__WF_WEAPONS || {};
      var file = MAP[name] || name.replace(/\s+/g, '_') + '.json';
      return nativeFetch.call(window, 'weapons/' + encodeURIComponent(file), init);
    }

    if (href.indexOf('enemies-min.json') !== -1) {
      return nativeFetch.call(window, 'data/json/enemies-min.json', init);
    }

    // 图标在计算里只用于渲染，不需要真实字节
    if (href.indexOf('getImg.php') !== -1) return empty('');

    // 跨域资源（字体、统计）离线时必然失败，直接给空响应，避免控制台噪声与等待
    if (url && url.origin !== location.origin) return empty('{}');

    // 同域的绝对路径 → 相对路径，从站点子目录解析
    if (raw.charAt(0) === '/') {
      return nativeFetch.call(window, raw.slice(1), init);
    }

    return nativeFetch.call(window, input, init);
  };
})();
