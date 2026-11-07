**English** | [简体中文](./developer-guide.md)

# 🛠️ Developer Guide

> For contributors and source authors: environment setup, project structure, and most importantly — the **tiered source-authoring tutorial** (Basic / Intermediate / Advanced) with full examples.
>
> 📚 Online source-authoring tutorial (bilingual with more demos): <https://nexhub-app.github.io/website/>; this document is consistent with it and kept in sync.

## 4.1 Environment

- Install the [Flutter SDK](https://flutter.dev) (this project requires **Flutter 3.47.0**, Dart 3.x);
- Set up the build environment for your platform (Android Studio / Xcode / Visual Studio, etc.);
- Confirm `flutter doctor` shows no significant errors.

## 4.2 Get & run the code

```bash
git clone https://github.com/nexhub-app/nexhub.git
cd nexhub
flutter pub get
flutter run
```

Pick a target device (emulator / real device / desktop) to launch.

## 4.3 Build release packages

```bash
# Android
flutter build apk
# Windows
flutter build windows
# and so on for other platforms
```

## 4.4 Project structure

```
nexhub/
├── lib/                  # App main code (Dart)
│   ├── core/             # Core capabilities: networking, resolver dispatch, source repo, reader/player infra
│   │   ├── models/       # Data models (e.g. PluginConfig source config)
│   │   ├── resolver/     # Resolver engine dispatch (builtin / script / webview / hybrid)
│   │   ├── scraper/      # List/detail/chapter scraping & extraction
│   │   └── services/     # Source repo, history, download services
│   ├── features/         # Feature modules: home, source management, manga, novel, video, settings, download…
│   └── l10n/             # i18n resources (Chinese / English)
├── assets/               # Assets (icons, generic hot-search words, etc.; no site sources)
├── plugins/              # Source directory (see below)
│   └── builtin/          # ⚠️ placeholder only in this repo; no source JSON is committed
├── test/                 # Unit tests (incl. source JSON validation; auto-skipped with no built-in sources)
├── android/ ios/ linux/ macos/ windows/ web/   # Per-platform projects
└── pubspec.yaml          # Dependencies & asset declarations
```

**About `plugins/builtin/`**: this repo **does not** commit any `.json` source files there (excluded in `.gitignore`). The directory exists only as a `.gitkeep` placeholder to keep the project structure complete and buildable. Real sources live locally or come from the community — **not in the public repo**.

**Content that is excluded and must never be committed**:

- `plugins/builtin/*.json` (any built-in / prepared sources)
- `reference/` (local source backups and example files)
- Internal dev docs, redevelopment prompts & plans, test-data scan scripts, etc. (under `docs/`, only the whitelisted public docs and their `.en.md` English versions are committed)
- `build/`, `sdk/` (build artifacts and the Flutter SDK; huge)
- `.workbuddy/`, `.trae/`, `.qoder/`, `.probe_tmp/` (local tool & probe temp artifacts)
- Root temp scripts (e.g. `tmp_*.mjs`, `run_probe.*`, `net_check.*`)

---

## 4.5 Source-as-Plugin: how to write and contribute a source

NexHub's parsing capability is fully driven by source JSON. A source is a JSON file describing how to scrape content from a site.

### 4.5.1 Source-level site settings guide (site / network)

Each source's "site metadata" and "network access method" are written in the source file — this is the **source-level site configuration**:

**`site` (required)** — basic site info:

| Key | Type | Description |
| --- | --- | --- |
| `site.domain` | string | Site main domain (e.g. `example.com`) |
| `site.baseUrl` | string | Site root URL (e.g. `https://example.com`), used to join relative links |
| `site.userAgent` | string? | Optional custom UA |
| `site.cookies` | string? | Optional site cookies (e.g. `session=xxx`) |
| `site.headers` | object? | Optional custom request headers |
| `site.mirrors` | array? | Optional mirror list, each `{name, domain, baseUrl}` (auto-switch when the main domain fails) |
| `site.publishPageUrl` | string? | Optional publish-page URL (a navigation page when the main domain fails; mirrors can be extracted from it) |
| `site.publishMirrorSelector` | string? | Optional mirror-extraction rule on the publish page (regex string or CSS selector) |

**`network` (optional, new in v0.4.0)** — source-level network override, letting a source ship "recommended network config":

| Key | Type | Description |
| --- | --- | --- |
| `network.proxy` | object? | Proxy override, e.g. `{ "mode": "manual", "protocol": "http", "host": "...", "port": 7890 }` |
| `network.dns` | object? | DNS override, e.g. `{ "mode": "doh", "dohUrl": "https://cloudflare-dns.com/dns-query" }` or `{ "mode": "custom", "servers": ["8.8.8.8"] }`; also supports `resolveSuffix` / `resolveSuffixDomains` (see below) |
| `network.hosts` | array? | Hosts override, each `{ "ip": "1.2.3.4", "host": "example.com", "enabled": true }` |
| `network.sni` | object? | SNI override, e.g. `{ "enabled": true, "defaultSni": "-" }`; value `-` suppresses SNI entirely, a domain uses that domain as SNI, and `domainSni` maps host patterns (`.example.com` for suffix match) to SNI values |
| `network.ech` | object? | ECH override, e.g. `{ "enabled": true, "echConfigList": "<base64>" }`; native-engine driven, effective for direct HTTPS (see note below) |

Rules: a key that is **absent = inherit global**; a key that is set = **override the whole aspect**. Priority: **user UI override for the source > source JSON `network` block > global settings > defaults**. Invalid values only warn and never disable the source.

> **How `sni` works**: genuinely effective for direct HTTPS connections (the TLS handshake is completed in-app, so SNI can be overridden with the configured value or suppressed with `-`; suppressing SNI together with hosts pinning a reachable IP bypasses SNI-based blocking — the Cloudflare edge accepts no-SNI handshakes and routes by the Host header). Not applied through a proxy.
>
> 💡 ECH is now wired: a built-in native engine (OpenSSL) drives it and it takes effect for direct HTTPS — no external proxy needed. Scopes: app-level (covers any https domain; sites without ECH support fall back per-domain, so normal sites aren't broken), per-source (only the source's site.baseUrl host; toggle via source JSON network.ech or the UI override), and Bangumi-specific. The native lib ships with the Android APK (arm64-v8a / armeabi-v7a / x86_64), the Windows desktop build, and the HarmonyOS HAP (arm64-v8a); macOS / Linux are not bundled yet and auto-degrade to direct. The rest (proxy / dns / hosts / sni) all genuinely work.

> **`dns.resolveSuffix` (resolve suffix, added in v2.0.0)**: the resolver queries *target host + suffix* and connects to the returned address, while the Host header stays the original hostname.
> Use case: when the site's own domain suffers DNS poisoning, query an unaffected alias (e.g. an alias domain served by the site's CDN) to obtain real addresses — **no IP needs to be hard-coded in the config file**, since each device resolves it with its own DNS. That makes it suitable for publicly shared sources.
>
> | Key | Type | Description |
> | --- | --- | --- |
> | `resolveSuffix` | string? | Like `".alias-cdn.example"` (must start with `.`); empty = disabled |
> | `resolveSuffixDomains` | array? | Scope of the suffix: exact domains or `.example.org` for suffix matching. **Empty list = applies to every host**; listing them explicitly is recommended so unrelated hosts (image nodes, etc.) don't pay for a lookup that is bound to fail |
>
> Failure handling: if the suffixed lookup fails or returns nothing, it falls back to resolving the original hostname — never a hard error.
> Typical combo: `{ "mode": "system", "resolveSuffix": "...", "resolveSuffixDomains": ["..."] }` plus `{ "sni": { "enabled": true, "defaultSni": "-" } }`.

