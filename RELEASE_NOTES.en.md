# NexHub v4.0.0-beta.3

> All-in-one media aggregation client (anime / comics / novels / video) — Source-as-Plugin · co-created community.

This is NexHub's all-in-one media aggregation client (anime / comics / novels / video). NexHub **does not bundle any content sources**; all content comes from "sources" that you import yourself.

> ⚠️ **This is the third public beta of 4.0.0 (still from the `feature/legado-booksource-compat` branch, not yet merged into main)**: 42 commits relative to v4.0.0-beta.2 — item-by-item semantic alignment of the book-source engine (variable deletion / TOC paging / charset table / binary cache / jsoup collections / WebView prefetch), paragraph comments with inline icons, a fix for favorites vanishing after restart, download cover fixes, precise TOC positioning, and exportable runtime logs. **Core features are complete and upgrading is safe.**
>
> - **Data compatibility**: Verified by code review, **no breaking data changes** — bookshelf, favorites, progress, bookmarks, history, and groups carry over directly; new book source fields are parsed with lenient semantics, so old source JSON needs no modification; reinstalling over the top works directly with the same signing key.
> - **Platform artifacts**: Android / Windows / Linux / macOS / iOS / HarmonyOS HAP are all published together in the same pre-release Release; the HarmonyOS HAP is unsigned and must be signed by you before sideloading.
> - **Recommendation**: This is a beta; if a non-standard source fails to parse, please report it with the in-app "Runtime Log", including device model and scenario for audio / live-stream paths.

## ✨ Core Features

- **All-in-one aggregation**: Anime, comics, novels, and video are managed, browsed, searched, read, and watched together in one app.
- **Source-as-Plugin · co-creation model**: Parsing power is driven entirely by importable source JSON; the app only provides the "engine" and hardcodes no site.
- **Multi-engine parsing**: Declarative (XPath / JSONPath / CSS) + scripted (built-in JS sandbox) with automatic dispatch.
- **Multi-section home page and dynamic filtering**: Tags / categories are "what you see is what you get", generated automatically from the source structure.
- **Local content import** (since v1.1.0): Novels support TXT / EPUB; comics support PDF / CBR / RAR / 7Z / ZIP / CBZ and other archives as well as whole-folder import (Android supports SAF folders); one-tap import from the bookshelf, readable offline.
- **Comic reader**: Double-page / single-page, page-turn gestures, zoom and filters, persistent reading progress, with targeted fixes for common pain points.
- **Novel reader**: Customize font, font size, line spacing, margins, theme, brightness, and more; changes take effect immediately and persist.
- **Video player**: Built on the single media_kit (libmpv) core with canvas_danmaku danmaku rendering.
- **Bangumi sync** (added in v0.4.0): Sync favorite status, watched episodes / reading progress, rating, and short reviews to Bangumi, with OAuth authorization login.
- **Network configuration** (added in v0.4.0): Global and source-level proxy / DNS (DoH, DoT) / Hosts configuration to cope with connection failures and DNS poisoning.
- **Favorite groups and comments** (added in v0.4.0): Multi-group tag-style management, local ratings and short reviews; site comments and Bangumi remarks on detail pages.
- **Desktop cards** (added in v3.4.0): Android widgets and HarmonyOS service cards in 8 types — continue watching / updates / downloads / statistics / heatmap / big number / modular / streak check-in — showing real progress and the current month's check-ins, following the system for light/dark appearance.
- **Wide-screen two-pane** (added in v3.5.0): On wide windows, see the list and details together on one screen, with a draggable width and a toggle; HarmonyOS tablets native full-screen, comics support automatic wide-screen double-page.
- **Novel continuous scroll and TTS** (added in v3.6.0): Scrolling seamlessly continues into the next chapter at chapter end, TTS position remembered separately, continue-reading at chapter end on by default; the player supports automatic orientation following the video and portrait-mode pages.
- **Book source compatibility layer** (added in v4.0.0-beta.1): Legado-style book source import fidelity, the `java.*` rule bridge with crypto / font / network capabilities, dynamic rule replay, the discover page option bar, and multi-type dispatch.
- **Download management / history and update tracking / Material 3 dynamic color / multi-language / cross-platform**.

## 📌 General Upgrade Notes

Apart from the "Special Notes" in each version, **all versions have no breaking data changes**: favorites / progress / bookmarks / history / groups / ratings / short reviews carry over directly, old source JSON needs no modification and no re-import.

**Signing key**: Since v0.3.0 a single fixed signing key has been used (injected via CI Secret, not stored in the repo), so you can reinstall over the top; older random-signed packages must be uninstalled once first. v0.2.12 introduced a fixed signature, and v0.3.1 switched to CI injection (the key itself is identical).

## 📝 Changelog (reverse order · newest first)

### 📝 Changelog (v4.0.0-beta.2 → v4.0.0-beta.3)

> 🧪 **Pre-release beta.** 42 commits, still from the `feature/legado-booksource-compat` branch; item-by-item engine alignment plus paragraph comments and fixes for favorites, download covers, TOC positioning and logs. No breaking data changes.

- **Paragraph comments & inline icons**: book-source content supports per-paragraph comments (view / load / page in a panel); inline icons render where rules place them and open the matching discussion; evaluation stays on the source rule chain.
- **Favorites protection**: `FilePrefsBackend` backs up before overwrite, falls back to `.json.bak` on read failure and throws when both fail; `FavoritesManager` tracks `_loadFailed` and **refuses to write**; history loading gained a startup guard; all four favorite entry points wrap `toggleFavorite` with try/catch plus a `favoriteSaveFailed` message.
- **Download covers**: `_saveCoverImage` now passes the per-source `effectiveFor(source)` profile; `_normalizeRemoteCoverUrl` normalises protocol-relative URLs; `AppCoverImage` treats `//` uniformly; coverKey separator changed to `_`; zero-byte leftovers are deleted and re-downloaded; local group covers fall back across batches to the first non-empty one.
- **TOC positioning**: `chapter_list_sheet` now uses `scrollable_positioned_list` and item indices (exact first-frame alignment, jumpTo for locate-current, filters cleared before locating, top/bottom by index, list rebuilt on filter changes).
- **Log export**: new `core/debug/log_export.dart` (log + environment header written to a temp file; HarmonyOS uses FileExporter save-as, others use share_plus); runtime log body is one `SelectableText` block, fixing one-line-only copy; both log pages gained "Export log file".
- **Book source · rule evaluation**: upward rule arguments evaluated in reverse with results backfilled by index; boundary fixes for parentheseless `@put`, inline `@js:`, selector group splitting, unknown XPath predicates returning false, and balanced scanning for inner `AnalyzeJson` rules.
- **Book source · variables**: put null now deletes at source / book / chapter levels; whole-block replacement deletes before adding; cross-round write-back aligned via `bookVarsDeleted` / `chapter.__syDeleted`; large variables routed at a 10000 threshold; `getVariable` checks normal table → big variables → empty string.
- **Book source · TOC & paging**: empty first page still evaluates nextTocUrl; TOC page ceiling raised 200→2000 with a warning; `nextChapterUrl` uses the cached fallback; multi-page list/detail variable propagation; failures fail instead of returning empty results.
- **Book source · network & encoding**: new `charset_registry` (Java charset aliases plus GBK/GB18030/Big5 etc.); PUT/DELETE/PATCH with binary `_syBodyB64`; cache keys include body / webJs / charset / proxy; rate limiting uses fixed windows and keeps progress; Dio timeouts 15s/60s; `filename*` decoded per RFC 5987.
- **Book source · jsoup / WebView / login**: `Elements`/`Element` collection and traversal surface, `abs:` against baseUri, sibling collections excluding the element; WebView POST prefetch (`_postPrefetchForWebView`); `loginCheck` replaces the whole response (url/headers) and advances per round; source header `@js:` evaluated by the host; `initUrl`, speed test and cache-key fixes.
- **Stability**: fixed a duplicate `defineProperty` on `source` in the preset script that aborted it (making `java.ajax` and globals unavailable), recovering book-source tests from 719 to 844 passing; cross-IIFE calls in the `cache` section now use `global.__syB64FromBytes`.
- **Tests**: the full book-source suite passes 857 / fails 23 (identical to the baseline); new tests for paragraph comments, variable deletion, binary cache, charset and preset-script assertions; `dart analyze lib` reports 0 errors.
- **Known limits**: unknown charsets still fall back to UTF-8; `unrar` / `un7z` still only handle the zip path; `JavaMap` keys are stringified; WebView paths need on-device verification.

### 📝 Changelog (v4.0.0-beta.1 → v4.0.0-beta.2)

> 🧪 **Pre-release beta.** 46 commits, still from the `feature/legado-booksource-compat` branch; adds audio playback and live streams while continuing book-source compatibility. No breaking data changes.

- **Audio playback**: new three-page audio UI (cover / chapter list / lyrics) with a single-row spatial control bar; lists and lyrics scale by distance from the centre and re-centre ~3s after you stop (first and last items included); the bottom bar stays only on the cover page and supports cover-based colouring; the speed sheet emphasises the selected row in the primary colour; embedded lyrics from audio book sources reach the player.
- **Live streams**: new `LiveStreamPolicy` and protocol detection (duration stuck at 0 while position advances for ~3s, or rtsp/rtmp prefixes); live cache profile (cache-secs=4 / 1s hysteresis / 16MiB / forced seekable disabled); three VOD-path fixes for live (readiness, resume seek, reconnect seek); 30s continuous-buffering watchdog + low-level error subscription + reconnect budget reset after 90s; red-dot LIVE badge and keyboard arrow guards.
- **File sources**: download links and local import; the detail page lists source files (tap to download or open), progress card reads local progress and browsing history; `LocalContentManager` keeps author and binding fields on insert / dedupe / cover backfill.
- **Evaluation**: RSA moved to host export with OAEP / strict semantics; AES-GCM; random sources seed from content (converging replay); replay placeholders are not cached and hex decoding is strict; dual semantics for `java` objects and body-title rules reach the reader; `data:` chapter URLs and `type` option byte hex; fixes for JS composite list rules and array pagination.
- **Discovery**: pure-JS `org.jsoup.Jsoup.parse` plus a minimal DOM / CSS selector set; script failures surface as visible errors; category lists cache per source, invalidate on exploreUrl changes and force-refresh on demand; `viewName`/`action` share the infoMap Java Map surface; source/cache/infoMap semantics and AES-GCM completed.
- **Sessions & auth**: on HTTP 412 the session cookie is fetched from the site root and the request retried; explicit Cookie values win when merging; `callBackJs` event callbacks and event bits; chapter purchase `payAction`; scripted headers and login Cookie overlay evaluated during image fetching; `loginCheckJs` AnalyzeUrl facade and response refetch.
- **Source identity & lists**: identity aligned to the `bookSourceUrl` primary key, fixing missing sources in online lists; search added to the source library and online source lists, scrolling with the list; removed the discovery expand arrow from online lists.
- **Images & comics**: comic image headers aligned with a replay wait ceiling; fixed comic chapter image parsing; image downloads gated by body context and bad cache entries evicted on failure.
- **HarmonyOS**: book-source WebView interaction and fetching enabled on HarmonyOS; bridge error messages now include location so jsLib compatibility rewriting triggers.
- **Source management**: file-type sources allowed; fixed hanging network imports and multi-source list crashes; bulk insert plus background parsing for multi-source imports; removed the "enable recommended sources" shortcut, keeping per-source toggles.
- **Onboarding**: a disclaimer page (5 key points + required agreement) at the end of onboarding.
- **Credits & engineering**: added a Legado with MD3 credit (README in both languages / in-app credits / release notes); the release pipeline now concatenates a bilingual Release body (Chinese first, `## English` separator), and release docs gained English versions.
- **Tests**: the book-source compatibility suite and new unit tests (live profile, bridge / context / regex compatibility) pass; `dart analyze lib` reports 0 errors.

### 📝 Changelog (v3.6.0 → v4.0.0-beta.1)

> 🧪 **Pre-release beta**. 42 commits from the not-yet-merged `feature/legado-booksource-compat` branch; the main line is the Legado book source compatibility layer. No breaking changes to existing sources or user data.

