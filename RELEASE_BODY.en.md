# NexHub v4.0.0-beta.4 (pre-release)

> All-in-one media aggregator (anime / manga / novels / video) — Source-as-Plugin · co-created community.

---

## 🩹 The fourth 4.0 test build

beta.4 is a focused cleanup: it **fixes the HarmonyOS build that could not get past launch**, and gives the book-source engine's concurrency, rate-limiting and network semantics another pass. 6 commits since v4.0.0-beta.3.

> - **Still built from the `feature/legado-booksource-compat` branch**, not merged into main; version v4.0.0-beta.4.
> - **Compatibility**: existing sources, bookshelves / favorites / reading progress are unaffected; the book-source work here is semantic alignment plus tolerance, so old sources need no edits.
> - **Beta reminder**: when something breaks, use Settings → Advanced → Runtime Log → Export log file and send it over — that makes diagnosis much faster.

> ⚠️ **This app ships with no content sources.** It is empty on first launch. Import at least one source JSON before you can see anything. Sources are shared by the community; assess their compliance and legality yourself.

---

## ✨ What's new

### 📱 The HarmonyOS build launches again

- **Fixed "install, open, stuck"**: the preparation script that adds HarmonyOS-only dependencies during the build had a faulty check, so the secure-storage dependency was never actually written into the manifest. The resulting package lacked that plugin's native registration; the app reads a credential at startup, fails, and stays on the splash screen — which looks exactly like "it won't open".
- The check now matches actual dependency lines, so both HarmonyOS-only dependencies land in the manifest, and the build log confirms the plugin is registered.
- If you installed the beta.3 HarmonyOS package and it would not start, just overwrite-install this build.

### 🚦 Concurrency and rate limiting behave properly

- **Queued requests no longer all pass at once**: after a rate-limit window expires the request is re-evaluated, so waiters are not released in one burst and real concurrency stays within the value configured on the source — less chance of being throttled or blocked by a site.
- **Explore-page category scripts run once**: concurrent calls for the same source reuse the in-flight result, so repeated taps or fast switching no longer re-run the category script; an explicit refresh waits for the pending call before refetching, instead of being overwritten by stale results.

### 📄 Content paging and batch requests: leaner and steadier

- **The next-page URL is evaluated in the current page's context**, so variables no longer leak across pages; batch page fetching stops dispatching after the first failure instead of burning through the remaining pages and re-hitting the site.
- **Batch request semantics tightened**: any failed item fails the whole batch, no more treating a partial success as complete; a batch speed-test API times each item and reports a unified failure code when testing sources.
- **In-page scripts retry on a fixed cadence** (up to 30 times / 30 seconds) when they yield nothing, then fall back to the HTML already fetched instead of waiting indefinitely.
- **Word counts are accurate**: rounded with HALF_EVEN at single precision, so `.x5` boundaries no longer display wrong.
- **jsoup connection options actually apply**: timeout, follow-redirects, max body size and ignore-HTTP-errors are honoured; replacement templates expand like a Java Matcher, with out-of-range groups and malformed patterns falling back to the literal instead of aborting.

### 🧩 Rules and archives: another compatibility pass

- Trailing cuts in rules, possessive quantifiers, XML parsing, JSONPath lookups, auto keys, multi-format archives, TOC refill and temporary source variables are aligned with baseline behaviour, so encrypted and compressed sources are less likely to "search fine but fail to open the content".
- The explore-page option bar now shares one live dataset between display name and action; script writes flow back and persist through the existing pipeline.

### 🧪 Tests & known limits

- `dart analyze lib` reports 0 errors; book-source test results match the pre-change baseline item by item, with no new regressions.
- A small set of Java APIs and charsets still degrade gracefully (unknown charsets fall back to UTF-8); `unrar` / `un7z` still only handle the zip path; WebView paths need more on-device verification.

---

## ⬆️ Install & upgrade

- This is a branch beta; Android / Windows / Linux / macOS / iOS / HarmonyOS artifacts ship in the same pre-release.
- The same signing key applies, so overwrite-install works. The HarmonyOS HAP remains unsigned and must be signed before sideloading.

## 📄 Disclaimer

- NexHub ships no content sources. Everything comes from sources you import yourself; verify each source's legality and safety before use. You bear the risk of using them.
