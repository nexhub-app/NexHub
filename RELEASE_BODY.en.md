# NexHub v4.0.0-beta.3 (pre-release)

> All-in-one media aggregator (anime / manga / novels / video) — Source-as-Plugin · co-created community.

---

## 🧪 The third 4.0 test build

beta.3 keeps lining the book-source engine up with its reference semantics and fixes a batch of everyday blockers: **favorites vanishing after a restart**, **downloaded content without covers**, **inaccurate TOC positioning**, and **logs you could not export**. It also adds **paragraph comments**. 42 commits since v4.0.0-beta.2.

> - **Still built from the `feature/legado-booksource-compat` branch**, not merged into main; version v4.0.0-beta.3.
> - **Compatibility**: existing sources, bookshelves / favorites / reading progress are unaffected; the book-source work here is semantic alignment plus tolerance, so old sources need no edits.
> - **Beta reminder**: when something breaks, use Settings → Advanced → Runtime Log → Export log file and send it over — that makes diagnosis much faster.

> ⚠️ **This app ships with no content sources.** It is empty on first launch. Import at least one source JSON before you can see anything. Sources are shared by the community; assess their compliance and legality yourself.

---

## ✨ What's new

### 💬 Paragraph comments and inline icons (new)

- **Paragraph comment panel**: book-source content supports per-paragraph comments — view, load and page through them in a panel; inline icons render where the rules place them and open the matching discussion.
- Comment evaluation goes through the source rule chain; site logic stays in the source file and nothing is hardcoded in the engine.

### ⭐ Favorites no longer disappear

- **Fixed "all favorites gone after a restart"**: a failed file read used to be treated as "no data", and the next ordinary favorite update wrote that empty list back to disk, losing favorites for good. Now a failed read falls back to the backup file; if the backup also fails the app reports it and **refuses to write**, so a good file is never overwritten by an empty list.
- Writes now back up before overwriting and verify length afterwards; failures surface a "favorite save failed" message and show the reason in the runtime log.
- History loading got the same startup guard: a failed read no longer leaves the app stuck while launching.

### 📥 Downloaded content has covers again

- **Cover saving now uses the per-source network profile**: saving used the global profile, so per-source proxy / encrypted channel / hosts never applied and covers were rejected by the CDN while the content itself downloaded fine. It now matches chapter images and reads the source profile.
- **Protocol-relative URLs**: `//cdn/xxx.jpg` is normalised to https instead of being treated as a local file and showing a placeholder.
- **Bad cache is no longer reused forever**: zero-byte cover leftovers (interrupted writes) count as empty and are deleted before re-downloading; cache keys now use filesystem-safe characters, so saving no longer fails on Windows.

### 📑 More accurate TOC positioning

- The comic / novel reader's TOC jump no longer estimates scroll distance from a fixed row height; it positions the current chapter by item index, so long TOCs and sectioned TOCs land correctly.
- "Locate current chapter" jumps precisely; if search or bookmark filters hide the current chapter, filters are cleared first; the list rebuilds safely on filter changes instead of resting on an out-of-range index.

### 🧾 Exportable runtime logs

- The runtime log page no longer copies just one line; both log pages (crash / runtime) gained "Export log file", with an environment header (app version, platform, export time). HarmonyOS uses system save-as, other platforms use the share sheet.

### 🧩 Book-source compatibility: semantic alignment, item by item

- **Rule evaluation**: fixed argument evaluation order and result backfill order for upward rules; concatenation rules keep text order while matching side-effect order; boundary semantics for `@put`, `@js:`, inline rules and selector groups are tightened.
- **Variables**: deletion (put null), whole-block replacement, cross-round persistence and write-back timing are aligned across source / book / chapter levels; large variables are routed by threshold so synchronous file writes no longer block the UI.
- **TOC and paging**: an empty first TOC page still evaluates the next-page URL; the TOC page ceiling was raised with a warning when hit; variable propagation across multi-page lists and details works, and failures now fail instead of returning silent empty results.
- **Network and encoding**: a Java charset alias table (GBK / GB18030 / Big5 …) with explicit errors for unknown charsets; PUT / DELETE / PATCH plus binary request bodies; cache keys include the body and more options; rate limiting uses fixed windows and keeps window progress when the rate changes at runtime.
- **jsoup compatibility**: the `Elements` / `Element` collection and traversal surface, `abs:` resolved against the document base URI, sibling collections excluding the element itself.
- **WebView and login**: POST prefetch before handing off to WebView, `loginCheck` replacing the whole response (including url / headers) and advancing per round, and source headers with `@js:` evaluated by the host.
- **Stability fix**: fixed a duplicate definition in the preset script that aborted it, which had made `java.ajax` and the global objects unavailable; book-source tests recovered from 719 to 844 passing.

### 🧪 Tests & known limits

- The full book-source suite passes 857 / fails 23, the same failures as before the change (all pre-existing); new tests cover paragraph comments, binary cache and variable deletion.
- `dart analyze lib` reports 0 errors.
- A small set of Java APIs and charsets still degrade gracefully (unknown charsets fall back to UTF-8); `unrar` / `un7z` still only handle the zip path; WebView paths need more on-device verification.

---

## ⬆️ Install & upgrade

- This is a branch beta; Android / Windows / Linux / macOS / iOS / HarmonyOS artifacts ship in the same pre-release.
- The same signing key applies, so overwrite-install works. The HarmonyOS HAP remains unsigned and must be signed before sideloading.

## 📄 Disclaimer

- NexHub ships no content sources. Everything comes from sources you import yourself; verify each source's legality and safety before use. You bear the risk of using them.