- **Import fidelity**: Book source fields such as `ruleData` / `jsLib` are no longer lost on import; source variables are merged into source management and persisted (survive restart), and script `source.putVariable` is written to disk.
- **Rule syntax**: Aligned ElementsSingle (index / exclusion / range step / negative index / `tag.` `class.` `id.` `text.` `children.` prefixes, CSS used only with `@css:`), XPath (td/tr shell padding / predicates / unions / compounds), the full JSONPath set, `textNodes` per-node semantics, `replaceRegex` in multiple forms, inline `@js:` rules, `@put` without parentheses, and `bookUrlPattern`; RegexCompat translates inline flags / `\Q..\E` / possessive quantifiers / atomic groups / `\p{In…}`; allInOne regex no longer defaults to dotAll.
- **java.* bridge · interoperability**: Pure-JS implementation of `Packages` / `JavaImporter`, filling in high-frequency classes per the corpus — Cipher / Base64 / Arrays / String / hutool / GZIP / okhttp3 / Jsoup connect / RSA signing, etc.; unregistered classes retain a TypeError.
- **java.* bridge · crypto**: `createAsymmetricCrypto('RSA')` (SPKI/PKCS#8/raw PKCS#1, PKCS#1 v1.5 type1/type2 and NoPadding, chunking by key length, built-in 2^16 limb + Montgomery modular exponentiation); AES ECB/CBC + PKCS5/7, DES/3DES, SHA/HMAC, variable chains; OAEP/EC/CTR/GCM/CFB/OFB explicitly return empty.
- **java.* bridge · fonts and elements**: `queryTTF`/`replaceFont` parse sfnt in pure JS (cmap format 4/12, loca/glyf) to restore obfuscated characters; `getElements`/`getElement`/`getStringList` host inline evaluation + jsoup-style wrapping; `timeFormat` aligned with legado.
- **java.* bridge · network family**: `java.ajax/get/post/head` support header merging and `followRedirects:false`; a `StrResponse` superset (body/code/statusCode/headers/header/cookies/url/isSuccessful/bodyAsBytes/raw); AnalyzeUrl exposes lastStatusCode/lastResponseHeaders/lastFinalUrl; `syResp` and `String(body)` semantics.
- **Dynamic rule replay**: `java.*` is backed by a deterministic protocol of "record call → host evaluate → backfill cache → rerun" (≤4 rounds); the settle cap is raised 4 → 16 rounds / 120s / stop when no new fetches, ajax and webview merged into the same round scheduling; the replay cache is pushed incrementally to JS globals, so long catalogs no longer require reloading the whole table.
- **Discover page**: ExploreKind structured parsing (type/action/chars/default/viewName/style) and 6 types of inline option bars (url/text/button/toggle/select), values persisted per source; dynamic category placeholders are replayed after host fetch, with cross-page dedup, automatic flipping past empty pages, and a fallback when the first category fails; lenient GSON kinds JSON parsing fixes missing categories in 29 sources.
- **Book source type dispatch**: `bookSourceType=2` → mangaSource + `images` adaptation (the body pipeline collects image URLs, plain-URL lines as fallback, Episode.id stores the chapter URL); type=1/4 → media bar + a media-chapter playback card in the novel reader, with direct deterministic parsing preferred; `bookSourceType` is read from selectors.
- **Login and WebView**: `loginCheckJs` / `loginUi` / WebView login trio, form values readable within the login scope; a headless WebView source extractor (`java.webView`, the `webView:true` option), with `webJs` executed inside the WebView and fed back; login state is no longer lost during category parsing.
- **Context and isolation**: `run()` changed to Zone passing, fixing null context after await caused by the async first frame popping the stack and cross-source context bleed under concurrency; cookie domain-match tightened; per-source JS engine pooling (cap 8, eviction and release); deleting a source cleans up cookies / variables and pooled engines.
- **Request headers and cookies**: Response Set-Cookie is stored per source and replayed automatically; default and image requests no longer fall back to injecting a baseUrl Referer (aligned with legado, which only adds UA), with existing Referers migrated; full-chain requests for sources with a `##` suffix fixed; java.get dispatches with two semantics based on argument count.
- **Rule detail fixes**: A batch of alignment fixes for list / detail / catalog rule semantics, missing synopsis, out-of-order catalogs, discover URL encoding and option consumption, baseUrl division of labor and post-processing timing, `source.key` returning the source URL, discover scoping and dedup, etc.
- **Testing and engineering**: shuyuan suite 84/84; bridge / context / regex compatibility-layer tests and standalone verification scripts; localization adds audio / video chapter copy; internal code names in commit messages neutralized; uncovered Java APIs are about 2.6% of calls / 3% of sources, explicitly degraded with no fabricated results.

### 📝 Changelog (v3.5.0 → v3.6.0)

> 🎉 **Stable release**. 16 commits relative to v3.5.0, centered on a **major overhaul of novel continuous scroll and the TTS chain** (seamless chapter-end continuation, separate TTS position storage, chapter-end continue-reading on by default with save migration, and a string of fixes for progress coordinates / highlights / pause / dropped audio), **player orientation adaptation** (automatic orientation following the video, portrait pages, a shared bottom bar for landscape and portrait), **source library category tabs + a three-tier source fallback**, plus global MD3 haptic feedback and several UI fixes. No breaking data changes; reinstall over the top is safe.

- **Novel · continuous scroll**: Added `scrollAutoNext` (on by default, can be turned off in Settings → Layout); `_NovelScrollSegment` segments text by chapter and concatenates it, appending the next chapter when within half a screen of the bottom (within the pre-built range), with 10s backoff + footer retry on failure; `ScrollEndNotification` settles the dominant chapter, `_scrollSegStarts` flat prefixes locate positions; when off, it retracts in place by the intra-chapter ratio without writing a dirty save.
- **Novel · TTS**: `ttsAutoNext` changed to default true and introduces `kNovelPrefsSchema = 2` (false in old saves is treated as the historical default, and later user choices are written back as v2); added `novel_tts_pos_<id>` to separately store the TTS segment, isolated from reading progress, with a "Remember TTS position" toggle; the online chain reports `currentIndex` (segment index) to fix highlights not moving / resuming jumping to the chapter start; `MediaKitTtsPlaybackControl` provides sentence-level pause / resume / stop, and the system engine switches to stop + remember-position-and-reread.
- **Novel · progress**: Segment-start position changed from "screen y + scroll offset" to the content coordinate from `RenderAbstractViewport.getOffsetToReveal` (eliminating a constant offset that left the dominant chapter permanently null); the segment-start cache is refreshed every frame, with the first segment falling back to the content start; a 10% dead zone on segment height; anti-regression only absorbs jitter within 5% and lets cross-chapter / appended cases through; `>= 0.985` rounds to 1.0, and scrolling to the bottom counts as full.
- **Novel · dropped audio**: Online chain uses `writeAsBytes(flush: true)` + 200ms silent warm-up then `seek(0)` to restore volume (user confirmed it is fixed); the sentence splitter fixed the flaw of "swallowing any ≤12-character run before a colon as a character name"; the system chain merges consecutive sentences of the same character, calls `setVoice` only when multiple voices are configured, and adds 80ms between sentences + a leading pause. **Audio dropped at the start with flutter_tts is not fully resolved**, due to a system engine limitation.
- **Player · orientation**: Locked orientation gains "Follow video" and sets it as the default, decided after the first width/height event (no lock before ready, square treated as landscape, re-decided on episode change); a manual rotation button is added to the mobile bottom bar, overriding the automatic decision within the session; entering and exiting full screen applies the currently effective orientation.
- **Player · layout**: A shared bottom bar for landscape and portrait (previous episode / play / next episode | danmaku … playback speed / aspect ratio / rotation / episode selection), with time moved to both ends of the progress bar; 40dp buttons, both groups on narrow screens scaled down by the same factor; a 6dp horizontal padding progress bar spanning the full width; edge lock / screenshot visible only on the control layer; the four-stage locked-orientation setting supports horizontal scrolling on narrow screens.
- **Source library · tabs**: `AppTabBar.compact` (text-only, 48 high, indicator shrinks to the label); the source library view page changes from group headers to dynamic "Novel / Media / Comic / (Other)" tabs + `TabBarView`, `TickerProviderStateMixin` supports controller rebuilding, `_lastTabIndex` is restored after reload, and selections persist across tabs.
- **Source library · multi-source fallback**: Added `CdnMirror` (jsDelivr → raw.githubusercontent.com → ghfast.top reverse proxy, 600ms ladder race, 4s connect / 8s receive / 12s hard cap), with the connection pool going through `NetworkConfigService.instance.globalProfile` to inherit proxy / DoH / Hosts; manifest and rawUrl both go through `CdnMirror.fetch(text, url)`, with relative paths resolved against the actually working address; `_load` is single-flight to prevent re-entry.
- **Network · diagnosable errors**: `HttpFetcher.onError` falls back to `e.error.toString()` when `e.message` is empty; added `libraryFetchFailed`, so failure messages no longer expose internal exception strings.
- **Global · haptics**: Tabs / switches / sliders / long-press menus / drag sorting / favorite·bookmark·like·read are mapped to MD3 haptic semantics tick / toggle / thunk / light; HarmonyOS declares `ohos.permission.VIBRATE` and steps everything down one level overall.
- **UI · other**: Bangumi favorite status five chips changed from `Wrap` to `DesktopHorizontalScroll + Row` (item types remain Wrap); the comic motion-effects toggle gains a persistent `_DevStageBanner` (`AppStatusColors.warn`, one shared component updated in three places), with `motionEffectDevWarning` in both zh/en l10n.
- **Documentation**: Filled in encrypted-channel engine behavior, script async conventions, prefetch response header boundaries, cookie merge rules, and media host rewrite scope; repository developer docs and the official site tutorial synchronized in zh/en.
- **Internal**: Reader preference schema migration; localization copy completed in both zh and en; the Linux release build disables `-Werror` imposed on pub plugins by the generated project (newer clang treats literal operators in old JSON headers as errors), keeping `-Wall` warnings; `dart analyze lib` 0 error; no breaking dependency changes.

### 📝 Changelog (v3.4.0 → v3.5.0)

> 🎉 **Stable release**. 30 commits relative to v3.4.0, centered on **wide-screen / tablet two-pane details** (with a settings toggle, draggable width, push-in page hosting, and HarmonyOS tablet device type), the **global rule pack for novel text purification** (12 built-in rules / automatic migration of old rules), **network and crypto channel hardening** (source-level media host rewrite, ECH retry and direct multi-IP, unified image channel), plus a batch of fixes for Bangumi authorization, cross-platform backup, and announcement loading. No breaking data changes; reinstall over the top is safe.

- **Wide-screen · two-pane details**: Added the `TwoPaneDetailController` global singleton and right-pane container; `AppNavigator.openContentDetail` becomes the unified entry point (only taken over by two-pane at the root route + window ≥1120, with 13 direct-push call sites migrated); `ContentDetailScreen` gains embedded/onClose inline modes, `TabbedShell` passes through onBack; `AppTokens.twoPaneBreakpoint = 1120`; narrowing the window automatically collapses and falls back to a full-page route.
- **Wide-screen · push-in pages**: `TwoPaneDetailHost` wraps the body of search / online list / real-URL browsing / download pages, with the decision changed to "host scope present in ancestor chain"; narrow-window behavior unchanged.
- **Wide-screen · interaction**: Settings "Detail Appearance" gains a "Two-pane detail" toggle (on by default); the divider is draggable to resize (`ValueNotifier` rebuilds only the pane area), clamped to [400, window-520], retained within the session.
- **Tablet · HarmonyOS**: `module.json5` deviceTypes gains tablet; `PlatformService.isOHOSTablet`; added `core/widgets/responsive.dart` width tiers; the comic reader gains "Automatic wide-screen double-page" (landscape and ≥840, vertical / strip comics excluded); wide-screen content layout follows the desktop style.
- **Novel · text purification**: Rules moved to global storage (`novel_replace_rules_global_v1`), seeding 12 built-in rules from `assets/novel/replace_rules.json` on first launch (10 on by default); rules gain `applyTo` (all / this book only / this source only) and `isBuiltIn`; old `novel_replace_rules_v1::<bookId>` rules are migrated to this-book-only rules when the book is first opened (with a migration marker to prevent duplication); each book keeps a single master toggle; the page now uses settings-system components and goes fully through l10n (40 new keys), supporting long-press drag sorting and restoration of built-in rules.
- **Network · source-level media host rewrite**: `PluginConfig.mediaHostRewrite` (`{originalhost: targethost}`, exact match, case-insensitive); `_absoluteCoverUrl` goes through `_rewriteMediaHost`, covering both list and detail cover exits; the ECH takeover scope includes the rewrite target domain, so covers and pages share the same channel; `antiHotlinking` remains an optional override.
- **Network · image channel**: The image cache service gets the effective network profile per source (previously fixed to the global profile, so source-level ECH / proxy had no effect); `SourceImage.buildHeaders` has an unconditional image-shaped Accept, removes Referer fallback injection (signed CDNs pass without Referer; hotlink protection is explicitly declared via `antiHotlinking.referer`); asset requests add `Sec-Fetch-Site` and no longer send incomplete header combinations a browser would never produce; desktop "Follow system proxy" reads the Windows registry proxy entry.
- **Network · crypto channel**: DoH bootstrap failure falls back to resolving the target domain via purely encrypted DNS; when the server rejects the config, reconnect using the retry config it delivered, and cache the measured working config per domain; ECH and direct connections unify on fd mode (`SSL_set_fd` + blocking handshake) to avoid anomalous judgments under BIO pairs; direct connections changed to try multiple IPs one by one with `connect_timeout` and cache the result; added ALPN `http/1.1`, header normalization (Host first, header names Title-Case, `Connection: close`); concurrency cap 32→64.
- **Source parsing · dynamic categories**: The `routes.categories` channel (script or builtin) returns a set of categories, preferred by the UI, falling back to `categoryEntries` on failure.
- **Source parsing · prefetch response headers**: Single JSON / text prefetches now use `getJsonWithHeaders` / `postJsonWithHeaders` / `postTextWithHeaders`, with response headers passed as the second handler argument (multi-arg form is the array `[body, headers]`, zero impact on single-arg handlers).
- **Source parsing · other**: Detail API `episodeCount` mapping added; the JS sandbox async entry goes to the unified `handlePromise` in a Dart-Future shape; explicit Cookie headers merge with the session jar by name and are no longer overwritten by echo-back; empty-id entries use a stable hash fallback for Hero tags.
- **Announcements**: The page now renders immediately via `loadLocal()` (memory → prefs cache → bundled asset), then `_refresh(silent)` in the background; three-tier source concurrency (600ms per tier) + single-flight `_pullRemote` + an 8s `Timer` hard cap + a shared static Dio; empty lists are treated as failures.
- **Bangumi**: Token endpoint falls back from "configured base → official bgm.tv"; `sessionExpired` / `lastAuthError` and expiry notices; 12h early pre-renewal (`onBeforeRequest`); `sanitizeToken()` cleans zero-width characters / quotes / the `Bearer ` prefix and self-heals in `init()`; `tokenFingerprint` for easier diagnosis; 401 uniformly shows "Login expired".
- **Cross-platform backup**: Added `platform_path_compat.dart` (path ownership by scheme + import filtering + startup self-repair); `backup_archive` / `cloud_sync_service` filter before writing; splash opens each box with `_openBoxResilient` (corrupt ones quarantined with a preserved copy) and rebuilds on `downloadManager.init()` failure; orphaned download record recovery is now best-effort.
- **Other fixes**: `AppCard` changed to `Material(child: InkWell(...))`, fixing click crashes inside lists and improving ripple clipping; mixed-type label text on detail pages judged by `label` mode (`hasTranslatableLatinWord`), with echo-back not written to cache.
- **Documentation**: The source-authoring tutorial reorganized into 22 graded sections and synchronized with the official site; `docs/OHOS_INSTALL_GUIDE.md` added and the README install section changed to two paths; the `developer-guide` (zh/en) field table adds media host rewrite and dynamic categories.
- **Internal**: Localization copy completed in both zh and en (40 keys for text purification, plus several for wide-screen and settings); no breaking dependency changes.

### 📝 Changelog (v3.3.0 → v3.4.0)

> 🎉 **Stable release**. 7 commits relative to v3.3.0, centered on **desktop cards (widgets)**: 8 Android widget types and 10 HarmonyOS service cards launched, continue-watching shows real progress and covers, statistics cards share the same source as the app statistics page, following the system for light/dark appearance; also fixes three classes of problems — entrance animation assertion spam, missed translations in mixed zh/en text, and statistics omitting hidden sources — and restores the Windows build under CMake 4.x. No breaking data changes; reinstall over the top is safe.

- **Desktop cards · data layer**: The `HomeWidgetService` singleton aggregates history / downloads / statistics, with throttled pushes on the first frame at startup, foreground/background switches, playback progress, and download changes; snapshots are uniformly sent as strings (Android SharedPreferences and HarmonyOS preferences disagree on numeric types); the theme snapshot is upgraded to a whole `ColorScheme`, with a regenerated set using the primary seed color for the other brightness as fallback.
- **Desktop cards · Android**: The main provider chooses small / medium / large layouts by `OPTION_APPWIDGET_MIN_WIDTH/HEIGHT`, with 7 separate providers for updates, downloads, statistics, heatmap, big number, modular, and streak check-in; cover BitmapFactory downsampling + RGB_565 to avoid TransactionTooLarge; PendingIntent distinguishes action and requestCode per card (`filterEquals` ignores extras, so the earlier four cards overwrote each other); the statistics card reflowed to 2×4 three metrics + a mini monthly calendar; unified 16dp corners and font hierarchy.
- **Desktop cards · HarmonyOS**: FormExtensionAbility + 10 ArkTS cards (`supportDimensions` two tiers + `resizable`); the snapshot key table is a dual read/write filter, so new keys must be added in sync; cross-process preferences persisted with `flushSync()`; card backgrounds and text go through `app.color.*` resources + `resources/dark/` overrides for light/dark; the `formId` list keeps only the most recent 32 to avoid full invalid pushes after repeated reinstalls.
- **Desktop cards · rendering**: Backgrounds and the monthly heatmap are pre-rendered to PNG by Flutter (background 512², reused directly when the parameter fingerprint matches); HarmonyOS covers use a Base64 data URI (card `Image` only accepts `$r()` / `$rawfile()` / Base64); the heatmap is redone as a 7-column calendar for the current month (header, first-day offset, date in cell, today outline, "less→more" legend), with 88px cells for clarity on 3x screens.
- **Desktop cards · settings**: Added "Appearance & Language → Desktop Cards", with background source (cover / theme / solid color), blur intensity, opacity, and the number of continue-watching items (3–8); changes save immediately and trigger a recompute (`HomeWidgetSettingsStore` is a ChangeNotifier); added 17 l10n keys (zh/en aligned).
- **Announcements and contact**: Added the "About → Software Announcements" page (reverse chronological / manual refresh / marked read on open), with the service layer gaining `loaded / all / isSeen / refresh()`; the About page splits out a "Contact Us" group (GitHub repo + official QQ group, opened externally); the settings search registry adds announcement and QQ-group entries with keywords.
- **Fix · entrance animation**: `Entrance` stagger offset changed to directly `index * 0.08`, where from item 13 `animStart > 1.0`, triggering the `begin <= 1.0` assertion in `Interval.transformInternal` thrown every frame; changed to `staggerIndex = index.clamp(0, 5)`, start capped at 0.4, duration no longer expanding linearly with index, plus a regression case for "40 items with large index + replay".
- **Fix · mixed-language translation**: `shouldTranslate` changed to decide by dominant script (adding `isMixedLanguage` / `foreignSourceCode`), so mixed zh/en is still translated while pure Chinese and scattered English model names are not mistranslated; the translation endpoint's echo-back of mixed text changed to explicitly specify a foreign source language and retranslate, collapsing adjacent duplicate segments; mixed echo-back in UI text is not cached, left to AI fallback.
- **Fix · statistics scope**: The statistics overview filters works by source visibility (`isHidden` / `isAgeBlocked`), recomputing the overview, 7/30-day actives, and average sessions from the visible list, and listens to source repository changes for immediate refresh; daily aggregation has no source dimension, so the heatmap / trend / streak still count by module overall.
- **Build · Windows**: Inject `CMAKE_POLICY_VERSION_MINIMUM=3.5` (written to both the variable and ENV, ensuring child cmake processes spawned by `execute_process` inherit it), compatible with the config failure where the pdfium helper project under CMake 4.x still declares 2.8.12.
- **Documentation**: The zh/en READMEs unified to a centered header (icon / positioning / tech stack and release badges / platform badges / language switch / QQ group), with the version notice area adding the group entry.
- **Internal**: The full desktop-card file set committed (Dart + Kotlin + ArkTS + assets); localization generated artifacts committed; no breaking dependency changes.

### 📝 Changelog (v3.2.0 → v3.3.0)

> 🎉 **Stable release**. 16 commits relative to v3.2.0, centered on a **translation system upgrade** (context / terminology closed loop / cache fingerprint / precision translation / AI review / two-stage comic fallback), **novel reading and TTS enhancements** (multi-character TTS, selection translation, Ask AI, note export, underline cloud sync, trend charts, Edge TTS), and **HarmonyOS PC adaptation**. No breaking data changes; reinstall over the top is safe.

- **Translation · context enhancement**: Inject preceding scrolled translation text, batch-boundary continuation hints and the next source segment, and the tail of the previous chapter; the glossary is filtered by whether terms appear in the current batch; unnamed proper nouns are required to follow earlier translations.
- **Translation · terminology closed loop**: After translation, terms are automatically extracted from the actual output (new terms stored per work, aliases merged when translations match, conflicts recorded without overwriting when they differ); the work glossary page shows the global + work-effective tables and pending conflicts, with adopt / keep actions; an auto-extraction toggle; the terminology version is included in the cache fingerprint.
- **Translation · cache fingerprint and expiry notice**: Chapter translation cache records an input fingerprint (version / language / style / CoT / normalized source / actually matched terms), recomputed when returning to the panel and glossary page, with a one-click retranslate on expiry; old cache without a fingerprint is not misjudged.
- **Translation · precision mode**: Three concurrent drafts at different temperatures per block, then compared and composed segment by segment; partial draft failure uses the remaining ones, total failure falls back to a single translation, composition failure takes the first draft; off by default (about 4× tokens), the toggle persists and is included in the fingerprint.
- **Translation · AI review**: The review page reviews segment by segment in the cloud, packaging evidence per chunk into one request that produces findings and a revised full text; revisions are written back to cache only when the user adopts them, in shadow form, keeping the fingerprint aligned with the source.
- **Translation · two-stage comic fallback**: Page-level visual translation produces one output, validates and retries on correction failure, then degrades to OCR → per-ID translation; strict ID protocol and targeted supplementary translation; partial-result status + background supplementation + cross-session continuation; the overlay renders only real translations, with a badge and manual retry; errors classified by HTTP status, with endpoint failover only for switchable errors.
- **Translation · three detail-page fixes**: Long-press gesture jitter tolerance (shared tolerant_long_press, 40px); long-press labels attributed to translation (Tooltip no longer steals the gesture); the six translation toggles changed to write to disk immediately; when the target language matches, it prompts "No translation needed".
- **Novel · multi-character TTS**: Character cards (name / alias / gender / dual-domain voice), dual-domain fallback routing, HTTP TTS sliding-window concurrent synthesis with ordered playback (first sentence plays immediately), audio md5 caching, AI storyboard two-stage attribution (returns only character / gender / confidence, discards hallucinated ids, adopts ≥0.6, chapter-level cache fingerprint), a cross-chapter continuous playback toggle, and system TTS per-sentence voice switching (HarmonyOS degrades to a single voice); fixes for the TTS start position being ignored, speed stuck at 1.0, and an async Wakelock exception on dispose.
- **Novel · six reader items**: Selection toolbar "Translate / Ask AI" (carrying chapter context, reusing the AI multi-route); Markdown export of notes / highlights (grouped by chapter, system share); fine-grained WebDAV sync of underline notes (per-book files, pull-merge at startup, push on backgrounding / exit, set-union semantics); a 7/30-day reading-time trend line chart on the statistics overview; built-in Edge voices for online TTS (Sec-MS-GEC v2 token implemented in Dart, WSS synthesis verified); toolbar adaptation for wide and narrow screens with a full-bleed background.
- **Novel · interactive reading layer**: A new settings toggle (off by default), centered point follows focus; enabled only in single-page page-turn mode with no zoom / rotation, with the original animation layer retained in other modes.
- **Settings · AI page and cloud sync**: The AI page reflowed into three sections, removing secondary folding and flattening nested mini-cards; a dedicated "Ask AI" endpoint config card added (blank falls back to the general one); the cloud sync page gains a "Sync underline notes" button and status card; Edge TTS voice dropdown and preview use the unified new style.
- **HarmonyOS · PC (2in1) adaptation**: Added device form and window control native channels, distinguishing PC / phone by device type; PC initializes a desktop window, scrollbars, and window full-screen; the 6 directory-import entries restored on PC (DocumentViewPicker FOLDER + copy into the sandbox), with the phone keeping its degradation.
- **HarmonyOS · special capabilities**: Cross-device continuation (rebuilding by chapter window / position after handoff), background download keep-alive (dataTransfer), app clones (≤5 instances), window rectangle memory, status bar tap-to-top, rotation and 2in1 layout adaptation.
- **HarmonyOS · ECH build**: CI automatically cross-compiles `libechproxy.so` and verifies its size and four exported symbols; the build script is compatible with NDK root directory conventions.
- **Fix · Bangumi**: 401 automatically renews with refresh_token and retries (concurrent requests share one refresh); when a personal token cannot be renewed, the original 401 is kept.
- **Acknowledgments**: wenyi (MIT © BigDawnGhost) — each stage of the translation pipeline is a clean-room independent implementation, credited only on the acknowledgment surface (README bilingual / About page / l10n).
- **Internal**: Localization generated artifacts committed; comments and docs continue the neutral-wording cleanup; no breaking dependency changes.

### 📝 Changelog (v3.1.0 → v3.2.0)

> 🎉 **Stable release**. 81 commits relative to v3.1.0, centered on the **official landing of HarmonyOS (HarmonyOS / OpenHarmony) adaptation** (phases 1–5 full flow + 23 wrap-up commits), bringing unsigned iOS builds, built-in free translation, screen-cast restoration, Monet wallpaper color extraction, HarmonyOS volume-key page turning and TTS, and more. No breaking data changes; reinstall over the top is safe.

- **HarmonyOS adaptation · architecture and platform layer**: All repository platform checks consolidated into a unified service (30 sites); dependency source switching (16 plugins and transitive deps) and local patches; a feature-degradation matrix and full degradation of directory-picker class entries; display name / icon / download directory adaptation.
- **HarmonyOS adaptation · source parsing**: A self-developed QuickJS native bridge (C API + pumping the microtask queue empty after each evaluation), so embedded JS-script sources run directly; the shell project and patch scripts brought under version control; emulator x64 gets the QuickJS / WebView native libraries.
- **HarmonyOS adaptation · playback core**: media_kit / media_kit_video HarmonyOS adaptation source integrated, with prebuilt libmpv artifacts bundled (arm64), playback on by default and a build switch to fall back to a degradation notice; player PiP secondary fallback and degradation notices complete.
- **HarmonyOS adaptation · system capabilities**: System notifications (including channels and permission requests), PiP (community adaptation fork, control panel and state sync), saving images to albums (`photoAccessHelper` system confirmation dialog, permission-free), clipboard images (native pasteboard), the system "Save As" export (plugin / backup), CoreSpeechKit offline TTS, volume-key page turning (native key channel), native mDNS screen-cast discovery, and system wallpaper primary-color Monet extraction (live following).
- **HarmonyOS adaptation · network**: Source WebView integrated with ArkWeb ProxyController; the ECH engine cross-compiled per the OHOS NDK and bundled in the HAP (FFI), with the build script completing OpenSSL environment variables and symbol checks to avoid silently building an ECH-less version.
- **iOS**: Added an unsigned IPA build (`--no-codesign` + Payload packaging), PRODUCT_BUNDLE_IDENTIFIER unified to `com.nexhub.app`; the display name unified to NexHub across all platforms.
- **Translation · built-in free channel**: Integrated the Edge/Bing free translation endpoint; titles / tags / synopses / comments / novels / subtitles use the free channel by default, falling back to AI on failure or unavailability; a circuit breaker (3 consecutive failures → 5 minutes silent), glossary and advanced style automatically switch to AI; UI text aggregated in 40ms batches + local cache.
- **Player**: Buffer tier alignment (fixing slight stutter from too-shallow buffering in data-saving mode); records the actual soft / hard decode and cache tier at startup (a basis for diagnosing stutter); screen-cast restoration; PiP on both platforms.
- **Data and stability**: History records persisted in a separate file (fixing loss on restart); favorites and download tasks stored in separate files + one-time migration; file preferences written serially key by key; a QuickJS release race spam fix; image save write-back verification added; danmaku matching skipped as a whole when credentials are missing; install packages strictly matched by platform, and HarmonyOS updates jump to the browser.
- **Interface**: Page transitions changed to each platform's system default; HarmonyOS back accent-color jump fixed, and the loading page shows the wallpaper primary color directly on the first frame; storage-location sheet overflow on landscape / small windows fixed; missing source cards in the low-spec all-card mode fixed.
- **CI · unified release discipline (v30)**: Any `v*` tag builds all platforms (including iOS), and the HarmonyOS HAP is built in parallel by a separate workflow then appended to the **same** Release; the "tag containing ohos skips all platforms" exception is removed, and platform-suffixed tags are no longer used for separate releases.
- **Internal**: The platform degradation matrix and known-issues list updated with real-device verification; comments / docs continue the neutral-wording cleanup.

### 📝 Changelog (v3.0.0 → v3.1.0)

> 🎉 **Stable release**. 13 commits relative to v3.0.0, centered on **player and video sniffing enhancements (frame stepping, auto-fullscreen on playback start, best-candidate selection for sniff results)**, a **search experience upgrade (live hot words, Enter to submit)**, and a batch of fixes (lost history covers, blocked in-app update downloads, missing ECH engine on Windows). No breaking data changes; reinstall over the top is safe (same signing key).

- **Player · frame stepping**: When paused, "Previous frame / Next frame" buttons added on both sides of the central play button, using native mpv frame-step / frame-back-step commands, advancing precisely by the container's true frame rate (not the core fallback 1/24s seek); on desktop, comma = previous frame, period = next frame (when playing, press pauses first then steps).
- **Player · auto-fullscreen on start**: Playback starts in immersive fullscreen (landscape locked), with the bottom-bar fullscreen button removed; the mobile system back exits the page (dispose unconditionally restores orientation and system UI), and desktop keeps the F key; each episode re-enters fullscreen on episode change / continuous play, with PiP and disconnection self-healing not falsely triggered; the left-edge lock / right-edge screenshot buttons are aligned horizontally with the central play button.
- **Player · error-page back bar**: A semi-transparent gradient back bar added to the top of error pages for parsing / extraction failures and exhausted auto-reconnect — previously error pages had no control layer and desktop had no system back gesture, leaving no exit after failure.
- **Search · live hot words**: The hot-word data source changed to live-pulled "Featured" ranking entries (anime / book channels), with Chinese names completed via the detail API and cached persistently; when the ranking is unavailable, it falls back to the live hot-search API; the old remote operations list layer removed (old sample words hogged priority so the live layer never ran); long-press a history hot-word chip to delete a single item (with confirmation dialog).
- **Search · Enter to submit**: Source search removes live typing search (no more requests fired mid-typing), triggering only on Enter / the search key / tapping history hot words and clear; the redundant 300ms debounce removed. SearchHistoryStore reads and writes are serialized to prevent interleaved revival of history entries.
- **Video sniffing · best-candidate selection**: `SnifferEngine.bestPlayable` sorts by "playlist / full video > ts segments > MIME video > other" and picks the best, with first-capture priority on ties; headless download sniffing changed to best-candidate selection instead of taking the first — extensionless ad placeholders (some sites push short videos via risk control) no longer displace the real direct link.
- **Video sniffing · passive network-layer capture**: Headless sniffing hooked into shouldInterceptRequest network-layer capture, covering blind spots of hooks such as players inside iframes / Worker fetch; the player's first sniff raised 12s→15s (slow path: playback page → cross-origin iframe → hls.js measured 10s+, and capturing returns early without affecting normal pages).
- **Video sniffing · real-link capture fix**: Extensionless media element direct links promoted, and sniffing no longer jumps to the top-level player page, fixing real-link capture for some sites' "premium routes"; the built-in sniff hook script committed (previously mistakenly ignored by the `*.js` generated-file rule).
- **History · cover fix**: Local entries merged to inherit covers, cover info passed through the reader, and cache filenames gain a module prefix to prevent cross-writes; during startup backfill, unreachable sources are marked and skipped instead of resending cover requests for the whole batch.
- **In-app update · speed-test download fix**: Mirror probing gains a hard time limit and self-defense cancellation, so speed tests no longer stall downloads; candidate mirrors are rate-limited in batches + a total budget.
- **Windows · ECH engine completed**: Windows release packages now bundle the ECH local engine DLL (using a committed DLL + CI artifact verification) — previously the installed Windows version's ECH did not work due to the missing DLL, and it is genuinely functional from this version.
- **Internal**: Comments / commit messages / docs continue the neutral-wording cleanup; CI build scripts adjusted; repository ignore rules revised (.mimosa scan state, source debug backups); no new dependencies.

### 📝 Changelog (v2.0.3 → v3.0.0)

> 🎉 **Stable release**. Relative to v2.0.3 (the previous stable version), spanning the entire 3.0.0 beta line (beta.1 → beta.4, around 80+ commits) plus a final round of 26 commits — a major feature leap with a stable wrap-up. No breaking data changes; reinstall over the top is safe (same signing key).

- **App-wide Material 3 visual system**: Full dynamic color extraction (Monet following the system wallpaper) + 9 palette styles; app-wide UI and settings unified to the design system; frosted-glass sidebar / bottom bar, and separate preview pages for local / network import.
- **Media servers (Emby / Jellyfin)**: Browsing / searching / playing / favoriting / progress fully connected, with multi-address automatic switching + foreground keep-alive, and a three-way decision before playback between original-image direct connection / direct play / server-side transcoding, with bidirectional sync of favorites and progress.
- **Network · ECH multi-platform**: The native ECH engine (OpenSSL) covers Android's three architectures + the Windows desktop; scoped app-level / source-level / Bangumi-only; macOS / Linux temporarily fall back automatically without bundled native libraries. A two-layer model of proxy / DNS / Hosts / SNI.
- **Source editing and source management refactor**: The source editing page split into five tabs + modular folding; source management joined cards + drag sorting.
- **Three major reader enhancements**: Novel style customization + double-page / whole-book page numbers; comic super-resolution + cache clearing; video media_kit + danmaku, background playback / PiP / skip intro and outro.
- **Comic motion effects**: A layered animation engine (parallax / breathing / weather / light effects), toggleable inside the reader.
- **Final polish round (26 commits)**: Massive network-connectivity hardening (request header case preserved to evade WAF fingerprints, 403 switches IP after dropping the connection pool, cleared SNI no longer discarded, CF 1034 edge restriction fixed, source-login WebView network following); fetch and parsing robustness (image 302 following, captcha misjudgment fixed, VideoExtractor nested braces, automatic passing of the "system security verification" page for common video-collection CMS, unified WebView UA/Cookie); route body/headers + optional params, search changed to a source-checkbox model, and a batch of source regression tests locked in.
- **Internal**: Comments / commit messages / docs continue the neutral-wording cleanup; no new dependencies; the CI four-platform build continues as before.

### 📝 Changelog (v3.0.0-beta.3 → v3.0.0-beta.4)

> 🧪 **Pre-release beta**. 10 commits relative to v3.0.0-beta.3, a minor update centered on **network-chain hardening (ECH multi-platform + proxy / Hosts / WebView full chain)**, interface detail polish (the source editing page split into five tabs, filter panel folding and lazy loading), and an update-dialog fix. No breaking data changes; reinstall over the top is safe (same signing key).

- **Network · ECH multi-platform**: The native ECH engine (OpenSSL) now covers Android's three architectures (arm64-v8a / armeabi-v7a / x86_64) + the Windows desktop (via FFI); Bangumi's ECH merged into the connection mode "three-way choice" unified toggle; macOS / Linux have no bundled native libraries yet and automatically fall back to direct connection. Scopes remain three tiers: app-level / source-level (`network.ech`) / Bangumi-only.
- **Network · proxy / Hosts / WebView full chain**: A source's built-in `hosts` are genuinely wired into the three chains of WebView / sniffing / downloads, with multi-IP failover added (fixing "works in browser, times out in app"); Android WebView following changed to static proxy rules (ProxyConfig does not support PAC); Windows WebView2's `host-resolver-rules` quoted to prevent command-line splitting — fixing the root cause where the DIRECT fallback never took effect.
- **Interface · source editing page refactor**: The source editing page split by "Basic Info / Network / Parsing / Filters / Advanced" into five tabs, making long forms easier to use; each module supports on-demand folding.
- **Interface · filter panel**: Groups support folding + lazy loading, so sources with many groups and long entries open faster and use less memory.
- **Android · notch screen**: The theme adds `windowLayoutInDisplayCutoutMode=shortEdges`, fixing the black bar at the top of the immersive reader fullscreen so notches / punch-hole screens are neither obscured nor left black.
- **Privacy**: Hidden source history filtered at the display layer; incognito determination criteria unified, and the incognito state shown in words in the menu.
- **In-app update**: The update dialog is no longer truncated at 6 lines, using a self-built lightweight markdown renderer so long release notes display fully and correctly with basic formatting.
- **Internal**: Comments / commit messages / docs continue the neutral-wording cleanup; no new dependencies; the CI four-platform build continues as before.

### 📝 Changelog (v3.0.0-beta.2 → v3.0.0-beta.3)

> 🧪 **Pre-release beta**. 11 commits relative to v3.0.0-beta.2, a feature update centered on **interface personalization (font / detail appearance)**, network enhancements (ECH implementation), and source management and media-server polish. No breaking data changes; reinstall over the top is safe (same signing key).

- **Network · ECH implementation**: Ported the native ECH engine (OpenSSL), genuinely effective for direct HTTPS connections, no longer depending on an external proxy; scopes split into three tiers: app-level / source-level (`network.ech` declarable in source JSON) / Bangumi-only; sites without ECH support fall back per domain adaptively; when the native library is absent (non-Android / not bundled), the whole set automatically degrades to direct connection.
- **Interface and theme**: Added global font settings (follow system / three built-in OFL fonts / custom import); detail-page appearance settings (cover dynamic accent color + cover blurred background).
- **Detail-page interaction**: Swipe actions on the narrow-screen chapter list, grid mode for all types, streamlined chips; online browsing source switching changed to a bottom sheet from the title, removing the source chip bar.
- **Source management**: Source list unified to the joined-card style + drag sorting.
- **Sniffer**: The results panel height is draggable and customizable, initially collapsed by default.
- **Media server**: Poster resolution adapts by density + backdrop prefetch, collection browsing, search history / cross-channel prevention, and the statistics panel's media-server data dimension; on desktop, mouse-drag horizontal scrolling and the media-server block scroll with the list.
- **Source fixes**: Engineering fixes for some anime sources protected by Cloudflare (verification wall rethrow, WebView2 proxy, failed domain migration, tag array filtering); media-server capabilities merged into the core-feature detail (zh / en).
- **Internal**: Comments / commit messages / docs continue the neutral-wording cleanup; no new dependencies; the CI four-platform build continues as before.

### 📝 Changelog (v3.0.0-beta.1 → v3.0.0-beta.2)

> 🧪 **Pre-release beta**. 28 commits and 134 file changes relative to v3.0.0-beta.1 (+15112 / -925), a major feature update centered on **media server integration (Emby / Jellyfin) and comic image super-resolution**. No breaking data changes; reinstall over the top is safe (same signing key).

🇨🇳 Released on National Day 2026-10-01; happy National Day to everyone.

- **Media server integration (Emby / Jellyfin)**: Added media-server data models and an API client, compatible with both Emby / Jellyfin dialects; log in by server address + account, with server entries using a separate namespace, fully isolated from local content and source content.
- **Connection stability**: A single server can configure multiple addresses, automatically switching to backups one by one on failure; periodic keep-alive while the app is in the foreground; addresses can be added / removed / managed in settings.
- **Browsing and playback**: Poster walls (uniformly cached posters), genre / year filtering and sorting, detail-page parallax hero images and shared-element transitions; poster cards with watched badges / progress tracks, episode cards with episode-number badges, detail-head title shadows and info chips, and unified skeleton screens and entry grouping; before playback, an automatic three-stage decision between "original-image direct connection / direct play / server-side transcode", with support for manual bitrate tiers and audio-track switching and real-time playback info, and in-player episode switching and continuous play; metadata readiness wait relaxed to 30s × two rounds of self-healing restart (compatible with slow first-packet servers).
- **Interaction and system integration**: Bidirectional favorite sync, continue watching (NextUp), watched marking; watch progress written both locally and to the server; server entries merged into unified history management and global search; deleting a server entry also cleans up the corresponding local history / favorites.
- **Comic reading**: Image super-resolution enhancement (multiple tiers, entry appears automatically only for low-resolution images), image cache categorization and automatic cleanup, and a streamlined reader interface.
- **Fixes**: WebDAV PROPFIND response parse failure; a playback freeze probe (distinguishing Cloudflare challenge interception from network unreachability and giving actionable hints); appending self-auth parameters to playback URLs (player redirects dropped headers causing infinite loading) and detail-title station-logo priority; a global transparent system navigation bar + bottom gesture-bar avoidance on each page; super-resolution tiers changed to auto show/hide (smoothly expanding when the toggle is on, auto-collapsing when off) and removal of the small-card wrapper to avoid a card-in-card; correction of the timing of the fake probe implementation in offline-state unit tests.
- **Internal**: Code comments and commit messages unified to neutral wording, continuing the beta.1 cleanup.

### 📝 Changelog (v2.0.3 → v3.0.0-beta.1)

> 🧪 **Pre-release beta**. 12 commits plus working-tree changes relative to v2.0.3, a major update centered on **landing the app-wide MD3 visual system, frosted glass and import previews, and comic motion effects**; underlying work completed the material_ui 1.4.0 migration and dynamic_color unpinning. No breaking data changes; reinstall over the top is safe (same signing key).

🌟 Special thanks to **mobai0z0** for contributing the comic motion effects (layered animation engine).

- **MD3 visual system**: Full dynamic color extraction (Monet following the system wallpaper) + 9 palette styles; app-wide UI and settings unified to the design system (joined cards, row styles, three-level settings pages); all reading settings folded + inlined panels on all three platforms.
- **Frosted glass and import previews**: Frosted-glass sidebar / bottom bar (customizable); separate preview pages for local / network import.
- **Comic motion effects (contributed by mobai0z0, experimental)**: A layered animation engine (static page → depth layering → 32 layered effects → GIF), toggleable and adjustable inside the reader; ⚠️ still being polished, with further optimization to come.
- **Underlying and dependencies**: material_ui 1.4.0 migration (329 imports + compatibility bridge), dynamic_color unpinned 1.8.1 → 2.1.0 (Monet chain verified), full migration of deprecated APIs, haptic feedback unified through the official HapticFeedback, comments and docs unified to neutral wording (cleaning up internal code names and example source-site names).

### 📝 Changelog (v2.0.2 → v2.0.3)

> ✅ **Stable release**. 3 commits and 52 file changes relative to v2.0.2, concentrated on **engine robustness, the MD3 haptic specification, and download and interface stability**. No breaking data changes; reinstall over the top is safe (same signing key).

🌕 Happy Mid-Autumn Festival; may the moon be full and people at peace.

### 🛠️ Engine and Source Parsing

- **JS sandbox preloads atob / btoa**: `_jsContextPrelude` preloads atob / btoa polyfills (decoding semantics aligned with the inline version embedded in source scripts, leniently stripping illegal characters and trailing `=`); a source script's own same-named declarations override as-is, so existing sources are unaffected and new sources can omit the inline polyfill.
- **meta multi-hop global persistence**: `FlutterJsEngine` gains `_loadedScripts`, evaluating each script only once per instance (failure is not cached); in a meta multi-hop chain, each hop's `__processor` no longer replays the whole script, and top-level vars remain visible across hops, matching the "globally visible for the lifetime of one JsEngine" convention.

### 🎮 Interface and Haptics

- **Haptic feedback restructured per official Material 3 semantics**: `AppHaptics` rewritten to `tick` / `click` / `toggleOn` / `toggleOff` / `thunk` / `confirm` / `reject` / `gestureThreshold`; the old `selectionClick` / `light` / `medium` / `heavy` remain as compatibility aliases (about 200 call sites auto-mapped).
- **Android native side switched to official vibration primitives**: API 31+ uses `VibrationEffect.Composition` combined primitives (`TICK` / `CLICK` / `THUD`, with an `areAllPrimitivesSupported` check first), 29+ uses `createPredefined`, then falls back to an amplitude single pulse; `vibrator.cancel()` retained to prevent queue buildup.
- **Components mounted per the spec**: switches / checkboxes about 45 sites → `toggleOn` / `toggleOff`; sliders `tick` per step (confirm on release); radio `tick`; pull-to-refresh → `gestureThreshold`; long-press `thunk` (about 15 action entry points).

### 📦 Downloads and Stability

- **SAF download fix**: `.cbz` with `application/zip` was rewritten by the provider to `.cbz.zip` per MIME and `rename` was rejected by the ROM; switching to creating it as `octet-stream` yields the correct filename; the `rename` fallback path gains retries and same-name cleanup.
- **Entrance animation fix**: `Entrance._play` changed from `late final` to `late`, fixing `LateInitializationError` spam and a broken replay when switching tabs and replaying.
- **Bookshelf history**: When the age restriction is on, `mature` source entries are automatically hidden (display-layer filter, restored when turned off); widget tests and an entrance-replay regression test added.

### 📝 Changelog (v2.0.1 → v2.0.2)

> ✅ **Stable release**. 2 commits and 15 file changes relative to v2.0.1, concentrated on **download / update channel reliability** and the **image saving and sharing experience**. No breaking data changes; reinstall over the top is safe (same signing key).

### 📦 Downloads and Updates

- **Update package integrity check**: In-app updates previously had no integrity check at all; three cases — a mirror returning 200 + an HTML error page, the server cutting the stream early, and a leftover locally truncated file — all produced a bad package that was silently delivered for installation. This release parses the byte-count field from the GitHub API for release assets; after download, a three-way check (stream truncation / byte-count comparison / file-header magic), failing any of which deletes the bad file and automatically switches to the next mirror to re-download; same-name reuse now includes a byte-count comparison; a second check is done before launching installation. Fixes the occasional "cannot decompress" on update (Fixes #13).
- **High-Android-version download path fix**: `defaultDownloadPath` falls back to the app documents directory when `getExternalStorageDirectory()` is null; self-repairs at startup historically invalid `file_picker` real paths that are not writable under scoped storage.

### 🖼️ Image Saving and Sharing

- **Save images to the public album**: Added `ImageSaver` + the `nexhub/media_store` native channel; Android 10+ writes to `Pictures/NexHub` via MediaStore (permission-free), and desktop writes to the downloads directory; wired into the comic reader and RSS image "Save".
- **Image sharing fix**: Comic / RSS image "Share" changed to use `share_plus` to genuinely share the image file via the system share sheet (previously it only copied the local path).

### 🎨 Interface and Experience

- **Unified global list-sheet styling**: `bottomSheetTheme` (no shadow + rounded corners + antialiased clipping) and `popupMenuTheme` (no shadow + rounded corners), inherited automatically where no style is explicitly passed.
- **Hotlink-protected source 403 fix**: Corrected a local variable in `_buildHeaders` shadowing the chapter-page Referer argument, fixing 403 on save / copy / share for binding-type hotlink-protected sources.

### 📝 Changelog (v2.0.0 → v2.0.1)

> ✅ **Stable release**. 7 file changes relative to v2.0.0, concentrated on **source parsing robustness, the network-favorite script channel, and video parsing stability**. No breaking data changes; reinstall over the top is safe (same signing key).

### 🔧 Source Parsing and Network Favorites

- **Numeric operations in route placeholders** (`lib/core/models/plugin_config.dart`): Numeric placeholders support `{page-1}` / `{page+1}` / `{page*30-30}`, with operators `+` `-` `*` `/` followed by a non-negative integer, evaluated left to right in written order (no precedence), and clamping negative results to 0. Use `{page-1}` for 0-based pagination and `{page*30-30}` for JSON API `offset` pagination in one step. Non-numeric placeholders are untouched.
- **Network-favorite list script channel** (`online_content_list_screen.dart` + `script_resolver.dart`): When `webFavorite.route` points to a JSON script endpoint, the favorite list is fetched through `ScriptResolver` with a `comments.login` token injected, up to 200 items; HTML source sites keep the original `getHtml` path.
- **Add-to-favorites script channel** (`web_favorite_action.dart`): When `webFavorite.add.route` points to a script endpoint, the source script performs the multi-step request + authentication (first fetch the work id, then POST); if not logged in, it prompts to go to the source account settings and paste a Token; a non-empty list returned is treated as success.
- **meta protocol chained multi-hop** (`script_resolver.dart`): When a handler returns another meta descriptor, one more hop is taken (up to 4 hops), for two-step "fetch id then submit" APIs; single-hop scripts have no side effects.
- **`{detailUrl}` passthrough + same-origin http→https upgrade** (`plugin_config.dart`): When a template is exactly `{detailUrl}` and the value is an absolute address, it is returned directly, avoiding a `https://base/http://real` double-host broken link; same-origin absolute `http://` links on list pages are upgraded to `https://` to avoid http direct-connection timeouts.

### 🎬 Video Parsing

- **Scripted video routes take priority** (`video_player_screen.dart`): Sources with `hybrid` + a video overlay of `type=='script'` use deterministic script parsing, avoiding the worst-case 12s sniff wait and the high-crash zone of the embedded browser on Windows; on script failure it falls back to general sniffing.
- **Cross-domain direct-link Referer correction** (`video_player_screen.dart`): When an extracted direct link is on a different domain from the source site, the capturing page's own Referer is used, reducing 403s from third-party parsing sites / CDNs.

### 📚 Developer Documentation

- `docs/developer-guide.md` / `docs/developer-guide.en.md`: Placeholder documentation updated to "numeric operations", adding `{page*30-30}` and the left-to-right evaluation rule for `+ - * /`.

### 📝 Changelog (v2.0.0-beta.8 → v2.0.0)

> ✅ **Stable release**. 6 commits relative to beta.8, concentrated on **comic image loading and source parsing robustness**, plus a new declarative source capability for image-byte decryption, `imageTransform`. No breaking data changes; reinstall over the top is safe (same signing key).

### 🖼 Comic Image Capabilities

- **Declarative source image-byte decryption (`imageTransform`)**: Some image hosts encrypt the image bytes themselves (decrypted and rendered by the site's JS in the browser), so providing only hotlink headers still yields ciphertext. A source can declare "match by host + decryption method" in the `imageTransform` section, and the engine decrypts uniformly at the image-download layer — supporting `aes-cbc` / `aes-ecb` / `rc4` / `xor`, with IV from a file-header prefix / fixed / all zeros, padding `pkcs7` / `none`, and keys and IVs in `utf8` / `base64` / `hex`; decrypted plaintext goes into the disk cache and is inherited automatically by Save / Share (9158d33).
- **Chapter-page Referer-derived image fetching**: Comic chapter pages derive the Referer from the current page URL when fetching images, making image fetches on hotlink-protected sites more reliable (d387c46).
- **Local cache for image favorites**: Image favorites support local caching and can be viewed offline (d387c46).
- **Rating annotation aligned to 16+**: Rating annotations displayed in line with the 16+ rating label (d387c46).

### 🛠 Engine and Image Compatibility

- **General rendering and image compatibility enhancements**: Enhanced general rendering paths and image-format compatibility so more image sources / hosts load normally (c503ea0).
- **Fetch-layer JSON negotiation**: `getJson` / `postJson` correctly carry `Accept: application/json` per JSON negotiation and fall back to unescaping, fixing parse failures where some sites' JSON routes returned HTML-wrapped escaped JSON due to negotiation (d0cd74d).
- **Cookie-rotation site image fix**: Sources configured with Cookie rotation no longer get stuck in endless image refreshing (9d4098a).
- **Startup local-cover backfill crash fix**: Fixed a concurrent-modification crash caused by backfilling local covers at startup (e704c3c).


### 💬 Author's Note

- After two to three months of intensive continuous development (often ten-plus hours a day), the author reached the 2.0.0 milestone and will enter a rest period; maintenance will continue (bug fixes and stability), but features may not grow substantially. See RELEASE_BODY.md, "The Author's Words".

### 📝 Changelog (v2.0.0-beta.7 → v2.0.0-beta.8)

> ⚠️ **Pre-release beta**. 5 commits relative to beta.7, all interface / interaction refactoring, with no changes to parsing or data logic. No breaking data changes; reinstall over the top is safe.

### 🎨 Visual and Micro-interactions

- **Unified design tokens and micro-interaction animations**: Added `app_tokens` / `app_theme` and `app_animations` (work card slide-in / hover, numeric-change pulse `AppValuePulse`, refresh indicators, etc.), with a batch of hardcoded sizes changed to design tokens; the Settings → Appearance page refactored (890b7c1).
- **More compact font sizes and spacing**: Overall smaller font sizes and tighter spacing for easier scrolling through long lists (890b7c1).

### 🧭 Navigation and List Experience

- **Swipe to switch navigation**: Home / categories support left-right swiping to switch (9e43003).
- **Cleaner source list**: The source management list removes the redundant URL line and shows source names on a single line; the two input boxes in the source-library add bar have unified corner radius (radiusMd) (9e43003 / ec64f0e).
- **Online browsing alignment**: Online browsing search and filter layouts are left-right symmetrical; the RSS top bar restored; the source-list category bar divides width evenly (b75c8b0).

### ✨ Detail Polish

- History button moved next to search, sniff status distinguished by color, the add bar made smaller overall; swiping switched to Offstage for optimization, and the online source browser interface streamlined (d389e7c).
- The network-settings page proxy-mode switch changed from `SegmentedButton` to an `AppValuePulse` pulse animation (pure UI, no logic change) (890b7c1).

### 💬 Author's Note

- After two to three months of intensive continuous development (often ten-plus hours a day), the author needs to rest for a while; maintenance will continue (bug fixes and stability), but there may be no major new features and the pace will slow. See RELEASE_BODY.md, "The Author's Words".

### 📝 Changelog (v2.0.0-beta.6 → v2.0.0-beta.7)

> ⚠️ **Pre-release beta**. 1 commit relative to beta.6, a small but critical fix: resolves the problem of "in-app update says download complete, but the installed package is the old version". No breaking data changes; reinstall over the top is safe.

### 🔄 In-app Update

- **Fix for accidentally installing an old package**: In-app update packages are now stored in directories by release version number (`<cache dir>/updates/<version>/`). Root cause: some platforms' asset filenames are fixed without a version number (e.g. the universal Android package `app-release.apk`), so a leftover old package from the previous version had the same name as the new asset and was mistaken for the new one by the "reuse local same-name file directly" logic — presenting as instant "download complete" and an unchanged version after install (8023242).
- **Package integrity check**: Before reusing a locally downloaded package, the file-header magic is verified by extension (APK/ZIP = `PK\x03\x04`, EXE = `MZ`) to defend against truncated leftovers from abnormal terminations such as process kills (`deleteOnError` only covers Dio's throw path, not process kills) (8023242).
- **Automatic cleanup of old-version leftovers**: When downloading a new version, best-effort deletion of other versions' leftover subdirectories under `updates/` (limited to inside those subdirectories, not touching other paths), avoiding cache accumulation (8023242).
- **Compatibility note**: Android `FileProvider`'s `cache-path` is configured as `path="."` (recursive), so an APK in a subdirectory is unaffected when handed to the system installer; Windows package filenames include the version number and were never affected by this bug, and now uniformly follow the new directory rule (8023242).

### 📝 Changelog (v2.0.0-beta.5 → v2.0.0-beta.6)

> ⚠️ **Pre-release beta**. 8 commits relative to beta.5, a major update centered on **RSS subscription reading**: RSS upgraded from a simple list inside the browse page to a full standalone reading module (offline cache / full-text fetch / image gallery / inline video and podcasts / groups and OPML / in-site search / system notifications), plus fixes for a batch of real-device feedback on media loading and layout. No breaking data changes; reinstall over the top is safe.

### 📡 RSS Subscription Management

- **Bind categories / move back to global**: Subscriptions can be bound and unbound between "Global Subscriptions" and the novel / comic / video categories; the global list shows all subscriptions and a category page shows only that category (0fd4a18).
- **Groups (multi-value tags)**: One subscription can belong to multiple groups, with a horizontally scrolling group filter bar at the top of the list, supporting create / rename (merging duplicate names) / delete a group (only removes the tag, not the subscriptions) (0fd4a18).
- **OPML import / export**: Supports both file selection (`.opml` / `.xml`) and pasted text, with per-item checkbox preview before import; export is organized by group and sent via the system share sheet (0fd4a18).
- **Site auto-discovery**: After entering a site address, the home page is fetched to parse candidate subscription sources, and if none are declared, common paths are probed; check to add (0fd4a18).
- **favicon backfill**: The subscription list shows site icons, preferring a self-supplied icon, otherwise falling back to the site-root favicon, and to a generic RSS icon if unavailable (0fd4a18).

### 📖 RSS Reading Experience

- **Offline cache + full-text fetch**: Opening an article automatically fetches and caches the body text, readable without a network; on fetch failure it falls back to offline content with a notice (0fd4a18).
- **Read and favorites**: Marked read on open (read items greyed out entirely), per-article star favorite, and a cross-source "RSS Favorites" summary page (entry: Settings → Data & Accounts) (0fd4a18).
- **In-site search**: Search within a single subscription and global search across all subscriptions, based on the local cache for offline use, with a hit count (0fd4a18).
- **Image gallery**: Tapping an image in an article opens a full-screen gallery with zoom, drag, save, and share (0fd4a18, 901fc5c).
- **Reading settings grouped + night mode**: Font size / line spacing / alignment / margins grouped by category, with a new night mode synchronized with the app theme (c30118c).
- **Layout alignment and content sanitization**: Unified list and body layout; body rendering skips scripts, embedded frames, forms, and other elements, and external links go to the system browser with unsafe protocols blocked (901fc5c, 05cd683).

### 🎬 In-article Media Playback

- **Inline video playback**: In-article video changed to 16:9 inline playback, with control-bar progress / duration / bottom positioning fixed and the buffering indicator synchronized (901fc5c, 6bf9f68).
- **Player capabilities aligned with the main player**: Gesture adjustment (brightness / volume / progress), a lockable control bar, aspect-ratio switching, and playback-position memory (1eb5cb1, dee5388).
- **Podcasts and attachments**: Audio attachments can be played directly in the article page (multiple audio tracks switchable, draggable progress); video / file attachments offer "Open Attachment" (901fc5c, 05cd683).
- **Image 403 and audio 0:00 fixes**: Image downloads now go through the app's unified network layer with a source identifier, fixing images that would not load on some sites; fixed audio-type detection failure causing duration to show 0:00 (05cd683, 901fc5c).

### 🔔 Update Notifications

- **System notifications**: Added a "System Notifications" toggle, aggregating one system-level notification after update detection; Windows / Web automatically degrade to an in-app unread badge (0fd4a18).
- **Auto-check while charging**: RSS update detection gains a "While charging" trigger, coexisting with "When opening the app" (c6f3c2d).

### 🧩 Format Compatibility and Parsing

- **Four formats supported**: RSS 2.0 / Atom / RDF (RSS 1.0) / JSON Feed all parse, no longer throwing "unsupported format" (0fd4a18).
- **Non-UTF-8 encoding fix**: Charset detected from the XML declaration and response headers, correctly decoding GBK-family and Latin-1-family encodings, fixing garbled text (0fd4a18).
- **Relative links absolutized**: Entry links / covers / attachments and subscription site addresses / icon addresses are all completed to absolute URLs against the subscription address (0fd4a18).
- **Conditional GET (304)**: Sends ETag / Last-Modified, and reuses the local cache when the server returns 304, so refreshing no longer re-downloads (0fd4a18).

### 🌐 Network and Connectivity

- **DNS multi-address retry one by one**: When custom DNS / pinned IP resolves to multiple IPs, they are tried in order, fixing "works in browser, app connection times out" (c6f3c2d).

### 🐛 Other Fixes and Hardening

- **Fetch timeout and cache-first**: Fixed subscription refresh timeouts; the list shows cache first and refreshes in the background, making opening faster (c6f3c2d).
- **Inline video timing race**: The player instance is now created only after tapping play, fixing occasional connection failures (c6f3c2d).
- **Unified subscription entry**: The browse page and settings page use the same RSS-subscription implementation, and the early duplicate internal implementation was removed (0fd4a18).
- **l10n**: Net addition of 151 zh/en strings (2567 → 2718, none removed), covering long-form reading, attachments, groups, OPML, search, notifications, and related interfaces (cumulative across commits).
- **Dependencies**: Added `flutter_local_notifications ^17.2.0` (system notifications, degraded on Windows / Web) and `http ^1.6.0` (image downloads reuse the unified network layer) (0fd4a18, 901fc5c).
- **Tests**: Added RSS parsing and OPML unit tests (0fd4a18).

### 📝 Changelog (v2.0.0-beta.4 → v2.0.0-beta.5)

> ⚠️ **Pre-release beta**. 1 commit relative to beta.4, concentrated on fixing the **network-favorite multi-folder experience** and the **source network-profile coverage**. No breaking data changes; reinstall over the top is safe.

### 📚 Network Favorites (Multiple Folders)

- **Folder switching fix**: Fixed the folder list being always empty (parsed results were mistakenly cast to MediaItem so no data could be read); it now correctly lists each folder (92d6a3e).
- **Two-level navigation fix**: Network favorites changed to two levels, "folder list → works", fixing "All" clicks doing nothing and empty folders having no back button (92d6a3e).
- **Folder item counts**: Folder cards show the number of items in that folder (92d6a3e).

### 🛰️ Network and Connectivity

- **Unified source network profiles**: Comments, tag browsing, and favorite lists now uniformly apply the source's declared network configuration (SNI / pinned IP / custom DNS), fixing connection failures on these pages caused by not using the source network profile (92d6a3e).

### 🐛 Fixes and Hardening

- l10n: Added the "Back to folder" string (92d6a3e).

### 📝 Changelog (v2.0.0-beta.3 → v2.0.0-beta.4)

> ⚠️ **Pre-release beta**. 20 commits relative to beta.3, centered on a **reliability and usability overhaul of cross-language translation**, with extensive hardening of **network connectivity, favorites, downloads, the update channel, and the source library**. No breaking data changes; reinstall over the top is safe.

### 🌐 Translation (Cross-language Reading)

- **Primary/backup translation endpoints with failover + health circuit breaker**: Automatic switch to the backup endpoint on primary failure, temporary circuit breaking with recovery probing on consecutive failures, reducing whole-segment failures from occasional AI-endpoint 5xx / timeouts (1764607).
- **Chapter translation checkpoint resume**: Checkpoints written per chunk, allowing resume from the breakpoint after interruption instead of retranslating the whole chapter (532c7c9).
- **Glossary injection + unified prompt pipeline**: Consistent proper nouns across segments, with a glossary shared across books; translation prompts unified (9c18011).
- **Optional polishing + evidence-driven review**: Translated text can optionally be polished a second time, with original-text evidence attached to key sentences for verification (1c59adc).
- **Book pre-scan**: Before entering translation, a chapter summary + whole-book overview is generated and injected for more coherent context in long books (5204e53).
- **Reusable translation asset export**: Translations exported as reusable assets (f59fb72).
- **Comic translation bubbles backfilled into rendering**: Translation bubbles backfilled by layout, with less leftover on page turns and more accurate overlay (9e4893f).
- **Offline subtitle translation for whole videos + bilingual export**: Full-video subtitles translated offline and exported as bilingual subtitles (eba1dd7).

### 🔄 Update Channel

- Candidate-link downgrade retries, strict speed-test validation, and stronger custom-mirror robustness (5b47eca). Beta.3 last fixed beta-channel detection; this release fixes the candidate chain and speed test.

### 🛰️ Network and Connectivity

- **Same-site request serialization + intelligent backoff** (anti-rate-limiting): A per-host async serial queue eliminates concurrent pile-ups triggering RST; retries distinguished by error nature — connectionError gets an extra retry, connectionTimeout (rate-limit hang) gets one extra + a long backoff, avoiding adding fuel to an already rate-limited site; fixed a streaming-download redirect connection leak (71bc7f1).
- **Network-favorite fix**: Fixed blank lists from using the wrong parsing entry (sources declaring `listEntry` use the correct entry, acf1530); in-app folder switching + add-to-selected-folder (9cbc49c); errors are no longer silently swallowed, showing an error state + retry entry instead.
- **e-hentai login pasted Cookie normalization**: Any common pasted format logs in and parses correctly (4a41c5d).

### 📚 Favorites / Downloads

- **Favorite fixes**: Fixed being unable to favorite on detail pages and lost favorite persistence; the favorite dialog gained "Favorite this chapter" (d6ae661).
- **Download fixes**: Leftover artifacts isolated per item, with meta write failure falling back to the download root directory (b6fc0f7).

### 🧩 Source Library

- Under the age restriction, the source library automatically hides 18+ sources, and the source management page removes the hidden notice; haptic feedback added app-wide (416282d).

### 🐛 Fixes and Hardening

- Fixed a cascade crash caused by a dialog's `TextEditingController` being disposed during its exit animation (a3d29ae).
- Fixed video background-play notification initialization failure and removed the `demo_multi_line` dead reference (442ec0b).
- Build chain upgraded to Gradle 9.1.0 / AGP 9.0.1 / Kotlin 2.3.20 (36a0f93).
- `gen_icons.py` output paths unified through `out_path` validation (13d3215).
- Documentation: Added an "Advanced Translation" chapter and a guide entry (03f2cc5).

### 📝 Changelog (v2.0.0-beta.2 → v2.0.0-beta.3)

> ⚠️ **Pre-release beta**. 8 commits relative to beta.2, centered on the two cross-language reading capabilities **comic page translation + real-time video subtitle translation**, with extensive hardening of the **update channel, network connectivity, and translation stability**. No breaking data changes; reinstall over the top is safe.

### 🌐 Translation (Cross-language Reading)

- **Comic page translation**: The comic reader automatically performs visual OCR + translation on the current page as you turn, with translation bubbles overlaid by viewport / aspect ratio / reading mode; cached by "work | chapter | page | language"; toggles in the long-press menu and reading-settings panel (remembered per work), retryable on failure.
- **Real-time video subtitle translation**: A subtitle-panel toggle (remembered across sessions), throttled reading of player subtitles with per-sentence translation; when no subtitles are present, frame capture OCR as fallback; the overlay at the bottom can optionally show the original; cached persistently by "language | md5".
- **AI settings page**: Added comic-translation / video-translation endpoint cards (blank falls back to the general translation endpoint), reachable from settings search.
- **Full translation-stability hardening**: A comic page translation concurrency semaphore (cap 2, cache hits do not occupy a slot) to avoid 429s on fast page turns; video OCR fallback re-entry guard; exponential-backoff retry for individual subtitle sentences (up to 3 times); a budget guard for whole-chapter novel batch translation (chunking when over the threshold); translation cache capacity limits (5000 entries each) + an entry count and one-click clear in settings; exceptions normalized into connection / timeout / other; OCR fallback track detection to avoid false triggers; image scaling centralized with proper decoder release.

### 🔄 Update Channel

- Version comparison changed to SemVer: for the same core version, pre-release segments are compared segment by segment, fixing the beta channel where "beta.1 → beta.2 was judged as already up to date" and updates were not received;
- Stable release > pre-release, with alpha < beta < rc ordered by SemVer for stepwise upgrades; added pre-release detection (by tag), and a tag fallback for the stable channel; the beta-channel description updated to include alpha / beta / rc.

### 🛰️ Network and Connectivity

- **Runtime SNI control**: SNI defaults to the domain name; "-" means no SNI (to bypass SNI blocking); supports `.example.com` suffix wildcard overrides per site; effective only for direct HTTPS; settings gain a domain → SNI mapping editor and a "Test SNI Handshake" action; SNI / ECH copy rewritten to reflect reality.
- **Direct TLS / port fixes**: Direct HTTPS connections now complete the TLS handshake; explicit ports are respected (previously sources with a port were connected to 443).
- **DNS resolution suffix**: A source declares only a suffix, and each device computes the address at runtime with its own DNS, so the config file contains no IP — convenient for publicly publishing community sources; the four query modes changed to "host + suffix", falling back to the original host on failure, supporting scope hits / subdomain wildcards, with IPv4 preferred + same-family rotation to avoid poisoned unroutable IPv6; multiple Hosts entries are all collected and rotated; fixed loss of the suffix when saving a source-level network override.
- **Source-level network override inherits the source's own config**: After importing a source that carries a `network` block, no reconfiguration is needed; clearing the custom override falls back to the source's own block (not the global one).
- **Headless silent fetching follows source network**: Silent fetching follows source hosts / DoH / proxy; integrated Cloudflare challenge detection and a visible verification page, and bypasses DNS poisoning.

### 🧩 Source Parsing Capabilities (for Source Authors)

- **Route placeholder offsets**: `{page-1}` / `{page+1}`; effective only for pure-integer variables, negative offsets clamped to 0, non-numeric values kept as-is; fixes "page 1 unreachable / duplicate page turns".
- **meta batch prefetch**: A source can return a `__fetchUrls` array (with `__fetchConcurrency`, default concurrency 6, cap 16); the engine fetches concurrently and passes the response array to `__processor` for synchronous handling; a single failure fills that position with null without interrupting the whole batch.
- **Category key-name tolerance**: Category reading is compatible with title / name / type_name.

### 🐛 Other

- Companion docs and tests updated accordingly, covering the above translation / update / network / source-parsing capabilities.

> ⚠️ **Known beta TODOs / not fully verified**: The effectiveness of comic page translation and real-time video subtitle translation depends on AI endpoint quality and the network environment; SNI / no-SNI still needs real-world testing on some sites; ECH direct connection is still not feasible (Dart TLS stack limitation). If you encounter problems after upgrading, please report them via Issues.

### 📝 Changelog (v2.0.0-beta.1 → v2.0.0-beta.2)

> ⚠️ **Pre-release beta**. 107 commits relative to beta.1, centered on **three-reader experience enhancements + a large number of real-device fixes**: the novel reader gains double-page / translation / AI illustrations / content editing / cloud sync / portable-format parsing, etc.; the comic reader gains night viewing / sleep timer / resource and memory optimization; the player gains super-resolution / danmaku sending / cache degradation / error retry / declarative menus, as well as the full lifecycle of system PiP and screen casting, desktop PiP, etc. This is a beta test and may contain undiscovered bugs; please report problems. No breaking data changes; reinstall over the top is safe.

### 📚 Novel Reader (Many New Features)

- **Double-page mode**: In wide-screen page-turn mode, two pages side by side like an open book, with progress based on the left page.
- **Whole-book page numbers**: Header / footer gain a "whole-book page number" slot, accumulating page positions across chapters for the entire book (partial calibration marked with + as estimates).
- **Bilingual / paragraph translation**: Integrated AI translation (OpenAI-compatible), with an original/translation comparison panel and translations cached per book; exports include a `_Paragraph Translation` appendix.
- **AI settings page**: Centralized configuration of AI capabilities such as translation / illustration (model, key, endpoint), with bilingual / paragraph translation settings merged onto the same page.
- **AI chapter illustrations**: Generate illustrations from chapter content, inserted as illustration lines into that chapter, so mixed text-and-image layout appears on reload.
- **AI reading summary / content synopsis**: Generate a summary by whole book or chapter for a quick recap of the plot.
- **Content editing**: Edit the body text directly in the reader and save; edited chapters carry a corner badge and can "Restore original".
- **E-Ink theme**: With the E-Ink preset selected, the body uses charcoal grey with vermilion accent annotation, automatically reverting to bright text at night.
- **Book-source JS simplified/traditional functions**: Source scripts can call `t2s()` / `s2t()` directly for simplified/traditional conversion (same semantics as the reader body conversion).
- **Batch archive import**: Support unpacking txt / epub from zip / cbz / rar / 7z archives into the library, automatically parsing book title / author.
- **Portable document parsing**: Added Mobi / PDF text-layer parsing (pure Dart, no extra dependencies); UMD has no reliable sample yet and is explicitly marked unsupported.
- **Fine-grained reading-progress cloud sync**: WebDAV per-book single-file sync, silently uploaded on backgrounding, with automatic conflict resolution.
- **EPUB export custom template + WebDAV upload**: Custom CSS / cover / synopsis, and the export can be uploaded to WebDAV with one tap.
- **Underline / highlight / excerpt / share**: Selection highlighting + excerpt notes + artistic share cards; supports source-switch relocation and is included with EPUB / TXT exports.
- **Online multi-voice TTS**: Customizable HTTP TTS endpoint for cloud-based multi-voice reading; the sentence splitter judges narration vs. characters by quotes / colons, with 1–8 concurrent predownloads and silence-placeholder degradation on failure plus automatic chapter continuation.
- **TTS notification-bar controls**: The TTS notification bar shows play / pause / previous sentence / next sentence.
- **Predownload while reading**: After reaching a threshold, subsequent chapters are predownloaded in the background for offline reading.
- **Smooth auto page-turn**: Can advance smoothly at intervals, pushing pixels in scroll mode / transition progress in page-turn mode.
- **Bookmark custom corner icon**: Bookmarks can be given a custom corner badge icon.
- **Bookshelf unread badge / new-chapter hint**; sorting by latest-chapter time / Chinese pinyin order.
- **Simplified/traditional conversion enhancements**: Search annotations and results apply simplified/traditional conversion, with phrase-level longest match and an exclusion word list; local book filenames automatically resolve title / author.
- **Long-body multi-page concurrent fetching**: Multi-page catalogs (nextContentUrl) are fetched concurrently and concatenated in order, speeding up large-chapter loading.
- **Page-turn animations and gestures**: 6 animations, a swipe-down-to-bookmarks gesture, and volume-key page turning.
- **Scroll-mode text and image enhancements**: Scroll body justified + illustration banners / cards with alignment.

### 🖼 Comic Reader (Enhancements + Optimizations)

- **Warm night-view overlay**: An independent toggle + intensity slider for more comfortable reading in low light.
- **Sleep timer**: Dual modes by minutes (15–90) or by chapter count (1–3).
- **Resource / memory optimization**: Archive temp directories recycled on exit, preload / render window eviction, image caching by memory budget + a disk-cleanup entry, progress flushed on backgrounding to defend against process kills, and strip-comic decode limits.
- **Double-tap three-state cycle**, **E-Ink refresh**, **ICC color correction** (6 color presets), and **auto-favorite covers**.
- **Configurable preload count (1–16)**, completed keyboard shortcuts, adjustable mouse-wheel speed, mouse cursor feedback, edge-swipe page turning while zoomed, configurable zoom anchor, and image-load-failure retry.

### ▶ Video / Player (Enhancements + Stability)

- **Super-resolution (Anime4K)**: Efficiency / quality tiers, improving the look of sources with no sharpness (enable as needed, mind performance).
- **Full system PiP lifecycle**: Records playback position on entry, resumes on exit, with three small-window actions (play / pause, danmaku, fast-forward), and does not enter when conditions are unmet.
- **Full screen-cast lifecycle**: Bidirectional position sync with the device while casting, reportable errors, and automatic pause on disconnect.
- **Desktop PiP**: Changed to a draggable shrunken always-on-top window, restoring the original window when closed.
- **Danmaku sending and upload**: After logging in to DandanPlay, you can send danmaku (log in in place if not logged in, and auto-resume sending on success).
- **Cache strategy degradation**: On cellular networks / low-memory devices, the cache tier is automatically lowered, taking effect immediately.
- **Tiered error retry**: Tiered timeouts + automatic reopen self-healing at initial / episode switch, reducing freezes.
- **Declarative player menu**, **subtitles remembered per video** (external subtitles / styles remembered by URL), **an anti-overlap track algorithm**, and **stable danmaku position after seek**.
- The player abstraction layer and async session cancellation unified, and the playback page split into multiple module files for improved stability and maintainability.

### 🔗 Cross-type / Bookshelf / Gallery

- **Cross-work reading queue** (novel / comic): The reader's three-dot menu "Add to / Open queue", also addable via long-press on a bookshelf favorite, and automatically removed when opened.
- **Unified image-favorite gallery**: Player screenshots / novel illustrations / comic panels all go into one library, with thumbnails carrying source corner badges.
- **Bookshelf sorting / category filtering**: Sort by latest-chapter time / pinyin order, categories derived from actual formats with empty items hidden, and manual drag sorting supported.
- **Gallery**: Folders + multi-select, predownload hooked into the formal download, filter collapse, and mobile adaptation.


### 🔐 Source Login / Verification

- **Source login API Key mode**: The login panel automatically shows or hides account / password / API Key fields per the source configuration.
- **Embedded WebView login + manual Cookie fetch and backfill**: Login changed to an embedded browser, with a floating button to manually backfill the Cookie.
- **Cloudflare verification fix**: The verification domain now uses mobile / full browser UA, fixing turnstile 600010.
- **DandanPlay new-user registration**: Unregistered users can create a DandanPlay account directly in the app, integrated with the account page.

### ⚙️ Settings / Onboarding / Updates

- **Settings system reorganized**: The settings page structure recategorized, with a new standalone "Update Settings" page (update check / download / reminders, etc.).
- **Settings search completion**: Search in inline settings dialogs can now hit all concrete settings items too.
- **Content and source rename rules**: Customizable rename configuration for content names / source names and network-related settings.
- **Onboarding revamped**: Onboarding content and flow updated, with light haptic feedback added during operations.

### 🐛 Other Fixes and Hardening

- Fixed occasional cover loss; strip comics scroll continuously across chapters upward (no more teleporting / frame flashing).
- Local comic reading progress fully restored: all four entry points — switching chapters / returning to the catalog / tapping exit / re-entering — resume correctly.
- Fixed occasional parse failure for encrypted-source video downloads; fixed single-chapter / single-episode download progress display; fixed the failure of canceling seek with an upward swipe in landscape.
- Fixed a layout issue where body text overflowed the display area in page-turn mode, causing text at the page bottom to be clipped.
- Fixed missing covers for locally imported videos; and several novel-reader polish items — underline color customization / toolbar overflow / tap-to-exit.
- Category first-screen cold-start self-healing and preloading of the first category, avoiding erroneous pop-ups; the history "Hide" soft-delete preserves progress.
- The build side synchronized CI's Flutter version and pinned the PDF dependency version.
- Numerous player / comic / novel-reader interaction and stability fixes.

> ⚠️ **Known beta TODOs / not fully verified**: System-level behavior of background playback / PiP needs real-device verification; super-resolution quality and performance tiers, danmaku sending and token-expiry paths, and the behavior of screen casting / PiP on some device models and desktop environments still need real-device verification; progress-bar drag frame previews were evaluated and are not implemented for now. If you encounter problems after upgrading, please report them via Issues.

---

### 📝 Changelog (v1.2.0 → v2.0.0-beta.1)

> ⚠️ **Pre-release beta**. 44 commits relative to v1.2.0, a major update: underlying upgrade to Flutter 3.47, **a large number of new features and real-device fixes across the novel / comic / video modules**, and newly added **compatibility for importing Legado (Reader) format book sources**. This is a beta test and may contain undiscovered bugs; please report problems. No breaking data changes; reinstall over the top is safe.

### 🛠 Underlying Upgrade: Flutter 3.32.0 → 3.47.0

- Upgraded Flutter / Dart to the 3.47 stable release, with the build chain aligned (Java 17 / AGP 8.11.1 / Gradle 8.14 / Kotlin 2.2.20); **the minimum Android version remains 7.0 (API 24), unchanged**.
- Code-level API migrations (`withOpacity`→`withValues`, `surfaceVariant`→`surfaceContainerHighest`, etc.), with more standardized Material 3 adaptation.
- After the upgrade, incremental build cache cleanup on the Windows desktop (more stable font / asset packaging).

### 📚 Novel Reader Enhancements (Many)

- **Legado (Reader) format book source import compatibility**: Supports importing Legado book sources (JSON / XML / NDJSON), automatically converting to local source JSON; compatible with their `@css/@xpath/@json/@js`, `##` regex replacement, `@put` variables, composite rules, catalog / body pagination, categories (explore) reusing search rules, `subContent` segmented body, `formatJs/preUpdateJs`, `imageStyle/imageDecode`, and other syntax; network import opens all five chains (search / discover / detail / catalog / body) for plain-text sources (type=0).
- **In-book search refactor**: Results carry in-chapter character offsets, jumping directly to the hit page across chapters (no longer only to the chapter's first page); whole-book search changed from serial to 6-way concurrent and merged in chapter order, caching fetched body text for the panel's lifetime; multiple occurrences of a word within a segment are listed individually (previously only the first per segment was reported); a 300-result cap per search to prevent list lag; both body text and keywords are converted per the reader's simplified/traditional setting before matching (so a simplified keyword finds a traditional original displayed as simplified); shows "Searched N/M chapters" progress.
- **Reading summary / quick overview**: Added offline extractive summarization + cloud AI summary (switchable modes) for a quick recap of the whole book.
- **Progress restoration fix** (important): Page-turn progress changed to "in-chapter character offset", resisting font-size / margin changes; fixed "turning to the first page, exiting and re-entering returns to the previous chapter's last page"; exit / backgrounding now writes to disk automatically, no longer losing position.
- **Volume-key page turning**: On by default (consistent with comics), turning pages with the phone's side buttons.
- **Mouse-wheel page turning**: In page-turn mode, the mouse wheel turns pages (direction can be reversed).
- **TXT internal chapter refinement**: Imported TXT changed from "split by double newline" to scanning line by line, so text with only a single newline between paragraphs no longer collapses the whole book into one chapter; title rules enhanced (English Chapter supports Arabic numerals and spelled-out numbers, Chinese numerals gain "两", and fixed names like "Preface / Final Chapter / Epilogue"); a three-fold title-line check (non-empty, line length ≤40, adjacent gap ≥500 characters) filters false positives; long body before the first title becomes a standalone "Preface" chapter; if zero hits in the whole book, a hard cut of about 10KB at paragraph boundaries is used as fallback, with a second split for single chapters over 100KB; the reader hooks into the chapter structure (same as EPUB), so catalog / previous-next chapter navigation / chapter-level progress and bookmarks work.
- **EPUB export embeds illustrations**: Exported EPUBs correctly carry illustrations.
- **Simplified/traditional conversion for downloads**: Download artifacts apply the simplified/traditional conversion setting.
- **TTS fixes**: Continuous chapter continuation, immediate switch on tapping a paragraph, and a ListTile assertion flood fix.
- **GBK / GB2312 site garbled-text fix**: Automatically detects HTML `<meta charset>`, so book titles, authors, chapter titles, and Chinese chapter URLs on gb2312 / gbk sites are no longer garbled (works for common book-source-type sites).
- **A book source's anti-crawling fallback**: When a source declares `useWebview`, pages intercepted by Cloudflare-like walls go through a real browser to fetch rendered HTML and feed it back for parsing.
- **Polish items** such as title-line overflow / font-size drag deadlock prevention and volume-grouping in the catalog.
- **Search history**: Records and quickly reuses recent search terms.
- **Downloaded chapter title display fix**: Novels downloaded locally no longer show chapter titles as internal filenames.
- **Search button crash fix**: Fixed a crash triggered by the reader's search button in some layouts.
- **Replacement rules / highlight rules**: Body purification during layout (pattern / replacement / regex) and highlighting (text color / background / underline), with a per-book toggle and no whole-book re-fetch on changes.

### 🖼 Comic Reader Enhancements (Many)

- **Bookmarks**: Add a bookmark to the current page; the bookmark list can jump to / delete entries.
- **Image-favorite gallery**: Long-press / right-click an image to "Save", grouped into image favorites for centralized viewing.
- **Natural sorting**: Local comics / archives sorted in natural order (2.jpg < 10.jpg) instead of broken lexicographic order.
- **Auto-download**: Automatically predownloads subsequent content while reading (triggered above a threshold) for smoother offline use.
- **Zoom factor indicator**: Shows the current zoom factor while zooming.
- **Absolute URL for top-bar chapter links**: The top-bar chapter address is judged as an absolute URL, so concatenation is more correct.
- **Fullscreen shortcut bound only to F11**: The F key no longer grabs fullscreen, avoiding accidental triggers.
- **Volume-key page turning**: Turning pages with the phone's side buttons (consistent with novels).
- **7 continuous-reading fixes + many real-device fixes**: A large batch of real-device issues fixed for local comic continuous reading, double-tap zoom three states, auto page-turn / scroll, first-screen single-image progress, strip-comic navigation continuity, auto-scroll sticking at the top, and losing changes when closing the settings panel.
- **Aggregated local "back to previous chapter last page" fix**: Aggregated local comics return precisely to the last page of the previous chapter.
- **Double-tap zoom toggle fix**: The "Double-tap zoom" setting previously did not respond to the toggle; it now works correctly.
- **Real fullscreen and keyboard shortcuts on desktop**: window_manager takes over fullscreen (F11 in / Esc out); arrow keys / PageUp·Down turn pages, ± zoom, N·P previous/next chapter; right-click in the image area brings up an action menu.
- **A set of zoom-gesture fixes**: Strip comics can initiate pinch-zoom even when not magnified (also works across pages); a single-finger tap when zoomed no longer falsely triggers page-turn / navigation; double-tap no longer triggers both "page turn + zoom"; the double-tap zoom anchor changed to the finger tap point rather than screen center; clearing residual pan offset after zooming back to 1x; pan clamped at boundaries when zoomed; zoom automatically reset before page turning.
- **Progress-write reliability**: On exiting the reader, pending debounced progress is written to disk before canceling the timer, no longer losing the last few seconds; scroll write-back is blocked during progress restoration to avoid polluting the save.
- **Dual-track brightness**: Positive brightness writes system brightness; negative brightness pushes system brightness to minimum and overlays a black mask, allowing lower readability in low light.
- **Strip-comic negative-margin crash fix**: After upgrading to Flutter 3.47, negative margins in strip comics triggered a framework assertion crash; fixed.

### ▶ Video / Player Enhancements (Many)

- **Multi-source auto-selection + fallback**: Entering / switching episodes resolves by remembered route first; when a route fails, it automatically rotates to the next candidate with a notice, and only reports "link expired" after all are tried.
- **Cross-work playback queue**: The more menu "Add to queue / Next / Queue management", with automatic cross-work continuous play; the most recent queue can be restored at startup; local / direct-link videos can be queued.
- **Background playback + notification bar**: Integrated a foreground media session, so audio-type content keeps playing and shows notification controls on the lock screen / in the background.
- **PiP lifecycle**: Entering / exiting PiP restores position and resumes playback.
- **Skip intro / outro**: Custom skip ranges, automatically skipped.
- **Auto-play-next countdown**: A countdown is shown before an episode ends and auto-play-next proceeds.
- **Sleep by episode count**: Stop after a remaining number of episodes, not only by minutes.
- **Double-tap seek accumulation**: Consecutive double-taps accumulate fast-forward / rewind (±Ns indicator).
- **Thin bottom progress bar**: A 2.5px thin progress bar is shown when the control bar is hidden.
- **Danmaku same-text dedup**: Identical danmaku within a 5-second window are merged, no longer spamming the screen.
- **Local video covers (folder-first + frame capture)**: Prefer a folder cover / same-named image, otherwise generate a cover by capturing the first frame muted; videos imported from Android SAF (`content://`) can also generate covers.
- **Horizontal-swipe cancel gesture**: A clear vertical offset during a horizontal seek cancels the jump, with haptic feedback.
- **m3u8 downloadable**: HLS streams support segmented concatenation into .ts downloads (variant streams and initialization segments handled); encrypted segments still need a key, keeping the known limitation.
- **Control-bar hide lease**: Dragging the progress bar or opening a menu / panel "holds" the control bar so it does not auto-hide in the meantime, restarting the timer on release.
- **Double-tap debounce**: Single taps are blocked for 600ms after a double-tap to avoid false triggers in the three-zone layout.
- **Network speed display**: Real-time network speed (MB/s) shown while buffering, auto-hidden when unavailable.
- **Auto-play for local / direct-link videos**: Opening local and direct-link videos no longer stays paused, matching the online path's behavior.
- **Horizontal-seek direction correction**: The horizontal-swipe direction was previously opposite to double-tap fast-forward (swiping right rewound); now unified.
- **Aspect ratio genuinely effective**: The container no longer fixes 16:9 but follows the aspect-ratio setting, making 4:3 and fill modes visually correct.
- **Episode-switch failure no longer silent**: A failed episode switch rolls back to the original episode with a notice, no longer leaving "new episode index + old frame".
- **Progress before exit not lost**: The last few seconds of progress are now saved correctly on exit / backgrounding (previously silently lost).
- **Sleep-timer end-state sync**: When the timer fires, the UI syncs to the paused state and cancels control-bar auto-hide.
- **Error cache-clear reconnect and danmaku stability**: Load failures include a "Clear cache" action to avoid stale direct-link false freezes; tiered timeouts + automatic reopen self-healing on episode switch; stable danmaku position after seek and ticked performance optimization without stutter.
- **Player-internal robustness fixes**: Retries no longer leak old playback instances; lifecycle rechecks added at each initialization stage; playback-position callbacks throttled to 250ms to avoid whole-page rebuilds; empty route names go through unified translation; screen-cast disconnect changed to awaitable so quick re-entry leaves no residual session; danmaku load-error notices on episode switch match the first-load ones.
- **Exit / switching stability and danmaku crash fixes**: A large batch of fixes for player enter / exit stability, danmaku load crashes, crashes on quick re-entry after exit, and defenses against crashes during playback.
- **Playback-position record rate limiting**: Only the most recent 50 position records are kept per work, avoiding long-term accumulation and bloat.
- Polish items such as aspect ratio, screen-cast handshake timeout rollback, restoring original position on route switch, preserving the sleep timer across episodes, and incremental danmaku injection; danmaku sources compete in parallel and take the fastest response, with shortened timeouts.

### ⬇ Downloads / Sources / Home / Import

- **In-app version upgrade**: Check for new versions in settings, show download progress percentage, and an enhanced mirror list.
- **Intermediate download progress fix**: HLS segment / direct-link / novel downloads all report real intermediate progress, no longer only jumping between 0% and 100%.
- **shuyuan (Legado) import**: See "Novel Reader" above; non-text source types (audio / images / files / video) are marked "Type unsupported" and not selected.
- **PluginConfig author field**: Sources can declare author information.
- **Book source compliance de-marking**: Source format compatibility descriptions neutralized.
- **A book source's WebView fallback**: See "Novel Reader" above.

### 🐛 Other Fixes and Internal Hardening

- Onboarding and the software-announcement sheet adapted to small screens / landscape, with SafeArea added.
- The runtime-log system upgraded (tiered + automatic capture of download / parsing / HTTP errors), with logs added to the shuyuan chain for easier diagnosis.
- Core entry / navigation / storage / services reorganized; build and engineering configuration stability improved.
- UI_BASELINE.md removed from git tracking (file kept); RELEASE_NOTES deduplicated and reorganized; docs slimmed down (a public docs whitelist).

> ⚠️ **Known beta TODOs / not fully verified**: System-level behavior of background playback / PiP needs real-device verification; advanced Legado features (such as individual JS rule syntax) may still need polishing; manual switching of video clarity and progress-bar frame previews are not yet implemented. If you encounter problems after upgrading, please report them via Issues.

---

### 📝 Changelog (v1.1.0 → v1.2.0)

> 20 commits relative to v1.1.0, focused on a **major stability overhaul of the local content (download / import) system** and **enhancements to all three readers**: Android SAF download writes, opening local video / comic / novel files, large-file loading, EPUB chapter parsing, download persistence, and other previously reported pain points were fixed in a concentrated way, and a "Runtime Log" was added to help with feedback and troubleshooting.

### 📥 Local Content Import / Parsing Enhancements

- Added **automatic text encoding detection**, improving the parsing accuracy of local TXT / no-BOM files and reducing garbled text.
- **More stable EPUB import**: The table-of-contents file (toc.ncx) no longer mixes into the body; supports splitting chapters by common patterns such as `class="chapter"` / `class="part"`, solving "the whole book produces only one chapter"; when an Android SAF file has no extension, MIME-type fallback recognition is used, greatly reducing false "empty folder" judgments.
- Local folder scanning is more robust: a failure reading a single subdirectory no longer interrupts the whole import.

### ⬇ Download Management Enhancements + Android SAF File System

- **Android download path**: Changed to the system folder picker (SAF), so the default download directory works correctly on Android; it can be reselected in "Settings → Downloads".
- Fixed the issue where Android SAF downloads had their **filenames rewritten by the system** (e.g. `.cbz` → `.cbz.zip`), making the downloaded content unopenable; after writing, an automatic read-back verification, rename, and leftover-file cleanup are performed.
- Fixed download task IDs containing link slashes causing **write / read path confusion** (re-downloading makes it take effect).
- Download failures are no longer "invisible": failed tasks show normally in the download list, and a new **"Runtime Log" page** (Settings → Advanced) centralizes download / parsing / network errors, with one-click copy for bug reports.

### 📚 Novel Reader Enhancements

- **Greatly improved loading of large EPUB / TXT files** (removed a bottleneck on the pagination hot path), so even oversized chapters turn pages smoothly.
- **Local novel download persistence rework**: Changed to **one independent TXT file per chapter + an images/ subdirectory for illustrations**, fundamentally fixing "downloading in two batches shows only one chapter"; the default download format changed from EPUB to TXT (more universal and directly openable).
- Clicking a local novel uniformly goes through folder-scan reading for more consistent logic; EPUB chapter jumps are smoother.

### 🖼 Comic Reading Enhancements

- Polish for local comic / image import and the reading experience (reading-page operations, image-view menus, etc.).

### ▶ Video / Player Enhancements

- Fixed the problem of **locally downloaded videos (including Android SAF / HLS .ts) loading forever and being unplayable**.
- Video download changed to **"sniff the real address first, then download"**; fixed HLS segment download and single-segment timeouts, improving the download success rate.
- Polish for the video home page browsing / search experience.

### 🔌 Fetching / Sources / Home and Import Flow

- **HTTP fetch enhancements**: Same-origin Referer fallback, etc., improving connectivity and download success rates on hotlink-protected sites.
- **Source-as-Plugin system enhancements**: More stable source loading / images / management panel.
- **Home and import-flow enhancements**: Polish for the local import entry and the local file viewer (images / video / text).
- Bookshelf widget fixes.

### 🐛 Other Fixes and Internal Hardening

- Fixed several problems reported by users.
- Onboarding and the software-announcement sheet adapted to small screens / landscape, with SafeArea added to avoid obstruction by the navigation bar / notch.
- The runtime-log system upgraded (tiered + automatic capture of download / parsing / HTTP errors), making feedback and troubleshooting easier.
- Core entry / navigation / storage / services reorganized; build and engineering configuration stability improved.

---

### 📝 Changelog (v1.0.0 → v1.1.0)

This version has 7 commits relative to v1.0.0, centered on the **local content import system**: novel / comic offline content expanded from "images and TXT only" to a complete import chain of **EPUB / PDF / multi-format comic archives / whole folders / Android SAF**, while **settings search was upgraded to full coverage of 226 items + precise scroll positioning**.

### 📥 Local Novels: EPUB Support (Core)

- The novel reader gains **EPUB** import: parse OPF / XHTML directly in the app to build the chapter structure, with no extra dependencies; TXT remains supported.
- Import routing corrected: .txt / .epub are correctly dispatched to the novel reader, with chapter switching, progress saving, and online chapters behaving consistently.

### 🗂 Local Comics: PDF + Multi-format Archives + Folder Aggregation (Core)

- **PDF comics**: Each page is rendered to an image reusing the existing comic image-view pipeline (the `pdfx` native engine), rendered page by page on first open and cached thereafter; supports cover preview and reading in page order.
- **Multi-format comic archives**: Added `.cbr / .rar / .7z / .cb7 / .cbt` support (pure-Dart decompression, including RAR5), with the existing `.cbz / .zip` still working; natural sorting by image path keeps page order correct; a single-image decompression limit guards against decompression bombs.
- **Folder import aggregation**: After selecting a directory, it asks whether to "merge into one work (folder = one work, internal files = chapters / episodes)" or "import each file separately"; aggregated entries reuse online chapter navigation (catalog / previous-next chapter).
- **Android SAF folder import**: Solves the problem that `file_picker` returned `content://` directories on Android that could not be read — recursively enumerating the directory tree, caching to local files, and reusing all read pipelines, so selecting a directory just works.
- The "Local" sections at the top of all three bookshelves (comic / video / novel) keep the import entry available, so you can import anytime without getting lost.

### 🔍 Settings Search: Full Coverage of 226 Items + Precise Scroll Positioning

- The settings registry covers **226 real settings items**; search results no longer only jump to a settings page but **scroll directly to the specific item** (e.g. searching "Theme Color" goes straight to the custom color-picker row).
- Added a scroll-positioning mechanism (`SettingsAutoScroll`): the lazy list automatically sweeps to build anchors, then smoothly scrolls in and adds a highlight pulse on a hit, enhancing the "lively feel".

### 🔧 Other Experience and Internal Hardening

- The Bangumi OAuth authorization dialog gains a loading progress bar and rounded styling, making the loading state more intuitive.
- The software-announcement service and settings-page internal logic reorganized, reducing redundant rendering.
- Cleaned up duplicate .gitignore entries; the announcement ID updated with the version.

---

### 📝 Changelog (v0.5.1 → v1.0.0)

This version has 1 commit relative to v0.5.1, focused on **onboarding expansion, the software-announcement system, and a Bangumi login rewrite fix**, plus several interface convergences and experience optimizations.

### 🧭 Onboarding Expanded to 6 Pages (Core)

- On first launch, complete onboarding before entering the home page: Welcome → Add a source → Link Bangumi → Privacy and compliance → Basic settings (appearance theme / interface language) → Grant Android permissions.
- The onboarding contains a privacy statement: "Your sources, credentials, and browsing history are stored only on this device and are not uploaded to any server; the app hardcodes no keys."

### 📢 Software Announcement System (Brand New)

- Remote announcements are accelerated via the jsDelivr CDN (automatically falling back to the official source on failure), with unread announcements popping up after the first frame; added `SoftwareAnnouncementService` / `SoftwareAnnouncementDialog` and `assets/announcements.json`.

### 🔐 Bangumi OAuth Login Rewrite (Fixes a Freeze)

- Changed from a separate built-in browser window to a WebView embedded in the dialog; fixed the failure where "the callback was lost when returning after authorization, leaving the UI spinning".

### 🖥️ Narrow-screen Browser Bottom Bar Slimmed Down

- The narrow-screen bottom bar changed to a pure Container with controllable height (40px) + a 1px top divider, with 5 buttons carrying tooltips.

### 📥 Source Management / Collection API Entry Consolidated

- The collection API entry moved into the "Network Import" tab's search box, removing the floating button and redundant inline buttons.

### 🧪 Tests

- Added a comic parser test (`test/manga_311s_parser_test.dart`).

---

### 📝 Changelog (v0.5.0 → v0.5.1)

This version has 2 commits relative to v0.5.0, focused on a **refactor of source management and the favorite flow**, a batch of **source capability enhancements** (one-tap library-source updates / mirror speed tests / automatic mirror fetching / comment compatibility / script text prefetch), plus several crash fixes and experience optimizations.

### 📚 Source Management / Favorite Flow Refactor (Core)

- **Lively drag-sort animation**: Source manager and settings Hero-page drag sorting now use `proxyDecorator` (scale + theme-color stroke + double shadow).
- **Source tile Material crash fix**: Uniformly wrapped in a transparent `Material`, fixing runtime `No Material widget found` crashes on some pages.
- **Single-source search horizontal list**: Mouse / trackpad drag enabled; media / novel / comic home pages hide the collection API floating button to avoid obstruction; several interaction and layout optimizations on library-source / online-content / online-browse / mirror pages.

### 📦 One-tap Library-source Updates (Brand New)

- Library sources support version comparison and one-tap updates, with statuses covering updating / updated / update failed / all up to date.

### 🌐 Mirror Enhancements (Brand New)

- The mirror page automatically fetches and adds available mirrors from the source's `mirrors` route (falling back to built-in backup domains when the primary domain fails); added "Speed test all".

### 💬 Comment Compatibility Enhancements

- Compatible with object-shaped comment lists keyed by id (e.g. Zai Comic); Unix seconds / milliseconds timestamps auto-formatted to absolute times.

### 🧩 Script Parser Enhancements

- Added `__fetchResponseType` (json / text) text prefetch; the `mirrors` route returning `[{name,domain,baseUrl}]` is passed through as-is, preserving the Source-as-Plugin principle.

### 🔧 Compilation and Engineering Fixes

- Fixed compilation errors including a missing `PointerScrollEvent` import, a `lerpDouble` call, and ReorderableListView parentheses; completed the l10n copy needed by new features.

---

### 📝 Changelog (v0.4.5 → v0.5.0)

This version is a **feature-increment release** over v0.4.5, with 5 commits relative to v0.4.5, introducing two brand-new capabilities and redoing settings and player settings.

### 📊 Reading Statistics Page (Brand New)

- **Reading-time tracking**: `ReadingSessionRecorder` records session duration in real time inside the video / comic / novel readers, automatically aggregating by day and by work.
- **Statistics page**: Settings → Statistics, with three tabs (Overview / By Day / List) + search + a summary card, showing cumulative reading time and most-recent activity per work.
- **Heatmap calendar**: A GitHub-style day grid, switchable by month, with null meaning "all", visualizing daily / monthly reading density.


### 🐞 Debug / Crash Logs (Brand New)

- Added the `crash_log` module and a "Crash Log" page (Settings → Advanced / About entry), centrally displaying runtime exception stacks for attaching accurate logs to Issues; also cleaned up dead code and standardized log output.

### 🎛️ Settings Page Refactor

- **Settings categorized**: Split out standalone "Advanced" / "Appearance" / "Category Management" pages, making the settings home structure clearer.
- **Reader global settings completed**: The novel / comic / danmaku modules' "Global Default Settings" pages connected and redundant controls cleaned up — novels gain "Simplified/traditional conversion / Body font family", comic / danmaku settings items unified; media-library and other user-visible copy polished; settings pages gain lively animations overall.

### 🎬 Player Settings Connected Globally + Per-work Overrides

- Player settings connected to a "global default + per-work (per-episode) override layer": seven items — decode / audio / aspect ratio / playback speed / continuous play / long-press toggle / long-press speed — can be overridden at the work level, falling back to global when unoverridden; danmaku display settings had redundant controls cleaned up.

### 🖼️ Strip-comic Reverse Page-turn Fix

- Fixed the reverse page-turn judgment when continuing to scroll up past the last page of a strip comic; combined with the previous version's landing-point fix, both upward and downward page turns are stable.

### 🔧 Backup / Auto-sync Fixes

- Fixed boundary issues with the auto-sync timer and backup archive, making backup / sync more reliable (the statistics box is now in the backup whitelist).

---

### 📝 Changelog (v0.4.4 → v0.4.5)

This version is an **urgent follow-up fix release** over v0.4.4, with 2 commits relative to v0.4.4, focused on experience fixes for the video player and the strip-comic reader.

### 🎬 Video Player Fixes

- **Landscape restoration on video exit**: Fixed the issue where exiting fullscreen playback left the screen orientation stuck in landscape instead of restoring the pre-entry orientation. The old logic only restored orientation "after going through fullscreen", while entering the playback page locks landscape by default (`lockOrientation: landscape`), causing the orientation to be locked after exit; now it **unconditionally restores orientation** when exiting the playback page (`SystemChrome.setPreferredOrientations([])`), with desktop / tablets unaffected.

### 🖼️ Strip-comic (Webtoon) Reader Fixes

- **Eliminated the sense of fragmentation**: After an image finishes loading, the placeholder constraint is removed and it is displayed at its true height, fundamentally fixing the "fragmentation / jumping" look at strip-image joins (`SourceImage` gains an `onLoadComplete` callback to support removing the placeholder).
- **Eliminated thin white bars**: Fixed gaps between images showing the light background and forming "thin white bars", so continuous strip scrolling no longer shows white.
- **Episode-selection UI shown on mobile**: The episode-selection `BottomSheet` height limit relaxed from 0.6 to 0.85 of screen height, the episode list changed to a compact layout, and routes changed to a horizontal Chip row — so on narrow screens (mobile) episode selection and routes display properly without crowding or truncation.

---

### 📝 Changelog (v0.4.3 → v0.4.4)

This version focuses on three blocks: **landing the UI design baseline** (sheet height-limit compliance, semantic status-color tokens, unified spacing / corner-radius convergence), **comic reader zoom-interaction fixes**, and **five feature fixes** (real-time novel catalog sync, locally imported comics, local file management, download path picker anti-freeze, RSS subscription optimization); it also restores platform project files mistakenly deleted in the previous version.

### 🎨 UI Design Baseline Landed

- **Sheet height-limit compliance (12 sites + 9 in the player)**: All `showModalBottomSheet` calls unified to `isScrollControlled: true` + an 85%-of-screen height limit + a scroll container — bookshelf long-press menus, chapter sorting / actions, favorite-method selection, article reading settings, reading-mode selection, image long-press menus, route selection, note lists, download-format selection, export-directory selection, etc. — so narrow screens no longer show truncated content.
- **Semantic status colors tokenized**: Added `AppStatusColors` (`ok` / `warn` / `fail` / `containerOf`), replacing 17 hardcoded colors; SnackBar passes `onInverseSurface` to adapt automatically to light / dark themes.
- **Spacing / corner radius converged**: Added `spaceXxs(2)` / `radiusXs(4)` tiers, mechanically replacing 92 magic numbers in 40 files with `AppTokens` (pixel-identical).
- **Eight UI optimizations**: Narrow-screen tabs hide icons leaving text only, source-management inner tabs scrollable; source list "Not logged in" badge; playback orientation defaults to landscape (desktop / tablets not force-rotated); 9 player sheets brought into compliance + danmaku-sending landscape/portrait adaptation + a media-info URL copy button + playback-stat labels allowed to wrap; fullscreen-exit residue fixed (`edgeToEdge` unified); novel theme follows three modes (follow app / always night / always day); **glaring loading-state fix** (the reader loading indicator sits on a plate of the current reading background color, no more white flash at night); **first batch of sheet-baseline compliance** (the player's long-press speed, more menu, screen cast, and sleep-timer sheets gained scrolling and height limits).

### 🖼️ Comic Reader Zoom Interaction (Targeted Fixes)

- **Double-tap three states**: Zoom out → zoom in → restore cycle, without entering settings.
- **Trackpad pinch**: Supports trackpad pinch gestures to zoom directly.
- **Drag-pan separated from wheel browsing while zoomed**: When zoomed, drag to pan and inspect details, while the wheel still turns pages, without interference.
- **Long-press and drag no longer conflict**: The gesture-recognition layer was fixed so a long-press menu does not falsely trigger zoom-drag.
- Added the `docs/UI_BASELINE.md` design-baseline document (fusion of Material 3 + Monet dynamic color, including narrow-screen responsive adaptation specs).

### 🔧 Five Feature Fixes

- **Real-time novel catalog sync**: The detail page and reader share a single catalog data source (`NovelTocStore`), synced in real time.
- **Locally imported comic reading**: An imported comic image directory is treated as one comic, read in filename order.
- **Local file management**: Locally imported files support **delete / rename** (both the import-history list and the bookshelf local section, via long-press / right-click).
- **Download path picker anti-freeze**: The download path setting persists and takes effect immediately; the directory picker runs in a background isolate, so **Windows no longer freezes or reports 0x80070057 / LateInitializationError**.
- **RSS subscription optimization**: Subscriptions are stored first and validated / completed in the background, eliminating lag when adding a subscription.

### 🛠️ Engineering Fixes (Important)

- **Restored mistakenly deleted platform project files**: Fixed the Windows build directory (`windows/`), web platform project (`web/`), tool scripts (`tools/`), danmaku rendering library (`third_party/canvas_danmaku`, vendored MIT), l10n artifacts, and test files accidentally deleted while tidying gitignore in the previous version — all four platform builds restored.
- **Windows player freeze fix**: `windows/runner/main.cpp` enables an independent UI-thread policy, fixing a frame freeze caused by window_manager fullscreen and the engine thread deadlocking (Flutter issue #176088).
- **Windows build UTF-8**: CMake adds the `/utf-8` compile option to avoid C4819 warnings for non-ASCII comments under the default code page.
- **Window-manager initialization moved earlier**: In `main()`, `windowManager.ensureInitialized()` moved before `runApp`, fixing frame freezes on entering / exiting the reader and failing F11 / Esc fullscreen.

### 🎨 App Icons Fully Updated

- All platform launcher icons replaced with the new `assets/icon/icon.png` (Android mipmap + adaptive icons, iOS / macOS AppIcon, Windows ICO, Web, Linux), preserving the adaptive-icon background color.

---

### 📝 Changelog (v0.4.2 → v0.4.3)

This version is a follow-up to v0.4.2, centered on a **systematic refactor of the comic reader**: page turning changed to "intent-driven", and seven rounds of continuous fixes applied to the **strip-comic (Webtoon) landing point when returning to the previous chapter**, fundamentally solving "stopping at the second-to-last page / fast-scroll rebound"; it also adds a persistent pinch-zoom and control-bar mis-touch protection.

### 📚 Comic Reader Refactor

- **Intent-driven page turning**: Page turning changed to "compute the target page first, switch chapters directly on out-of-bounds", fixing unresponsiveness when tapping the last page on narrow screens.
- **Boundary drag chapter switching**: Continuously dragging at a chapter boundary accumulates displacement and automatically switches to the next chapter (reset on release / re-scroll), solving the inability to turn to the next chapter from the last page.
- **Seven consecutive fixes for the previous-chapter landing point** (strip comics): placeholder height → stable criterion → anchor compensation → `jumpTo` alignment coefficient, fundamentally eliminating "stopping at the second-to-last page" and "fast-scroll rebound":
  - Fixed the placeholder height of unloaded images in `fitWidth` mode, correcting the landing-point offset when returning to the previous chapter;
  - Corrected two "reached the bottom" logics mistaking placeholder height for real height;
  - Switched to the criterion of "jump to bottom + `maxScrollExtent` stable" to land on the last page;
  - Finishing touch changed to verifying and re-anchoring the landing point, syncing the page number display during restoration;
  - Anchor + pixel compensation to land precisely on the last page;
  - Finally switched to `jumpTo` with a computed alignment coefficient to teleport to the last page, eliminating fast-scroll rebound.
- **Persistent pinch-zoom**: The zoom gesture is now always available — pinch with two fingers directly zooms in page-turn mode; single-finger pan only works while zoomed, otherwise it is handed back to the underlying scroll / page turn.
- **Control-bar mis-touch protection**: Added control-bar area protection to the tap hot zone, so tapping the top / bottom buttons does not trigger page turning.
- **Chapter boundary hints**: A text hint is given when already at the first / last chapter.

---

### 📝 Changelog (v0.4.1 → v0.4.2)

This version is an **urgent fix release** for v0.4.1, specifically fixing two page-turn experience problems in the **strip-comic (Webtoon) reader** exposed in v0.4.1.

### 📚 Strip-comic Reader Fixes

- **Current page locked to the last page when scrolling to the bottom of a strip comic**: Fixed the issue where on narrow screens, after scrolling to the bottom, the current page stayed at the second-to-last page and the progress bar was out of sync with chapter progress — when scrolled to the very bottom, the current page is now correctly locked to the last page.
- **Fallback to the next chapter when the last page cannot be turned**: When a strip comic on the last page continues to be turned upward and scrolling is clamped by the page so page turning fails, it automatically falls back to switching to the next chapter, avoiding "stuck on the last page and cannot turn".

---

### 📝 Changelog (v0.4.0 → v0.4.1)

This version is a follow-up to v0.4.0, focused on **fixing the build failure of v0.4.0 on overseas CI due to Gradle repository mirror order (all four platforms now build normally)**, and strengthening Bangumi sync, refactoring source management, completing the age-restriction system, and a batch of reading-experience fixes.

### 🌸 Bangumi Sync Enhancements

- **One-tap sync on detail pages**: Sync to Bangumi directly from an item's detail page, precise down to a specific episode / chapter.
- **Manual episode / chapter sync**: Supports manually triggering sync for a single episode or chapter, no longer full-only.
- **Per-route selection in the player + a Cleanup menu**: Episodes filtered by the current route; the player gains a "Cleanup" menu (clear watch records / progress, etc.); the sync dialog redone in the site's style, allowing multiple episodes / chapters to be checked for batch sync at once.
- **Select route → show all routes**: After selecting a route on the detail page, the player shows all routes for that source, making batch selection easier.
- **Incremental sync + conflict resolution**: Cloud sync changed to incremental transfer, with conflict detection and status details added (you can clearly see what synced and where conflicts occurred).
- **Unified backup archive**: Local import / export and cloud sync redesigned, with a unified backup-package structure and progressive restoration; the "Remember playback / reading position" toggle added.
- **Data safety correction (important)**: Fixed the cloud-sync / local-backup whitelist missing several storage boxes, avoiding data loss during backup and sync; also added live UI refresh after Bangumi logout, a friendly hint when the route panel has no routes, and help-document links.
- **Reading / progress / playback fixes**: Fixed several experience issues with reading progress, playback progress, and the sync dialog.

### 🧩 Source Management Refactor

- The source library gains **subscription / selective import**, no longer limited to manually pasting JSON; source JSON supports **full-field visual editing**; fixed login-state recognition and refresh for some sources on the source-management page.

### 🔞 Age-restriction System

- A refined age-restriction policy; **18+ sources are hidden by default** (can be manually enabled); added **network favorites** and **source announcements (announcement)** capabilities.
- **Source author responsibility**: Please fill in the `ageRating` field truthfully in your source JSON (`general` all ages / `teen` teen 16+ / `mature` adult 18+, with aliases such as `all`/`16`/`r18`/`nsfw` supported, defaulting to `general`). The app automatically rates and hides based only on this field; **ultimate content compliance and age-appropriateness are the responsibility of the source provider and the user**.

### 📚 Reading / Comic Experience

- Comic reader: Fixed page turning being out of sync with the progress bar.
- Fixed the dark-mode reading experience (background and preview); reader copy / preview adjusted; detail-page episode-selection / chapter-catalog dates follow the global date format; fixed collapsed-state title positioning; integrated Bangumi comment documentation.
- **6 experience-issue fixes** + committed changes left over from earlier rounds.

### 🔧 Other

- Fallback fix for the video-sniffing page loading forever in release builds.
- Added GitHub Issue templates (bug / feature / docs).
- Added missing files (content_detail_tabbed_shell, etc.) to keep remote master consistent with the working tree.
- Synchronized the source JSON field-spec documentation update to v0.4.0 (adding explanations for `network` / `comments` / `login` / `webFavorite` / `ageRating` and other fields).
- **CI build fix**: Android Gradle repositories changed to `google()` / `mavenCentral()` first with Aliyun as fallback, solving build failures where overseas runners could not fetch Google artifacts (e.g. flatbuffers-java).

---

### 📝 Changelog (v0.3.1 → v0.4.0)

> ⚠️ **This is a major version update**: relative to v0.3.1, **93 files changed and about 20,000 lines of code added**, introducing six blocks of new features at once and refactoring the detail page. **This version is expected to have a noticeably higher bug count than before**; please be sure to back up your data before upgrading; users seeking stability are advised to wait for a v0.4.x patch release.
>
> ✅ **Data compatibility**: No breaking changes. Old favorites / progress / bookmarks / history carry over directly; the new groups, ratings, and short reviews are all additive fields; **old source JSON needs no modification and no re-import**.
>
> ✅ **Signature preserved**: The same key as v0.3.0 / v0.3.1, so you can reinstall over the top.
>
> 🗳️ **Request for comments**: The design direction of Bangumi integration (sync direction / automatic reporting / binding strategy / privacy boundary / whether to extend to video) is open for community comment in [Discussions](https://github.com/nexhub-app/Nexhub/discussions); participation is welcome.

The theme of this version is "**from a standalone tool to a synchronizable, configurable, and social aggregation client**".

### 🌸 Bangumi Integration (Core)

- **Two login methods**: OAuth 2.0 authorization login (browser authorization → `nexhub://oauth/callback` deep-link callback, with refresh_token automatic renewal) and a manually entered personal Access Token (validated against `/v0/me` before saving); credentials stored in system secure storage.
- **OAuth app credentials injected at compile time** (`String.fromEnvironment`), with no credentials in source; CI already injects them, and when a self-built build has no injection the OAuth button shows "Not configured", so you can use an Access Token instead.
- **Synced content**: Favorite status (Want to Watch / Watching / Watched), anime watched episodes (incremental marking, only the difference set), comic / novel reading progress (ep_status), local ratings, and short reviews; options to push local group names as tags and to make new favorites private.
- **Conservative sync strategy**: Push-oriented, pulling back only ratings / short reviews "when locally empty"; status only advances, progress only increases, never overwriting remote "On Hold / Dropped".
- **Sync granularity**: Toggled per module (anime / comic / novel); supports full sync, single-item sync on the detail page, and "Import from Bangumi" (automatic binding by title similarity, without creating new local favorites).
- **Bangumi tab on the detail page**: Cover, rating and rating count, five-status favorite statistics, synopsis (expand / collapse), episode count and air dates, all tags, characters, related works, and remarks; with entries for "Open in browser / Manual binding / Sync-status override".
- **Item binding**: Local item ↔ Bangumi item mapping; cache first, then automatic title-similarity matching (≥0.85 adopted automatically), otherwise a candidate list for manual selection; can be unbound, and favorite status can be manually specified.
- **Proxy / mirror**: Direct / mirror modes, with the mirror mode allowing separate primary-site domain, API domain, and image domain, solving unreachable official domains and failed cover loading.

### 🌐 Network Configuration System (Global + Source-level)

- **Globally configurable**: Proxy (direct / system / manual, HTTP or SOCKS5, with account and password, the password stored separately encrypted), DNS (system / custom UDP / **DoH** / **DoT**, with resolution cache and built-in Cloudflare / Google / Quad9 presets), custom Hosts, SNI, and ECH.
- **Source-level overrides**: Enter a source's network override page from source management and choose per item, for "Proxy / DNS / SNI / ECH / Hosts", whether to inherit global or override individually. Priority: **user override > source JSON `network` block > global > default**.
- **App-wide effect**: `NexhubHttpOverrides` applies the configuration to all `dart:io` traffic in the app (including image loading and downloads); DNS resolution has a TTL cache and prefers custom Hosts hits; **changes take effect immediately, no restart needed**.
- **Built-in connectivity tests**: Proxy test, DNS test, DoH test.
- ⚠️ **Limitations**: SNI is best-effort only due to the Dart TLS stack; **the ECH UI is complete but not yet effective at runtime**.

### 🗂️ Favorite Groups and Local Ratings

- An item can belong to **multiple groups** (tag-style), independent of the site's genre classification.
- **Isolated by module**: Anime / comic / novel groups are independent and do not cross over.
- **Hideable**: A group can be marked hidden, so it does not appear in the group bar or filters, and can be restored in "Category Management".
- **Multi-select**: The group bar can select multiple groups at once for a union filter; the item group-assignment panel uses multi-select overlay assignment.
- The bookshelf's top group bar \[All\]\[Ungrouped\]\[Each group] auto-centers on tap; the management panel supports drag reordering, renaming, deletion (only unlinking), and creation.
- **Bookshelf filtering gains a "Group" dimension** (including an "Ungrouped" sentinel), stackable with sort / category / status / progress.
- **Local ratings and short reviews**: 0–10 scale + a short review, entered via the Bangumi panel on the detail page and long-press on a bookshelf card; can be pushed to Bangumi as a rate / comment.

### 💬 Comment Feature

- The detail page gains a "Comments" tab, split into two sub-pages: "Site Comments" (source site) and "Bangumi Remarks".
- **Bangumi remarks are read-only** (public API, no login needed).
- **Site comments are read-write**: List, load replies, post, reply, like, and report — each determined by routes declared in the source JSON, with buttons not rendered for undeclared actions.
- When a source does not declare `comments`, only the Bangumi-remarks sub-page is shown.

### 🔑 Source Login and Authentication

- **Web login**: An embedded WebView logs in to the site and automatically captures the session Cookie; **manually pasting a Cookie** serves as the desktop fallback.
- Login state is automatically detected and refreshed (re-evaluated on Cookie change), with the current login status shown at the top of the panel.
- Supports **logout**: `CookieStore` gains deletion by host, clearing only that site's session and not affecting other sources.

### 🧭 Detail-page Refactor (Three Modules Unified)

- **Deleted** `comic_detail_screen.dart` and `novel_detail_screen.dart`; comic / novel / video all go through `content_detail_screen` + `content_detail_tabbed_shell`.
- **Tabbed**: A Hero hero-image (scrolls to collapse and sticks to top) + a floating primary action (continue watching / reading, tappable on the first screen) + sticky tab bar "Detail / Bangumi / Episodes (chapter catalog) / Comments / Recommendations"; **episodes are reachable in a single tap** (the old version required opening a folded entry or a dialog).
- After the refactor, **not a single capability was lost**.

### 🎨 Other Experience

- **Unified batch-download episode dialog**: Shared by all three modules, with video automatically deduplicating by route to count the total, fixing a controller leak in the old implementation.
- **Skeleton screens**: Shimmer loading placeholders, with phase offsets supported to avoid whole-screen synchronized flickering.
- **Progress cards**: Added a completion-state highlight for fully read / watched, with numbers changed to a tweened rolling animation.
- Several narrow-screen layout fixes on detail pages and the bookshelf.

### 🧩 New Source JSON Fields (for Source Authors, All Optional)

| Field | Purpose |
| --- | --- |
| `network` | Source-level network override block: `proxy` / `dns` / `hosts` / `sni` / `ech`; inherits global when absent; invalid values only warn without blocking enablement |
| `comments.provider` | Defaults to `source`; `bangumi` is parse-only and not implemented this release |
| `comments.routes` | Only `list` is required; `replies` / `post` / `reply` / `like` / `report` are optional, and buttons are not rendered when undeclared |
| `comments.selectors` | `items` / `commentId` / `author` / `avatar` / `content` / `time` / `likeCount` / `replyCount` / `hasMore` / `success`, etc., using the same engine as top-level selectors |
| `comments.login.url` | WebView login page address |
| `comments.login.checkCookie` | A Cookie with this key name is treated as logged in |
| `comments.login.checkUrl` + `loggedInSelector` | Optional secondary probe to confirm the login is valid |

Comment routes support the `comments.` namespace, with placeholder replacement / mirror switching / relative-path completion consistent with the main routes.

### 🔧 Build and CI

- The CI four-platform (Android / Windows / Linux / macOS) build commands now include `--dart-define=BANGUMI_CLIENT_ID` and `BANGUMI_CLIENT_SECRET` (from repository Secrets), fixing unavailable OAuth login in official Release packages.

### 🧪 Tests

- Added 13 test files covering Bangumi binding / items / sync service, comment API and UI, DNS resolution, network configuration and client construction, valid network profiles, favorite groups and the group bar, source authentication management, and HttpFetcher profiles.

---

### 📝 Changelog (v0.3.0 → v0.3.1)

This version focuses on **video playback core and decoding robustness**, adding **Chinese traditional-color themes** and a **production-grade upgrade of signature management**; it also improves Android build / rendering stability on some device models and domestic networks, and fixes several parsing and danmaku-matching issues.

### 🎞️ Video Backend Simplification

- Removed the `fvp` video backend dependency, unifying on the single **media_kit + media_kit_libs_video (libmpv)** core path; cleaned up fvp registration and comments (splash / main / platform_service).

### 📊 New: Playback Statistics Panel

- Added the `PlayerStats` model, reading read-only mpv properties (actual decoder `hwdec-current`, codec, pixel format, resolution, render / decode dropped frames, bitrate, buffer progress).
- `VideoPlayerBackend` gains `getProperty`, and `MediaKitBackend` implements reading mpv properties.
- The player's "More" menu gains a "Playback Stats" item, showing the current decode method (soft / hard), codec, pixel format, resolution, dropped frames, bitrate, and cache buffering.

### 🛡️ Decode Abnormality Auto-degradation and Self-healing

- On hardware decode failure (garbled / artifacted screen), `PlayerController` automatically degrades to software decoding and broadcasts `decodeFallbackStream`; the playback page shows a notice and **re-opens the current address** so the new decode path truly takes effect (mpv's hwdec does not apply immediately to an already-playing decoder).
- Manually switching decode mode likewise re-opens to take effect; added a "Hardware Decode+" option with a hint "recommended when artifacts appear".


### 🔐 Production-grade Signature Management Upgrade (Security)

- The fixed signing key is no longer committed to the repo: `android/app/upload-keystore.jks` is now **injected via a CI Secret**, with the password stored in `android/key.properties` (not committed, with a `key.properties.example` template provided); `.gitignore` gains ignores for temporary key files.
- The key itself is completely identical to v0.3.0, so **reinstalling over the top from v0.3.0 still works** (no uninstall needed).

### 💬 Danmaku Matching Fix

- Fixed cross-title false matches: danmaku-library matching now requires `isMatched` or a similar title, removing blind-choice fallback to avoid matching unrelated danmaku libraries.

### 🔎 Parsing / Sniffing Fixes

- Fixed verification-wall interception on common book-source-type sites + Cookie persistence, improving novel-source stability.
- Fixed video-sniffing stability (including a fix for lost commits after the object store was corrupted and rebuilt).

### 🤖 Android Rendering Fix (Artifacted Screen)

- `AndroidManifest.xml` adds `io.flutter.embedding.android.EnableImpeller=false`, falling back to **Skia** rendering, fixing external-texture **flickering / artifacts** on some older GPUs / drivers (Mali, old Adreno) under the Impeller OpenGL backend (unrelated to decode method; also occurs with software decoding).

### 🔧 Android Build Reliability (Domestic Networks)

- `build.gradle.kts` / `settings.gradle.kts` add Aliyun maven mirrors (google / central) first with official sources as fallback, mitigating `dl.google.com` direct-connection stalls.
- `gradle.properties` adds Gradle HTTP connection / socket timeouts (60s) and a maximum retry count (3), avoiding infinite hangs on download timeouts.

### 🎨 Themes: 6 Chinese Traditional Color Presets

- `app_tokens.dart` adds seed colors for **Tea Red / Peach Bloom / Sky-Water Green / Vermilion / Ultramarine / Xuan Black** (with Chinese names, authoritative values consistent with zhongguose.com and Guo Hao's *Chinese Traditional Colors*).
- Fixed **Xuan Black rendering**: selecting it follows a dedicated "Ink Black + Vermilion" theme, fixing the "no effect" problem where a near-black seed color produced greyscale through `fromSeed`.
- Preset swatches **show the Chinese color name in a long-press Tooltip**.

### 🖥️ Interface

- Narrow-screen responsive layout optimization for detail pages.
- Fixed duplicate display of the "Layout" button on the online-browse page, unifying the layout entry.
- Fixed hint text on the video-sniffing page being squeezed into vertical columns.

### 🧪 Tests

- `test/player_screen_test.dart` gains about 138 lines covering playback stats and decode degradation / gesture-related logic.

---

### 📝 Changelog (v0.2.13 → v0.3.0)

This version is a larger upgrade of the player and danmaku experience, adding a video-sniffing engine and unifying the license to Apache-2.0. Relative to v0.2.13, 16 commits were merged, touching 40+ files.

### ⚖️ License and Compliance

- The repository license standardized to **Apache-2.0**, with a new `NOTICE` file and improved third-party attribution (canvas_danmaku MIT, Legado, Mihon, RSSHub, etc.).
- The acknowledgments section removed footnotes to GPL-3.0 repositories not actually drawn upon, to avoid license confusion.
- The About page (`about_screen`) gained third-party license / acknowledgment display and a NOTICE entry.

### 🔎 New: Video-sniffing Engine

- Added a standalone **video-sniffing engine** (`lib/core/sniffer/*`: sniffer_engine / sniffer_bridge / sniffer_models / sniffer_rules) + the rule file `assets/sniffer/sniffer_rules.json`.
- The sniffing page (`browse_sniffer_screen`, 626 lines) replaced the old `video_sniffer_screen`: it injects JS via WebView to capture in-page m3u8 / video direct links (including `URL.createObjectURL`) and passes them back to Dart through the bridge; rules automatically filter ads / thumbnails / beacons.
- Video parsing changed to **sniff-first**: sniffing results are preferred to locate the real playback address, and the "dragging the progress bar then reconnecting plays from the start" problem fixed.
- Sniffing results support copying to the clipboard / saving to the `NexHub/sniffer` directory, automatically carrying a Referer to avoid 403s.

### 💬 Danmaku System Refactor

- **Localized danmaku rendering engine**: Vendored the canvas_danmaku engine to `third_party/canvas_danmaku` (MIT license retained) to support custom rendering.
- **One's own sent danmaku changed to a white outlined capsule** (the original engine hardcoded green rectangles): patched to support rounded capsules + a white outline, distinguishing one's own danmaku from others'.
- Unified **player danmaku settings** and **global danmaku page settings** into a single data source, avoiding the two sets overwriting each other; with a double-safety apply.
- Danmaku settings persistence changed to **file-first**, so they survive exit and re-entry; fixed a loading-timing issue causing "not retained after exit and re-entry".
- Danmaku settings effectiveness fixed: font size / opacity / custom color actually take effect.
- The danmaku settings panel changed to an **in-page floating panel**, fixing an immediate crash on Windows.
- Added a **danmaku matching panel** (`danmaku_match_sheet`): manually / automatically match danmaku libraries (DandanPlay).
- Fixed crashes on consecutively opening videos, danmaku settings application timing, residual `onReady`, and uncaught async screen-brightness exceptions.

### 🎬 Player Gestures and Stability

- **Gesture system refactor** (`video_player_screen`, +992 lines):
  - Single tap: show / hide the control bar.
  - Double-tap zones: center = play/pause, left = rewind 10s, right = fast-forward 10s (ignored when locked).
  - Long press: switch to a custom speed, restoring on release (controlled by the `longPressSpeedUp` toggle, with the speed value selectable in the "More" menu).
  - Left vertical swipe brightness / right vertical swipe volume / horizontal swipe seek preview + a central gesture indicator overlay.
  - Keyboard: Space play/pause, left/right seek ±10s, F fullscreen, M mute.
- **Settings effectiveness foundation**: Global player default settings (decode / audio / aspect ratio / speed / volume / continuous play / orientation lock / seek multiplier / subtitle style) connected for loading and application, so settings-page fields truly take effect immediately.
- Fixed an **HLS native crash**: correctly releasing VideoController on exit and re-entry.
- Fixed a **video reconnect loop**: same-instance re-open self-healing + seek grace period relaxed to 60s.
- Fixed crashes on consecutively opening videos, danmaku settings application timing, uncaught async screen-brightness exceptions, and a compile error from delayed assignment of a `final` local variable `speed`.

---

### 📝 Changelog (v0.2.12 → v0.2.13)

This version focuses on parsing and playback stability of the video module, and also folds in v0.2.12's Android fixed signature:

### 🐛 Fixes / Stability (Video Module)

- **Parsing-layer refactor and stability**: Rewrote `http_fetcher` (more stable retries / encoding / timeouts) and fixed multiple parsing failures and video-extraction exceptions in `builtin_resolver` / `webview_resolver` / `video_extractor` / `media_api_service`; the path of feeding back post-render HTML from WebView for parsing is more robust.
- **Player exit crash fix**: On `deactivate`, the player cuts off `stall/position/completed` stream subscriptions and sets the `_disposed` flag, fixing the "accessing an ancestor of a deactivated widget" overflow crash; a fallback for losing context in a snackBar exit animation; fixed embedding `Positioned` adaptive video-area filling. The `webview_verification_screen` verification / extraction flow is more stable.
- **Total-episode count correction**: Changed to group by route (`Episode.lineName`) and take the largest group's episode count, avoiding accumulation across mirrored routes (e.g. 4 routes × 30 episodes miscounted as 120).
- **Precise episode parsing**: `fetchEpisodes` supports passing through `detailUrl`, parsing episodes precisely by the detail page address.

### ✨ Parsing Engine Enhancements (Source-as-Plugin Capability)

- **POST form routes**: `builtin_resolver` supports `routes.X.method:"post"`, automatically splitting query parameters into a form body, adapting to common video-collection CMS sites where "categories / lists are filled by frontend JS POST APIs" (e.g. `/ds_api/vod`); purely config-driven, with no hardcoded sites.
- **Weekly schedule (weekly updates) parsing**: Added a `week` route and weekly-list selector support, able to parse the airing weekday from `status` and display it grouped.
- **Category filters "all different"**: `SourceFilterConfig` gains `byCategory` (override filter groups by category id) and `defaults` (per-category defaults, e.g. 233 anime `sort=hits/year=2026`), all declared in source JSON with nothing hardcoded in Dart.
- **Broken-link fix**: A `video` route with `{url}` goes directly to an absolute address, avoiding it being prefixed with the base into a double-host broken link (`https://base/https://episode`) that breaks playback; relative addresses also get base normalization to avoid `//` double slashes.
- **Chinese search / filter fix**: `keyword` and filter placeholders containing Chinese are automatically `encodeComponent`-ed, fixing garbled Chinese keyword searches and empty results for Chinese filters (e.g. "Fantasy") on common video-collection CMS; for its `show` route, the `page` segment on page 1 is left empty, avoiding a wrongly assembled segment causing 404.
- **JsonPath null protection**: Non-string selectors gain a null fallback to avoid parsing crashes.

### 🎨 UI / Layout

- **Unified weekly-schedule layout**: Changed to the unified `ContentCard`, following the global layout (grid columns / list mode / corner radius / title / author), refreshed in real time by `ListenableBuilder`; all weekday chips are clickable (empty days show an empty state).
- **Global "Layout" button**: The browse-page AppBar gains a "Layout" button, so the home / weekly-schedule / category / ranking tabs can all change layout.
- **Detail-page cast collapsible**: The video detail-page cast block changed to collapsible (`_InfoChipsSection`), each group showing the first N by default with "Expand N / Collapse" for overflow, with the year always shown.
- Stability and layout fixes for the home page / content lists / source search / chapter lists (`online_content_list_screen` / `online_home_section` / `module_source_search_screen` / `chapter_list_section`).
- Added multi-language strings (l10n).

> This version already includes v0.2.12's fixed-signature keystore, so the Android package can be reinstalled over the top (older random-signed packages must be uninstalled once first).

---

### 📝 Changelog (v0.2.11 → v0.2.12)

This version fixes the problem where the Android package could **not be reinstalled over the top** because of "a random signature generated on each CI run":

### 🐛 Fix

- **Android could not be reinstalled over the top**: Previously release builds used the default debug signature, but CI uses a fresh virtual machine each time and `~/.android/debug.keystore` does not exist, so the build tool randomly generated a new keystore each time, making every APK's signing certificate different and preventing old packages from being overwritten. This version generates a fixed signature `android/app/upload-keystore.jks` (alias nexhub, PKCS12, RSA 2048, valid until 2053), commits it to the repo, and uses it for release builds in `build.gradle.kts`; it also adds `.gitattributes` marking `*.jks` as binary to prevent newline conversion during Git checkout from corrupting the keystore.
- ⚠️ **Installation note**: The random-signed old package already on your phone cannot be overwritten by a re-signed one, so you must **uninstall it once** before installing v0.2.12; after that, all versions can be upgraded by direct overwrite.

---

### 📝 Changelog (v0.2.10 → v0.2.11)

This version has **no application feature changes** relative to v0.2.10; it only adds an "Acknowledgments" note to the project:

### 🙏 Documentation

- **Added an Acknowledgments section**: Formally thanking [Legado](https://github.com/gedoor/legado) (and its variants), [Mihon](https://github.com/mihonapp/mihon) (a Tachiyomi derivative, and its variants), and [RSSHub](https://github.com/DIYgod/RSSHub) in the README and release notes.
  - Legado's "book source" rule system provided core inspiration for NexHub's Source-as-Plugin parsing and co-creation philosophy; NexHub's novel paginator borrows its `ChapterProvider` pagination algorithm in an independent Dart implementation (source code not copied); Legado's upstream carries no license, so this acknowledgment serves only as inspiration attribution.
  - Mihon (Apache-2.0, © Mihon contributors) — its extension sources and comic-reader interactions provided important references for NexHub's comic parsing and reading experience.
  - RSSHub (AGPL-3.0, © DIYgod) provides RSS aggregation for NexHub's subscription feature; NexHub only calls it as a client and has not modified or redistributed its source code.
- Only documentation and acknowledgments updated; no code / build-artifact changes involved; application functionality is identical to v0.2.10.

---

### 🎨 Changelog (v0.2.9 → v0.2.10)

This version **adds one user-visible platform capability**: the "Themed icon (themed icon / Monet color extraction)" on Android 13+ — the launcher icon **changes color to follow the wallpaper**.

### ✨ New

- **App icon Monet color extraction (Android 13+ themed icon)**: Previously `flutter_launcher_icons` only configured `adaptive_icon_background` and `adaptive_icon_foreground` and **lacked a single-layer monochrome layer**, so when Android 13+ tried to tint the icon to the wallpaper color on the home screen, the tint layer was missing and the icon stayed a fixed cyan background with a white "N". This version adds `assets/icon/icon_monochrome.png` (a white "N" + four white decorative corner dots on a transparent background) and wires up `adaptive_icon_monochrome` in the `flutter_launcher_icons` block of `pubspec.yaml`. The next time CI re-runs `flutter_launcher_icons`, the Android job will also produce the `ic_launcher_monochrome` resource, so the launcher icon will take color from the system wallpaper (the cyan background stays as brand color, while the "N" + dots follow the wallpaper color).
- Only affects Android 13+ devices that support themed icons; older devices, other Android versions, and Windows / macOS / Linux are completely unaffected (icon display behavior unchanged).

---

### 📝 Changelog (v0.2.0 → v0.2.9): Multi-platform Installers / Icons / Signature Fixes (No Application Feature Changes)

The v0.2.1 through v0.2.9 phase had **no application feature changes**, focusing on fixing packaging, icon, and signature issues for each platform's installer (recorded together here to avoid repetition):

- **Windows custom launcher icon**: `flutter_launcher_icons` regenerated icons, so both the installer and the extracted package carry the official NexHub icon (previously the Flutter default logo).
- **Windows exe installer**: Changed to installing Inno Setup via Chocolatey and then directly calling `ISCC.exe` to compile `windows/installer/NexHub.iss`, removing the failed third-party action dependency; and successively fixed the `SetupIconFile` path having one extra `..\..`, committing the official `ChineseSimplified.isl` language pack to the repo and using the correct path relative to the repo root, the `OutputDir` output directory being wrong (ISCC wrote to repo-root `Output/` instead of `windows/installer/Output/`), and the CI "copy fallback" copying an exe already in place onto itself, causing a `with itself` self-overwrite error (added an absolute-path comparison guard).
- **macOS / Linux app icons**: CI regenerates `AppIcon.appiconset` before build; Linux rebuilds the project with `flutter create --platforms=linux .` and then overwrites the icon; removed unrelated video-play placeholder images from the repo (bearing a "Image generated by AI" watermark).
- **Acknowledgments supplement**: During this phase, acknowledgments to Legado / Mihon / RSSHub were added to the README / release notes (see the note before v0.2.10).

---

### 📝 Changelog (v0.1.0 → v0.2.0)

This version merged 22 commits relative to v0.1.0, with the following highlights:

### 🐛 Key Fixes

- Fixed the global page-transition fade direction being reversed, causing the whole page to become invisible (black screen).
- Video core initialization failure no longer drags down the whole app (black-screen fallback: only video is unavailable, browsing / reading work as usual).
- Added a global error fallback: build-time exceptions show readable red text instead of a black screen, making root causes easier to locate.

### ✨ New Features / Experience

- Comic reader: Supports mouse drag / swipe page turning, mouse-wheel "action / direction" settings, strip-comic zoom and page turning.
- Cover-image Hero shared element: Smoothly flies from a list card into the detail page.
- DandanPlay danmaku changed to compile-time injection, and the credentials page removed (the key injected via CI Secrets).

### 💫 Lively Animations (Full Upgrade)

- Lively bottom-bar animation + theme-color capsule indicator.
- Unified lively animation primitives: press spring-back (AppTapScale), entrance (Entrance), and sheet / drawer spring-back (AppSheetBody).
- Global page-switch transitions finally changed to zero-animation instant switching, eliminating the frozen stutter on back navigation.
- List items / cards enter with lively motion; icon buttons and player controls spring back on press.
- The loading indicator upgraded to a three-dot bounce; pull-to-refresh is elastic; the top bar fades out on scroll.
- Content cards spring back on press + dialogs pop in elastically.
- Performance first: removed the only unnecessary infinite-loop animation (zero cost when idle).

---

## 📦 Installation

Download the installer for your system from the **Assets** below:

| System | File | Installation |
| --- | --- | --- |
| **Android** | `app-arm64-v8a-release.apk` (most phones) / `app-armeabi-v7a-release.apk` (older devices) / `app-x86_64-release.apk` (emulators) | Allow "Unknown Sources" on your phone, then tap the APK for the corresponding architecture to install. Installing the wrong architecture will report "Invalid package" |
| **Windows** | `NexHub-setup-x.y.z.exe` (recommended) / `NexHub-windows-x64.zip` | Double-click the exe and follow the wizard; or extract the zip and run `NexHub.exe` inside |
| **Linux** | `NexHub-linux-x64.tar.gz` | Extract and run `bundle/nexhub` |
| **macOS** | `NexHub-macos.zip` | Extract and drag `NexHub.app` into the "Applications" folder |

> ⚠️ The macOS package is **not notarized**, so the first launch may require clicking "Open Anyway" in "System Settings → Privacy & Security".

## 🔌 Important: Import a Source First

This app **does not bundle any sources**; it is empty on first launch, which is normal. Please import at least one source JSON first (in-app "Source Management / Import Source") to see content. Sources are shared and maintained by the community; obtain them through community channels and evaluate their compliance and content legality yourself.

> For complete usage and development guides, see the repository [README](https://github.com/nexhub-app/nexhub#readme).

## ⚠️ Disclaimer

NexHub is an open-source technical demonstration project that itself **does not provide, store, or relay any copyrighted content**, and **does not bundle any content sources**. All content comes from sources imported by the user, whose legality and copyright status are the responsibility of the source provider and the user. By using this software, you indicate that you have read, understood, and agreed to the full Disclaimer in the repository (drafted in accordance with the relevant laws and regulations of the People's Republic of China).

## 🙏 Acknowledgments

Thanks to [Legado](https://github.com/gedoor/legado) (and its variants) and [Mihon](https://github.com/mihonapp/mihon) (a Tachiyomi derivative, and its variants) — the former's "book source" rule system inspired NexHub's Source-as-Plugin parsing and co-creation philosophy, while the latter's extension sources and comic-reader interactions provided important references for comic parsing and the reading experience. Thanks also to [Legado with MD3](https://github.com/HapeLee/legado-with-MD3), whose book-source parsing rules informed NexHub's source parsing (GPL-3.0 © HapeLee; only the rule designs were borrowed, no source code was copied, and this acknowledgment serves solely as inspiration attribution). Thanks also to the [Flutter](https://flutter.dev) / Dart team, and to open-source projects such as [flutter_js](https://pub.dev/packages/flutter_js), [media_kit](https://pub.dev/packages/media_kit), and [canvas_danmaku](https://pub.dev/packages/canvas_danmaku), as well as all developers and source authors who have contributed to the "Source-as-Plugin · co-created community" philosophy.

## 📝 Known Limitations

- **iOS installers are not provided for now**: Signing requires an Apple developer account; run `flutter build ios` on your own machine to package it yourself.
- **The macOS package is not notarized**: Distribution across devices may be blocked by the system.
- **Android APK signing key (injected via CI Secret)**: The fixed signing key for release packages is **no longer committed to the repo**, and is instead **injected via a GitHub Actions Secret**, with `android/key.properties` storing only the password (not committed, with a `key.properties.example` template provided), meeting production-grade security requirements. The key itself is identical to v0.3.0, so **reinstalling over the top works from v0.3.0 onward**; if you are still on an older random-signed package, you must uninstall it once first. If you want to publish to an app store, use your own private official signing key.
- **Core features are complete**: Future versions will focus mainly on bug fixes and feature advancement; please report problems via Issues / the community.
- **ECH is not yet effective**: The ECH UI in network settings is ready but not yet wired up at runtime; **SNI is best-effort only** (due to the Dart TLS stack limitation).
- **Bangumi OAuth is unavailable in self-built builds**: App credentials are injected at compile time; when not injected, please log in with an Access Token instead, or register your own application at [bgm.tv/dev/app/create](https://bgm.tv/dev/app/create) (callback URL `nexhub://oauth/callback`).
- **Bangumi remarks are read-only**; the available operations for site comments depend on which routes are declared in the source JSON.
