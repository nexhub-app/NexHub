# NexHub v4.0.0-beta.2 (pre-release)

> All-in-one media aggregator (anime / manga / novels / video) — Source-as-Plugin · co-created community.

---

## 🧪 The second 4.0 test build

beta.2 keeps filling in the book-source compatibility layer and adds two new experiences: a **three-page audio player** and **adaptive live-stream playback**. 46 commits since v4.0.0-beta.1.

> - **Still built from the `feature/legado-booksource-compat` branch**, not merged into main; version v4.0.0-beta.2.
> - **Compatibility**: existing sources, bookshelves / favorites / reading progress are unaffected; source types are detected automatically, no manual edits needed.
> - **Beta reminder**: the new capabilities cover a lot of ground; a few unconventional sources may still fail. Please attach the in-app "runtime log" when reporting.

> ⚠️ **This app ships with no content sources.** It is empty on first launch. Import at least one source JSON before you can see anything. Sources are shared by the community; assess their compliance and legality yourself.

---

## ✨ What's new

### 🎵 Audio playback (new)

- **Three-page audio UI**: cover page + chapter list + lyrics, swipe left/right to switch. The bottom bar stays only on the cover page and fades out while browsing lists or lyrics, so it never blocks gestures.
- **Single-row spatial control bar**: previous / sleep timer / play / next / speed on one row, both side groups equal-width, play button strictly centred, button sizes shrinking outward from the centre.
- **Spatial scaling**: list rows and lyrics scale by distance from the viewport centre, with the current episode / line slightly boosted. Scrolling is never hijacked while you drag; about 3 seconds after you stop, the current item re-centres — and the first/last items can centre too.
- **Cover-based colouring**: play button and background share three schemes — cover colour / app theme / solid colour.
- **Speed sheet**: the selected row is emphasised with the primary colour instead of a check mark that squeezed the text.
- Embedded lyrics from audio book sources are read and shown in the player.

### 📺 Adaptive live streams

- **Automatic detection**: after opening, a duration stuck at 0 while the position advances (verdict in ~3s), or an rtsp / rtmp style URL, is treated as live — no manual toggle.
- **Low-latency profile**: live playback uses dedicated cache parameters (4s buffer, 1s hysteresis, 16MiB, forced seekable disabled), and the VOD path no longer interferes (skips resume seek, reconnects no longer jump to stale timestamps).
- **Self-healing**: a 30s continuous-buffering watchdog plus low-level error subscription; the reconnect budget resets after 90s of stable playback; stream end reconnects instead of clearing progress and chaining episodes.
- **Control bar**: live mode replaces the progress bar and duration with a red-dot LIVE badge; keyboard left/right is guarded so a stray seek cannot kill the stream.

### 📚 Book-source compatibility, continued

- **File sources**: download links and local import are supported; the detail page lists source files (tap an undownloaded file to fetch it, tap a downloaded one to open), and the progress card reads local progress plus browsing history.
- **Crypto & evaluation**: RSA asymmetric crypto now exports via the host with OAEP / strict semantics; AES-GCM added; random sources seed from content so replay converges; replay placeholders are no longer cached and hex decoding is strict.
- **Rule details**: dual semantics for `java` objects and body-title rules now reach the reader; comic image headers aligned with a replay wait ceiling; `data:` chapter URLs and `type` option byte hex supported; fixed JS composite list rules, array pagination and TOC / discovery evaluation.
- **Discovery**: a pure-JS `org.jsoup.Jsoup.parse` with a minimal DOM / CSS selector set lets scripts that call jsoup parse directly; discovery script failures surface as visible error states, and category lists cache per source with forced refresh.
- **Sessions & auth**: on HTTP 412 the session cookie is fetched from the site root and the request retried; explicit Cookie values take precedence when merging; chapter purchase (`payAction`), `callBackJs` event callbacks and event bits are supported; scripted headers and the login Cookie overlay are evaluated during image fetching.
- **HarmonyOS**: book-source WebView interaction and fetching are enabled on HarmonyOS; fixed a bridge error message that lacked location and silently disabled jsLib compatibility rewriting.

### 🗂 Source management & import

- **Search**: both the source library and the online source list gained a search box that scrolls with the list instead of sticking to the top.
- **Steadier imports**: file-type sources are allowed, network import no longer hangs in a loading state, and the multi-source list no longer crashes; bulk imports are inserted in one batch and parsed in the background, reducing stalls and crashes.
- **Simplified entry**: the "enable recommended sources" shortcut is removed; per-source toggles remain.
- **Onboarding disclaimer**: a disclaimer page (5 key points + a required agreement checkbox before "Get started") was added to the end of onboarding.

### 🙏 Credits & docs

- Added a **Legado with MD3** credit (README in both languages, in-app credits page, release notes) stating that only rule ideas were consulted and no source code was copied.
- The release pipeline now produces a **bilingual Release body**: Chinese first, English after, in the same Release.

### 🧪 Tests & known limits

- The book-source compatibility suite and new unit tests (live profile, bridge / context / regex compatibility, etc.) pass; `dart analyze lib` reports no errors.
- A small set of Java APIs is still uncovered; unsupported forms degrade explicitly.
- WebView paths (headless fetching, `webJs`, login forms) still need more on-device verification — please report how they behave on HarmonyOS too.

---

## ⬆️ Install & upgrade

- This is a branch beta; Android / Windows / Linux / macOS / iOS / HarmonyOS artifacts ship in the same pre-release.
- The same signing key applies, so overwrite-install works. The HarmonyOS HAP remains unsigned and must be signed before sideloading.

## 📄 Disclaimer

- NexHub ships no content sources. Everything comes from sources you import yourself; verify each source's legality and safety before use. You bear the risk of using them.