### 4.5.2 Source-authoring tutorial (tiered: Basic / Intermediate / Advanced)

This section mirrors the official tutorial: 22 modules in three difficulty tiers, each with an explanation, a field table and a code sample. The online edition (bilingual, with a jumpable table of contents) is at [NexHub site · Source-authoring tutorial](https://nexhub-app.github.io/website/docs-tutorial.html).

> Protocol details follow the actual parsing in `lib/core/models/plugin_config.dart`; this page and the official tutorial are kept in sync, and the code wins if they ever diverge.

#### 🟢 Basics

##### 1. What is a Source

A Source is a JSON file that describes HOW to scrape a specific site for anime / manga / novel / video. NexHub only ships a generic engine; all site-specific parsing lives in this file — that is exactly 'source = plugin'.

The app embeds a JS sandbox: you can use declarative selectors (jsonpath / css / xpath) to extract fields directly, or embed JavaScript in the source to handle complex pages. Anyone can import your source file with one tap, no full app update needed.

##### 2. Basic fields (every source)

Every source starts with these common header fields. Fill them in first so the app can identify, manage and upgrade your source.

Note: the source model does NOT read lang / builtin keys — they are silently ignored, so don't rely on them as functional fields. author is now a real field shown on the source detail page.

Age rating (ageRating) is also a basic field: general (all) / teen (13+/16+) / mature (18+), with aliases like all / 16 / r18 / nsfw accepted; default general. mature is hidden by default from users who have not enabled age confirmation.

The parser.type values are detailed in sections 12-13.

| Field / key | Description |
| --- | --- |
| `id` | Unique id, e.g. manga_demo. Same-id sources upgrade or skip by version; avoid collisions. |
| `name` | Display name, e.g. 'Demo Manga'. |
| `author` | Optional. Source author name (shown on the source detail page, for attribution). |
| `version` | Integer version (coerced to int, default 1). Same-id sources upgrade or skip by version. |
| `type` | Media type: animeSource (video/anime) / mangaSource / novelSource. |
| `site` | Site object (required): domain, baseUrl (root, for relative links), mirrors list; optional userAgent / cookies / headers. |
| `parser` | Parser config: { type, overrides?, script? }. type is builtin / hybrid / script. |
| `ageRating` | Optional. Age rating general / teen / mature; default general, mature hidden by default. |
| `enabled` | Optional, whether enabled (default true). |

```json
{
  "id": "demo_anime",
  "name": "Demo Anime",
  "version": 1,
  "type": "animeSource",
  "ageRating": "general",
  "site": {
    "domain": "example.com",
    "baseUrl": "https://example.com",
    "mirrors": [ { "name": "main", "domain": "example.com", "baseUrl": "https://example.com" } ]
  },
  "parser": { "type": "hybrid", "overrides": { "latest": { "type": "builtin" } } }
}
```

#### 🟡 Intermediate

##### 3. Search module (search / ruleSearch)

Triggered when the user types a keyword. Two paradigms:

- Anime/Manga (Paradigm A): define search url in routes (with {keyword}), then use selectors or script to extract the result list.
- Novel (Paradigm B, Legado-compatible): use ruleSearch with CSS selectors declaring each result's title, author, cover, detail link.

Returned fields usually: id, title, cover, detailUrl.

| Field / key | Description |
| --- | --- |
| `routes.search.url` | Paradigm A: search endpoint, {keyword} for query, {page} for page. |
| `selectors.list / bookList` | Result container selector (jsonpath or css). |
| `selectors.title / bookName` | Title field. |
| `selectors.cover / bookCoverUrl` | Cover URL; relative paths auto-joined to baseUrl. |
| `selectors.id / bookUrl` | Identifier or link used to open detail later. |

```js
// Paradigm A: routes + selectors (anime)
"routes": {
  "search": { "url": "/s?wd={keyword}&page={page}", "method": "get", "responseType": "json" }
},
"selectors": {
  "list": "$.list",
  "title": "$.vod_name",
  "cover": "$.vod_pic",
  "id": "$.vod_id"
}

// Paradigm B: novel ruleSearch (Legado)
"ruleSearch": {
  "bookList": ".bookbox",
  "bookName": ".bookname a@text",
  "bookAuthor": ".author@text",
  "bookCoverUrl": ".bookimg img@src",
  "bookUrl": ".bookname a@href"
}
```

##### 4. Discovery / Category (discovery / ruleExplore)

Used by the Home page and category browsing. Paradigm A uses latest/explore/category routes + categoryEntries; Paradigm B uses ruleExplore + exploreUrl (each line 'Category::URL').

Home sections are defined by homeSections (title, route, style grid/list, limit).

| Field / key | Description |
| --- | --- |
| `category.categoryEntries` | Paradigm A: category array, each {id, title}, plugged into the category route. |
| `homeSections` | Home blocks (latest, popular…) referencing a route with a limit. |
| `exploreUrl` | Paradigm B: newline-separated 'Category::URL' for the explore page. |

```json
"category": {
  "categoryEntries": [
    { "id": "all", "title": "All" },
    { "id": "1", "title": "Anime" },
    { "id": "2", "title": "Movies" }
  ]
},
"homeSections": [
  { "id": "latest", "title": "Latest", "route": "latest", "style": "grid", "limit": 18 }
]
```

##### 5. Detail / Contents (detail / ruleBookInfo)

Loaded when opening a title. Responsible for: title, cover, description, author/cast, tags, status, and the chapter/episode list.

Paradigm A uses detail route + selectors.detail and episodes; Paradigm B uses ruleBookInfo (meta) + ruleToc (chapter list with chapterList / chapterName / chapterUrl).

| Field / key | Description |
| --- | --- |
| `selectors.detail` | Paradigm A: object extracting title/cover/description/cast per field. |
| `selectors.episodes` | Paradigm A: chapter link selector, e.g. ul li a. |
| `ruleBookInfo.tocUrl` | Paradigm B: link into the contents page; empty means detail page itself is the TOC. |
| `ruleToc.chapterList` | Paradigm B: chapter item selector; nextTocUrl supports paginated TOC. |

```js
// Paradigm A
"selectors": {
  "detail": {
    "title": "$.list[0].vod_name",
    "cover": "$.list[0].vod_pic",
    "description": "$.list[0].vod_content"
  },
  "episodes": "ul.anthology-list-play li a"
}

// Paradigm B (novel)
"ruleToc": {
  "chapterList": ".chapter li a",
  "chapterName": "@text",
  "chapterUrl": "@href",
  "nextTocUrl": "a:contains(下一页)@href"
}
```

##### 6. Content module (content / ruleContent)

Loaded when opening a specific chapter:

- Novel (Paradigm B): ruleContent.content extracts body text (@textNodes for clean text, nextContentUrl for paginated body).
- Manga: chapters route/script returns the chapter list, then images module parses that chapter's image URLs.
- Anime: video module resolves the playable video URL.

| Field / key | Description |
| --- | --- |
| `ruleContent.content` | Novel body selector, often #content@textNodes for paragraph text. |
| `ruleContent.nextContentUrl` | Next-page link of the body for continuous reading. |
| `chapters (manga)` | Returns chapter list, each with id and detail link, feeding images. |
| `images (manga)` | Returns that chapter's image URL array, decryption supported. |

```json
"ruleContent": {
  "content": "#nr1@textNodes",
  "title": "#nr_title@text",
  "nextContentUrl": "a:contains(下一页)@href"
}

// manga images (script returns image array)
"images": {
  "type": "script",
  "function": "parseImages",
  "script": "function parseImages(html, context){ /* parse & decrypt */ return [url1, url2]; }"
}
```

##### 7. Video parsing (player / video)

The core of anime sources. The video route gets the player page HTML, then a selector / script / WebView extracts the real video URL (m3u8 / mp4).

Three ways: a declarative selector (e.g. //video/@src), embedded JS (overrides.type:"script"), or WebView rendering then extract (overrides.type:"webview" — common for m3u8 or when the page must execute JS to reveal the URL).

If the source provides danmaku, the video module can additionally return a danmaku API. Multi-line: if an episode has several addresses, the app offers a 'source switch'.

Async data: when an API call is needed first, the script returns {__meta:true,__fetchUrl,...}; the engine prefetches then calls the processor (see section 13).

| Field / key | Description |
| --- | --- |
| `routes.video.url` | Player page URL (usually from episodes). |
| `overrides.video.type` | How this endpoint is parsed: builtin / css / xpath / jsonpath / script / webview. Video often uses webview for m3u8. |
| `selectors.video` | Video URL selector, e.g. //video/@src or jsonpath (declarative mode). |
| `__meta async` | When an API call is needed first, the script returns {__meta:true,__fetchUrl,...}; the engine prefetches then calls the processor (see section 13). |

```js
// Option A: declarative
"routes": { "video": { "url": "{url}", "method": "get", "responseType": "html" } },
"parser": { "type": "hybrid", "overrides": { "video": { "type": "webview" } } }

// Option B: script fetches API then parses
function parseVideo(html, context){
  var api = extractApi(html);
  return { __meta: true, __fetchUrl: api, __processor: "__processVideo" };
}
function __processVideo(json, context){
  return json.url; // real play URL
}
```

##### 8. Manga image parsing (images)

The most common script module for manga. Sites often encrypt image URLs, so decryption lives in the script. The images function receives the detail/API data and returns that chapter's image URL array.

Note: many KR/CN sites obfuscate image URLs with a custom algorithm — implement it here.

| Field / key | Description |
| --- | --- |
| `function` | Entry function name, e.g. parseImages, matching overrides.images.function. |
| `returns` | A string array, each element a full image URL. |
| `context.baseUrl` | Site baseUrl available in script to complete relative paths. |

```js
function parseImages(raw, context){
  var baseUrl = (context.baseUrl || '').replace(/\/$/, '');
  var urls = decrypt(raw);
  return urls.map(function(u){ return u.indexOf('/')===0 ? baseUrl+u : u; });
}
```

##### 9. Web favorites (webFavorite)

If your source site itself offers a 'my bookshelf / favorites' page, declare webFavorite so the app shows an extra 'Web Favorites' tab in browse. What users see there comes from the site account (requires login), not the app's local favorites.

Declare it by adding a webFavorite object at the source top level. enabled defaults true; title is the tab label; route / url is the 'view favorites list' route or address — when route points to a JSON API script endpoint, the favorites list is fetched via the script resolver and automatically carries the login token (good for auth-required App API favorites). addRoute / addUrl is the 'add to favorites' route or address, supporting {id} / {detailUrl} / {title} placeholders — when addRoute points to a script endpoint, the add is handled by the source script (multi-step request + auth, e.g. fetch the work uuid first then POST), no static form needed; requireLogin true means login is required first.

Note: webFavorite and the app's local favorites are independent — local favorites are managed by the app, web favorites go through the site API.

| Field / key | Description |
| --- | --- |
| `enabled` | Optional, whether to enable the Web Favorites tab (default true). |
| `title` | Optional, the tab label, e.g. 'My Bookshelf'. |
| `route / url` | View-favorites route name or full address; pick one, route must be defined in routes. |
| `addRoute / addUrl` | Add-to-favorites route or address, supports {id} / {detailUrl} / {title} placeholders. When addRoute points to a script endpoint, the add is handled by the source script (multi-step + auth), good for App API sources. |
| `requireLogin` | Optional, true requires site login first. |

```json
"webFavorite": {
  "title": "My Bookshelf",
  "route": "webFavorite",
  "url": "/user/bookshelf",
  "addUrl": "/user/favorite/add?id={id}",
  "requireLogin": true
}
```

##### 10. Source announcement (announcement)

Source authors can publish an announcement to users of the source (e.g. 'site changed domain, please update'). It renders as a banner at the top of the source's home and detail pages.

announcement is an optional top-level object: title is required (announcement title); body is optional text; url is an optional 'view details' link; updatedAt is an optional update time (Unix seconds, used to show 'N days ago'). If url is omitted, the whole banner is non-clickable.

| Field / key | Description |
| --- | --- |
| `title` | Required, announcement title. |
| `body` | Optional, announcement body. |
| `url` | Optional, link opened when the banner is tapped (e.g. a migration note). |
| `updatedAt` | Optional, update time as Unix seconds. |

```json
"announcement": {
  "title": "Site domain changed",
  "body": "Old domain example-old.com is down, please update to the new one.",
  "url": "https://example.com/notice",
  "updatedAt": 1700000000
}
```

##### 11. Weekly schedule (schedule)

Want the source's home page to show a 'weekly schedule' (what updated each day Mon-Sun)? Use a homeSections entry with style 'schedule'; the app groups it by weekday.

Steps:

1. Add a homeSections entry { id, title, route:'week', style:'schedule', limit:0, more:false }. The route name is up to you (here 'week').
2. Define a week route with the same name in routes; its results must carry a 'weekday' field (the app bins works into Mon-Sun by it).

Users then see an update table grouped by weekday on the source home. limit:0 means no cap; more:false hides 'view more'.

| Field / key | Description |
| --- | --- |
| `homeSections[].style` | Set to 'schedule' to enable the weekly board. |
| `homeSections[].route` | Route name for the schedule data (must match routes). |
| `routes.week` | Returns a list with weekday field; app bins into Mon-Sun. |
| `limit / more` | limit:0 = no cap; more:false hides 'view more'. |

```json
"homeSections": [
  { "id": "week", "title": "Weekly", "route": "week", "style": "schedule", "limit": 0, "more": false }
],
"routes": {
  "week": { "url": "/api/weekly", "method": "get", "responseType": "json" }
}
```

#### 🔴 Advanced

##### 8 (cont.). Image byte decryption (imageTransform)

Some image CDNs encrypt the **image bytes themselves** (the browser decrypts them client-side via the site's own JS). No matter how you set Referer/UA, the client receives ciphertext and decoding fails. Such sources can declare an imageTransform block at the top level: list the CDN hosts that need decryption and the algorithm; the engine decrypts uniformly at the image-download layer (all keys/algorithms come from the source JSON — the engine hard-codes no site logic).

Coverage: common community image-byte encryption schemes — aes-cbc / aes-ecb / rc4 / xor; IV supports prefix-bytes / fixed / all-zero; padding supports pkcs7 / none; key and IV support utf8 / base64 / hex encodings. Decrypted plaintext goes into the on-disk cache; save/share inherit it automatically.

Note: matchHosts must enumerate **all** CDN hosts that may serve images (some sites rotate image hosts by mirror domain — miss one host and that mirror's images break).

| Field / key | Description |
| --- | --- |
| `matchHosts` | List of image CDN hosts to decrypt (exact match, case-insensitive). |
| `decrypt.algo` | Decryption algorithm: aes-cbc / aes-ecb / rc4 / xor. |
| `decrypt.key / keyEncoding` | Key bytes; keyEncoding supports utf8 (default) / base64 / hex. |
| `decrypt.ivSource` | IV source: prefixBytes (the first ivLength bytes of the ciphertext are the IV, most common) / fixed (use decrypt.iv) / none (all-zero IV). |
| `decrypt.padding` | Padding: pkcs7 (default) / none (ciphertext length always a multiple of 16). |

```json
"imageTransform": {
  "matchHosts": ["cdn.example.com", "cdn-mirror.example.com"],
  "decrypt": {
    "algo": "aes-cbc",
    "key": "16-byte key literal",
    "keyEncoding": "utf8",
    "ivSource": "prefixBytes",
    "ivLength": 16,
    "padding": "pkcs7"
  }
}
```

##### 12. Selector syntax cheat-sheet

Parsing has two layers — the top-level parser.type and each API's overrides.type:

- Top-level parser.type takes only three values: builtin (pure declarative), hybrid (declarative + per-API overrides, most common), script (all JS sandbox).
- Each API can set overrides.type to decide how THAT endpoint is parsed: builtin / xpath / jsonpath / css (the four declarative sub-types share one engine) / script (JS sandbox) / webview (render in an embedded browser then extract — common for m3u8) / webview-html (WebView returns HTML then parsed — common for anti-bot search).

The declarative selector syntax is chosen by overrides.type:

- jsonpath: starts with $, for JSON APIs (e.g. $.list[0].vod_name).
- css: standard CSS selectors for HTML (e.g. .bookname a).
- xpath: starts with // or ./, for HTML (e.g. //video/@src).

Novel sources (Legado-compatible) add custom syntax: @text gets text, @href/@src get attributes, @textNodes gets clean body, || is a fallback selector, a:contains(text) filters by visible text, .0/.1/-1 picks the Nth.

| Field / key | Description |
| --- | --- |
| `top-level parser.type` | builtin / hybrid / script — the source-wide default. |
| `overrides.<api>.type` | per-API: builtin / xpath / jsonpath / css / script / webview / webview-html. |
| `$.field` | jsonpath, extract a JSON field. |
| `.class a@text` | css + @text gets element text. |
| `//video/@src` | xpath gets an attribute value. |
| `a:contains(下一页)@href` | novel: filter links by visible text. |

```js
// top-level: hybrid + per-API type
"parser": { "type": "hybrid", "overrides": {
  "search": { "type": "jsonpath" },
  "video": { "type": "webview" },
  "detail": { "type": "css" }
} }
// jsonpath
"title": "$.vod_name"
// css (HTML)
"bookName": ".bookname a@text"
// xpath (HTML)
"video": "//video/@src"
```

##### 13. Embedded JS conventions

When declarative selectors are not enough, use parser.overrides to write JS. Each module can set type:'script' with a function name and script source.

Key rules:

1. Signature is fixed: parseXxx(html, context); html is the page string, context has baseUrl, log, etc.
2. Must return synchronously (array or object).
3. For async data, return the {__meta:true, __fetchUrl, __processor} protocol object; the engine prefetches that URL, then calls __processor synchronously — the only safe async channel.
4. Never hardcode site constants into the app; keep everything in the source file.
5. The sandbox now presets atob / btoa (browser-semantics polyfill, leniently stripping invalid chars and trailing '='), so scripts can call them directly without embedding a polyfill; a source's own same-name declaration overrides the default. Within one JsEngine instance, top-level variables persist across meta multi-hop calls — each hop's __processor no longer replays the whole script — matching the 'globals stay visible within one JsEngine' convention.

| Field / key | Description |
| --- | --- |
| `function` | Entry function name, matching overrides.`<module>`.function. |
| `context.baseUrl` | Current source's base URL, for relative links. |
| `context.log` | Optional logger for debugging (context.log('msg')). |
| `__meta protocol` | Async prefetch: return this object, engine calls __processor after fetch. |

```json
"parser": {
  "type": "hybrid",
  "overrides": {
    "search": {
      "type": "script",
      "function": "parseList",
      "script": "function parseList(html, context){ /* parse & return array */ return []; }"
    }
  }
}
```

##### 14. Advanced: source-level network / comments / login (v0.4.0)

| Field / key | Description |
| --- | --- |
| `network` | Source-level proxy / DNS / Hosts / SNI / ECH override; defaults to global. |
| `network.sni` | SNI override, e.g. { "enabled": true, "defaultSni": "-" }; "-" skips SNI, a plain domain uses that as SNI, domainSni maps 'domain→SNI' with suffix wildcard. Effective for direct HTTPS; ignored when using a proxy. |
| `network.ech` | ECH override (e.g. { "enabled": true, "configs": [...] }). Driven by a built-in native engine; takes effect for direct HTTPS. Scopes: app-level / per-source / Bangumi; now shipped with Android (three ABIs) and the Windows desktop build; macOS / Linux fall back to direct for now. |
| `comments.provider / routes / selectors` | Declares site comments; routes.list is required when comments is set, others optional. |
| `comments.login.url` | WebView login page URL; the app opens it for login and captures the session cookie (local only). |
| `comments.login.checkCookie` | Cookie login: this cookie key means logged in (fast check). |
| `comments.login.checkUrl / loggedInSelector` | Session probe: GET checkUrl; a non-empty selector match means the session is valid. |
| `comments.login.sendTokenAs` | Token carrier (login type): null = cookie only; bearer → `Authorization: Bearer <cookie value of checkCookie>`; key → `Authorization: <authScheme> <manual key>`, i.e. API key login. |
| `comments.login.authScheme` | Only when sendTokenAs==key: Authorization prefix, default Key; change it if the site wants Token / Bearer etc. |
| `comments.login.apiKeyParam` | Only when sendTokenAs==key: key name in the local key store, default apiKey (stored as sourceId:apiKeyParam). |
| `site.cookies` | Manual cookie login: paste the whole session cookie into site.cookies; every request carries it. |
| `precedence` | User override > source network block > global > default; applies instantly, no restart. |

```json
"network": { "proxy": "direct", "dns": "system" },
"comments": {
  "provider": "source",
  "routes": { "list": { "url": "/api/comments?book={id}", "responseType": "json" } },
  "selectors": { "items": "$.list", "content": "$.content", "author": "$.user" },
  "login": {
    "url": "https://example.com/login",
    "checkCookie": "sessionid",
    "checkUrl": "https://example.com/me",
    "loggedInSelector": ".user-info"
  }
}
// Manual cookie login: paste the whole session cookie into site.cookies
"site": { "baseUrl": "https://example.com", "cookies": "sessionid=abc123; uid=42" }
// API key login (same comments.login block): sendTokenAs=key
"login": {
  "sendTokenAs": "key",    // appends Authorization: <authScheme> <pasted key>
  "authScheme": "Key",     // default Key; change if the site wants another prefix
  "apiKeyParam": "apiKey"  // key name in the local key store, default apiKey
}
```

##### 15. Writing 'You may also like'

'You may also like' is the recommendation block on the detail page. Adding it lets readers keep discovering without going back to search.

Three ways (pick per source type, can coexist):

1. Recommendation route (recommended, works for anime / manga / novel): declare recommend (preferred) or related in routes; when the detail page opens the engine calls it with the {id} variable and renders the results as the block. If neither exists, the block is not rendered.
2. Manga (mangaSource): add a recommendations object under selectors.detail with list / title / cover / url to extract the list straight from the detail page (used by some built-in sources).
3. Novel (Legado): use ruleBookInfo.recommendations to extract recommended titles.

Note: recommendations reuse the list parsing engine, with the same fields as search / latest (id / title / cover / detailUrl) — in most cases copying your search selectors just works.

| Field / key | Description |
| --- | --- |
| `routes.recommend` | Recommendation endpoint (preferred): called with the {id} variable when the detail page opens; results render as the block. |
| `routes.related` | Fallback recommendation endpoint; used when recommend is absent, same behaviour. |
| `selectors.recommend` | Extraction selectors for recommendations (same shape as search / latest: list / title / cover / id); falls back to selectors.search. |
| `selectors.detail.recommendations (manga)` | Object { list, title, cover, url } to extract the list straight from the detail page. |
| `ruleBookInfo.recommendations (novel)` | Legado-compatible field, selector for recommended titles. |
| `Not rendered when` | Neither recommend nor related is declared — the detail page then hides the block. |

```js
// 写法一（通用）：recommend 路由 + 选择器
{
  "routes": {
    "recommend": { "url": "/api/recommend?id={id}", "method": "get", "responseType": "json" }
  },
  "selectors": {
    "recommend": {
      "list": "$.list",
      "title": "$.vod_name",
      "cover": "$.vod_pic",
      "id": "$.vod_id"
    }
  }
}

// 写法二（漫画）：selectors.detail.recommendations 从详情页直接抽
"detail": {
  "title": "h1.text-xl@text",
  "recommendations": {
    "list": ".recommend-list a[href^=\"/manga/\"]",
    "title": "h3@text",
    "cover": "img@src||data-src",
    "url": "@href"
  }
}
```

##### 16. Collection API interface

The 'collection API' is the set of scrape endpoints a source exposes — i.e. the endpoints defined in routes (search / latest / detail / video / images …) and the extraction rules declared per endpoint via selectors or overrides. The app engine calls each endpoint in turn, turning site data into a unified structure.

Endpoints and overrides:

- Each endpoint first defines url in routes (supports {keyword}/{page}/{id}/{url}/{detailUrl} placeholders), method, responseType, headers, params.
- How it is parsed is decided by parser.overrides.`<endpoint>`: builtin / xpath / jsonpath / css / script / webview / webview-html.
- Declarative endpoints use selectors.`<endpoint>`; script endpoints use overrides.`<endpoint>`.script.

Async protocol __meta: when an endpoint must call another API before parsing (e.g. video first calls an API to get the real URL), the script returns { __meta:true, __fetchUrl, __processor }. The engine prefetches __fetchUrl, then hands the result to __processor synchronously. This is the only safe async channel in the sandbox.

Common endpoints: search, latest, explore / category, detail (+contents), episodes, video, chapters (manga), images (manga), week (schedule). Exact field names are in each module section and the 'Complete Source Field Reference'.

| Field / key | Description |
| --- | --- |
| `routes.<name>` | Endpoint address and method; {keyword}/{page}/{id}/{url} auto-replaced. |
| `parser.overrides.<name>` | How this endpoint is parsed: builtin / xpath / jsonpath / css / script / webview / webview-html. |
| `selectors.<name>` | Extraction selectors for declarative endpoints. |
| `__meta protocol` | Script endpoints that need a second request return {__meta:true,__fetchUrl,__processor}. |

```js
// A full endpoint declaration (routes + overrides + selectors)
"routes": {
  "search": { "url": "/s?wd={keyword}&page={page}", "method": "get", "responseType": "json" }
},
"parser": { "type": "hybrid", "overrides": { "search": { "type": "jsonpath" } } },
"selectors": { "list": "$.list", "title": "$.vod_name", "cover": "$.vod_pic", "id": "$.vod_id" }

// Video endpoint needing a second request
function parseVideo(html, context){
  var api = extractApi(html);
  return { __meta: true, __fetchUrl: api, __processor: "__processVideo" };
}
function __processVideo(json, context){ return json.url; }
```

##### 17. Full example: novel source (Legado)

A complete runnable novel source example (Legado-compatible format). Note: novel sources do NOT use the id / name / type / site top-level keys; instead they use Legado keys like bookSourceName / bookSourceUrl / bookSourceType / ruleSearch / ruleToc / ruleContent / ruleBookInfo; parsing is handled by parser.overrides.content. Replace example.com with a real site and the selectors with real rules, then import.

```json
{
  "bookSourceName": "Demo Novel",
  "bookSourceUrl": "https://m.example.com",
  "bookSourceType": 0,
  "enabledExplore": true,
  "enabledSearch": true,
  "exploreUrl": "Xuanhuan::https://m.example.com/xuanhuan/\nUrban::https://m.example.com/dushi/",
  "bookSourceGroup": "Built-in",
  "concurrentRate": 0,
  "ruleSearch": {
    "bookList": ".bookbox",
    "bookName": ".bookname a@text",
    "bookAuthor": ".author@text",
    "bookCoverUrl": ".bookimg img@src",
    "bookUrl": ".bookname a@href",
    "bookLastChapter": ".update a@text"
  },
  "ruleExplore": {
    "bookList": ".bookbox",
    "bookName": ".bookname a@text",
    "bookAuthor": ".author@text",
    "bookCoverUrl": ".bookimg img@src",
    "bookUrl": ".bookname a@href"
  },
  "ruleBookInfo": {
    "name": "h1@text",
    "author": "p:contains(作者)@text",
    "coverUrl": ".block_img2 img@src",
    "intro": ".intro_info@text",
    "tocUrl": "a[href^=\"/book_\"]@href",
    "lastChapter": "p:contains(最新) a@text",
    "bookStatus": "p:contains(状态) span@text"
  },
  "ruleToc": {
    "chapterList": "a[href^=\"/book_\"][href$=\".html\"]",
    "chapterName": "@text",
    "chapterUrl": "@href",
    "nextTocUrl": "a:contains(下一页)@href"
  },
  "ruleContent": {
    "content": "#nr1@html",
    "title": "#nr_title@text",
    "nextContentUrl": "a:contains(下一章)@href"
  },
  "parser": {
    "type": "hybrid",
    "overrides": {
      "content": {
        "type": "script",
        "function": "parseContent",
        "script": "function parseContent(html, context){ var raw = context.dom.queryHtml(html, '#nr1') || context.dom.queryHtml(html, '#content') || ''; raw = raw.replace(/<script.*?<\/script>/gi, ''); return context.content.clean(raw); }"
      }
    }
  },
  "bookSourceComment": "Demo novel source, plain HTML content"
}
```

##### 18. Full example: anime source (animeSource)

A complete runnable anime source example (animeSource). The core is the video endpoint: here we use webview to extract the real play URL (good for m3u8 / sites where the page must execute JS to reveal the URL). Note an anime source MUST include a latest route. Replace example.com with a real site and import.

```json
{
  "id": "demo_anime",
  "name": "Demo Anime",
  "version": 1,
  "type": "animeSource",
  "responseType": "json",
  "useWebview": true,
  "site": {
    "domain": "example.com",
    "baseUrl": "https://example.com",
    "mirrors": [ { "name": "main", "domain": "example.com", "baseUrl": "https://example.com" } ]
  },
  "parser": {
    "type": "hybrid",
    "overrides": {
      "latest": { "type": "builtin" },
      "search": { "type": "builtin" },
      "detail": { "type": "builtin" },
      "episodes": { "type": "builtin" },
      "video": { "type": "webview" }
    }
  },
  "routes": {
    "latest": { "url": "/api/latest?page={page}", "method": "get", "responseType": "json" },
    "search": { "url": "/s?wd={keyword}&page={page}", "method": "get", "responseType": "json" },
    "detail": { "url": "/detail/{id}", "method": "get", "responseType": "json" },
    "episodes": { "url": "/detail/{id}", "method": "get", "responseType": "json" },
    "video": { "url": "{url}", "method": "get", "responseType": "html" },
    "week": { "url": "/api/weekly", "method": "get", "responseType": "json" }
  },
  "selectors": {
    "list": "$.list",
    "title": "$.vod_name",
    "cover": "$.vod_pic",
    "id": "$.vod_id",
    "detail": { "title": "$.vod_name", "cover": "$.vod_pic", "description": "$.vod_content" },
    "episodes": "ul li a"
  },
  "category": { "categoryEntries": [ { "id": "all", "title": "All" }, { "id": "1", "title": "Anime" } ] },
  "homeSections": [
    { "id": "latest", "title": "Latest", "route": "latest", "style": "grid", "limit": 18 },
    { "id": "week", "title": "Weekly", "route": "week", "style": "schedule", "limit": 0, "more": false }
  ]
}
```

##### 19. Full example: manga source (Demo Manga / mangaSource)

This is a complete manga source example modeled on the built-in 'Demo Manga' source (demo.example). Manga sources have two key endpoints beyond anime/novel: chapters (chapter list) and images (that chapter's images).

Key points:

- chapters often needs a second request — the script first grabs data-mid from the page, then returns {__meta:true, __fetchUrl, __processor} so the engine prefetches the chapter API (here api.example.com), then __processChapters handles it synchronously (async rules in section 13).
- Image URLs are usually encrypted: put the decryption in parseImages under overrides.images.script and return the image URL array.
- Category tags (selectors.category.tags) ids are the site's real slugs (e.g. 古风 = gufeng, no hyphen) — don't invent them.

For readability the real source's long regex/decryption scripts are condensed to skeletons here (importing as-is yields empty results); replace each script with real parsing logic before use.

```json
{
  "id": "manga_demo",
  "name": "示例漫画",
  "version": 4,
  "type": "mangaSource",
  "responseType": "html",
  "useWebview": true,
  "site": {
    "domain": "demo.example",
    "baseUrl": "https://demo.example",
    "mirrors": [
      {
        "name": "demo.example",
        "domain": "demo.example",
        "baseUrl": "https://demo.example"
      },
      {
        "name": "m.demo.example",
        "domain": "m.demo.example",
        "baseUrl": "https://m.demo.example"
      }
    ]
  },
  "parser": {
    "type": "hybrid",
    "overrides": {
      "latest": {
        "type": "script",
        "function": "parseList",
        "script": "function parseList(html, context){ var baseUrl = (context.baseUrl || '').replace(/\\/$/, ''); var results = []; /* 正则抓 <a href=\"/manga/...\"> 块，取 h3 标题与封面 */ return results; }"
      },
      "search": {
        "type": "script",
        "function": "parseList",
        "script": "function parseList(html, context){ return []; }"
      },
      "detail": {
        "type": "script",
        "function": "parseDetail",
        "script": "function parseDetail(html, context){ return { title: '', cover: '', description: '', author: '', tags: [] }; }"
      },
      "chapters": {
        "type": "script",
        "function": "parseChapters",
        "script": "function parseChapters(html, context){ var m = html.match(/data-mid=\"(\\d+)\"/i); if (!m) return []; return { __meta: true, __fetchUrl: 'https://api.example.com/api/manga/get?mid=' + m[1] + '&mode=all', __processor: '__processChapters' }; }"
      },
      "images": {
        "type": "script",
        "function": "parseImages",
        "script": "function parseImages(raw, context){ var urls = decrypt(raw); return urls; }"
      }
    }
  },
  "routes": {
    "latest": {
      "url": "/",
      "method": "GET",
      "headers": {
        "Referer": "https://demo.example/",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
      }
    },
    "explore": {
      "url": "/manga/page/{page}",
      "method": "GET",
      "headers": {
        "Referer": "https://demo.example/",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
      }
    },
    "category": {
      "url": "{category}/page/{page}",
      "method": "GET",
      "headers": {
        "Referer": "https://demo.example/",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
      }
    },
    "search": {
      "url": "/s/{keyword}?page={page}",
      "method": "GET",
      "headers": {
        "Referer": "https://demo.example/",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
      }
    },
    "detail": {
      "url": "/manga/{id}",
      "method": "GET",
      "headers": {
        "Referer": "https://demo.example/",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
      }
    },
    "chapters": {
      "url": "/manga/{id}",
      "method": "GET",
      "headers": {
        "Referer": "https://demo.example/",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
      }
    },
    "images": {
      "url": "/manga/{id}/{chapter_id}",
      "method": "GET",
      "headers": {
        "Referer": "https://demo.example/",
        "User-Agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36"
      }
    }
  },
  "selectors": {
    "latest": {
      "list": "a[href^=\"/manga/\"]",
      "title": "h3@text",
      "cover": "img@src||data-src",
      "id": "a@href"
    },
    "explore": {
      "list": "a[href^=\"/manga/\"]",
      "title": "h3@text",
      "cover": "img@src||data-src",
      "id": "a@href"
    },
    "category": {
      "list": "a[href^=\"/manga/\"]",
      "title": "h3@text",
      "cover": "img@src||data-src",
      "id": "a@href",
      "categories": [
        {
          "id": "manga",
          "name": "全部"
        },
        {
          "id": "manga-genre/kr",
          "name": "韩漫"
        },
        {
          "id": "manga-genre/cn",
          "name": "国漫"
        },
        {
          "id": "manga-genre/jp",
          "name": "日漫"
        },
        {
          "id": "manga-genre/ou-mei",
          "name": "欧美"
        }
      ],
      "tags": [
        {
          "id": "gufeng",
          "name": "古风"
        },
        {
          "id": "rexue",
          "name": "热血"
        },
        {
          "id": "chuanyue",
          "name": "穿越"
        },
        {
          "id": "xuanhuan",
          "name": "玄幻"
        }
      ]
    },
    "search": {
      "list": "a[href^=\"/manga/\"]",
      "title": "h3@text",
      "cover": "img@src||data-src",
      "id": "a@href"
    },
    "detail": {
      "title": "h1.text-xl@text",
      "cover": ".object-cover img@src||data-src",
      "author": "div:has(> span:contains(\"作者：\")) a[href^=\"/manga-author/\"]@text",
      "tags": "a[href^=\"/manga-tag/\"] span@text",
      "description": "p.text-medium@text",
      "status": "div:has(> span:contains(\"状态：\"))@text"
    },
    "chapters": {
      "list": ".chapteritem",
      "title": ".chaptertitle@text",
      "id": "a@href",
      "url": "a@href",
      "updatedAt": ".time@text"
    },
    "images": {
      "list": "#chapcontent img",
      "fallbackUrl": "img@data-src||img@data-original||img@src",
      "config": {
        "skipPatterns": [
          "logo",
          "icon",
          "qrcode",
          "avatar",
          "banner"
        ],
        "sizeFilter": {
          "minWidth": 100,
          "minHeight": 100
        },
        "referer": {
          "mode": "site"
        },
        "pagination": {
          "mode": "none"
        }
      }
    }
  },
  "category": {
    "dynamicCategories": false
  },
  "stealthMode": true,
  "antiHotlinking": {
    "referer": "https://demo.example"
  },
  "webviewConfig": {
    "adblock": true,
    "timeoutSeconds": 20
  },
  "homeSections": [
    {
      "id": "latest",
      "route": "latest",
      "title": "近期更新",
      "style": "grid",
      "limit": 18,
      "more": true
    },
    {
      "id": "hots",
      "route": "category",
      "title": "人气排行",
      "style": "grid",
      "limit": 12,
      "more": true,
      "params": {
        "category": "hots"
      }
    },
    {
      "id": "kr",
      "route": "category",
      "title": "韩漫",
      "style": "grid",
      "limit": 6,
      "more": true,
      "params": {
        "category": "manga-genre/kr"
      }
    },
    {
      "id": "cn",
      "route": "category",
      "title": "国漫",
      "style": "grid",
      "limit": 6,
      "more": true,
      "params": {
        "category": "manga-genre/cn"
      }
    }
  ]
}
```

##### 20. Debug & import

How to verify after writing?

1. Use browser DevTools (F12) to confirm the real page's HTML/JSON structure matches your selectors.
2. In the app, 'Import Source' and paste the JSON. If parsing fails, check JSON format (escaped quotes and newlines).
3. Script sources can use context.log() inside overrides to print intermediate results.
4. Start with a minimal source that only gets one module working (e.g. search), then progressively add detail / video / images.
5. Share: send the JSON to friends, or submit to the community source repo — anyone can import it with one tap.

| Field / key | Description |
| --- | --- |
| `Import` | App 'Source Management / Import Source' → paste or pick file. |
| `Common errors` | JSON syntax error, selector returns empty, relative link not joined to baseUrl, script throws. |
| `Upgrade` | Bump version; same-id sources auto-overwrite the old one on import. |

##### 21. Complete Source Field Reference

A fairly complete field cheat-sheet, grouped as top-level / site / parser / routes / selectors / advanced blocks. Everything except id, name, type, site and parser is optional; unknown keys (e.g. author / lang / builtin) are ignored by the model — do not treat them as functional fields.

The authoritative constraints live in lib/core/models/plugin_config.dart; this table covers the fields used most often when writing a source.

| Field / key | Description |
| --- | --- |
| `id` | Required. Unique source id (e.g. domain_typename to avoid collisions); same id is upgraded/skipped by version. |
| `name` | Required. Display name. |
| `version` | Integer version (default 1). On import, only >= installed version overwrites; < installed version is skipped. |
| `type` | Required. animeSource (video/anime) / mangaSource (manga) / novelSource (novel). |
| `responseType` | Optional. json \| html, sets the default parse engine; overridable per-route. |
| `useWebview` | Optional bool. true = render the whole source via WebView before extraction (good for anti-bot sites). |
| `site.domain` | Required. Site main domain. |
| `site.baseUrl` | Required. Site root used to resolve relative links. |
| `site.userAgent / cookies / headers` | Optional. Global request UA / cookies / custom headers. |
| `site.mirrors[]` | Optional. Mirror list, each {name, domain, baseUrl}. |
| `site.publishPageUrl / publishMirrorSelector` | Optional. Fallback publish page and mirror-extraction rule (regex or CSS) when the main domain dies. |
| `parser.type` | Required. builtin / hybrid / script — the source-wide default parse mode. |
| `parser.overrides.<api>` | Optional. Per-API parse mode: builtin / xpath / jsonpath / css / script / webview / webview-html. |
| `parser.script / entrypoints` | Optional. JS source and entry-function map for script mode. |
| `routes.<name>` | Optional. Endpoint addresses; string form or {url, method, headers, params, responseType, parser}; {keyword}/{page}/{id}/{url} placeholders auto-replaced. |
| `selectors` | Optional. Declarative selectors (JSONPath / CSS / XPath), used with parser.overrides. |
| `category.dynamicCategories / categoryEntries` | Optional. Dynamic category inference or static category table [{id,title}]. |
| `homeSections[]` | Optional. Home sections: {id, title, route, style, limit}; falls back to a single 'latest' block when omitted. |
| `filters` | Optional. Dynamic filters: groups, byCategory (per-category override), defaults (category default params). |
| `stealthMode` | Optional bool. More aggressive anti-detection request strategy. |
| `antiHotlinking.referer / headers / userAgent` | Optional. Anti-hotlink: add Referer / headers / specific UA. |
| `webviewConfig.adblock / timeoutSeconds` | Optional. WebView adblock toggle and timeout (default true / 20s). |
| `comments` | Optional. Comments config: provider(source/bangumi), routes(list required; replies/post/reply/like/report optional), selectors, login(url=WebView login page + checkCookie=cookie key + checkUrl/loggedInSelector=session probe). |
| `network` | Optional. Source-level network override: proxy / dns / hosts / sni / ech; inherits global by default, invalid values only warn. (sni and ech are both runtime-effective for direct HTTPS) |
| `announcement` | Optional. Source announcement: {title, body?, url?, updatedAt?}. |
| `webFavorite` | Optional. Web favorites: enabled / title / route / url / addRoute / addUrl / requireLogin; when present, the 'Web Favorites' tab shows in browse. |
| `ageRating` | Optional. Age rating: general (all) / teen (13+/16+) / mature (18+). Aliases like all/16/r18/nsfw accepted; default general. mature is hidden by default. |
| `deprecated / migrationMessage` | Optional. Mark deprecated and show a migration hint. |
| `enabled / enabledExplore / isHidden` | Optional bool. Enabled / shown in explore / hidden. |

```js
// Top-level field skeleton (illustrative, not a full source)
{
  "id": "demo_anime",
  "name": "Demo Anime",
  "version": 1,
  "type": "animeSource",
  "responseType": "json",
  "useWebview": false,
  "site": { "domain": "example.com", "baseUrl": "https://example.com" },
  "parser": { "type": "hybrid", "overrides": { "video": { "type": "webview" } } },
  "routes": { "latest": { "url": "/api/latest?page={page}" } },
  "ageRating": "general",
  "webFavorite": { "route": "fav", "addRoute": "fav_add" },
  "network": { "proxy": "direct" }
}
```

---

### 4.5.3 Import rules, extra notes & contributions

**About the `version` import rule (pay attention)**:

- To release a new source version, simply bump `version` in the JSON;
- Importing a same-id source: version **≥ installed** → replace (upgrade / same-version re-import applies your edits); version **< installed** → skip, preventing an old version from clobbering the new one;
- Built-in sources cannot be overwritten; the "enabled / hidden" state is preserved on import.

**`comments` sub-fields (new in v0.4.0, all optional)**:

| Field | Description |
| --- | --- |
| `comments.provider` | Default `source` (comments from the source site). `bangumi` is **parsed but not implemented** |
| `comments.routes.list` | **Required** (when `comments` is declared); comment-list route |
| `comments.routes.replies` / `post` / `reply` / `like` / `report` | Optional; **undeclared buttons are not rendered** |
| `comments.selectors` | `items` / `commentId` / `author` / `avatar` / `content` / `time` / `likeCount` / `replyCount` / `hasMore` / `success`, etc. |
| `comments.login.url` | WebView login-page URL when login is needed |
| `comments.login.checkCookie` | Presence of this cookie key means logged in |
| `comments.login.checkUrl` + `loggedInSelector` | Optional secondary probe |
| `comments.login.sendTokenAs` | Token carrier (login type): `null` cookie only / `bearer` → `Authorization: Bearer <cookie value of checkCookie>` / `key` → `Authorization: <authScheme> <manual key>` (**API key login**) |
| `comments.login.authScheme` | Only when `sendTokenAs==key`; `Authorization` prefix, default `Key` |
| `comments.login.apiKeyParam` | Only when `sendTokenAs==key`; key name in the local key store, default `apiKey` (stored as `sourceId:apiKeyParam`) |

**Batch prefetch of many pages (`__fetchUrls`)**:

When a script endpoint has to follow N pages one by one (e.g. a gallery page only lists thumbnails and the full image lives on each page), switch to the batch protocol: the engine fetches concurrently on the Dart side, then hands the results back to the script for synchronous processing.

```json
{
  "__meta": true,
  "__fetchUrls": ["/p/1", "/p/2", "/p/3"],
  "__fetchResponseType": "text",
  "__processor": "__processPages"
}
```

- `__fetchResponseType`: `json` (default) / `text`;
- `__fetchConcurrency`: concurrency, 6 by default, capped at 16;
- `__fetchHeaders` / `__fetchMethod` / `__fetchBody`: extra headers / method (`get` by default, `post` allowed) / POST body;
- `__processor` receives the responses **in input order**; a failed item is `null` and does not break the batch;
- Within one `JsEngine` instance, `__meta` may chain up to 4 hops, and top-level variables stay visible across hops.

**How to contribute**:

1. Write the source JSON on your own branch and import it into the app to verify scraping works;
2. To share, publish your source JSON through community channels (**do not submit sources to this app repo** — the repo only hosts the engine);
3. To improve the engine / readers / player / docs, file Issues and Pull Requests.

> Co-creation presumes **compliance and copyright respect**: only parse public content you have the right to access and that permits scraping; don't use sources to infringe others' lawful rights.

## 4.6 Testing

```bash
flutter test
```

The test suite includes source JSON validation; with no built-in sources present, related cases auto-skip (fitting the open-source no-source model).
