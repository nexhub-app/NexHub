<div align="center">

  <img src="assets/icon/icon.png" width="128" alt="NexHub" />

# NexHub

All-in-one media aggregator (Anime / Manga / Novel / Video) — an open-source reading & watching tool based on the "Source-as-Plugin · Co-created Community" model

[![Flutter](https://img.shields.io/badge/Flutter-3.47.0-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.4.0%20%3C4.0.0-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![Release](https://img.shields.io/github/v/release/nexhub-app/NexHub?logo=github)](https://github.com/nexhub-app/NexHub/releases)
[![CI](https://github.com/nexhub-app/NexHub/actions/workflows/build.yml/badge.svg)](https://github.com/nexhub-app/NexHub/actions/workflows/build.yml)
[![Downloads](https://img.shields.io/github/downloads/nexhub-app/NexHub/total?logo=github)](https://github.com/nexhub-app/NexHub/releases)
[![Stars](https://img.shields.io/github/stars/nexhub-app/NexHub?style=flat&logo=github)](https://github.com/nexhub-app/NexHub/stargazers)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?logo=apache&logoColor=white)](LICENSE)
[![QQ Group](https://img.shields.io/badge/QQ%20Group-1132306726-1EBAFC?logo=tencentqq&logoColor=white)](https://qm.qq.com/q/KQ9T6Zh7EG)

<br/>

<img src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white" alt="Android" />
<img src="https://img.shields.io/badge/iOS-000000?logo=apple&logoColor=white" alt="iOS" />
<img src="https://img.shields.io/badge/Windows-0078D4?logo=windows&logoColor=white" alt="Windows" />
<img src="https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white" alt="macOS" />
<img src="https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black" alt="Linux" />
<img src="https://img.shields.io/badge/HarmonyOS-0A59F7?logoColor=white" alt="HarmonyOS / OpenHarmony" />

<br/>

**English** | [简体中文](./README.md)

</div>

> Latest release: **v3.3.0 (stable)**. The previous release is **v3.2.0** (stable — official HarmonyOS support, unsigned iOS build and built-in free translation). The project is under continuous development. Contributions and ideas are welcome via Pull Requests / issues. See [RELEASE_NOTES](./RELEASE_NOTES.md) for the full changelog.
>
> 📱 **HarmonyOS / OpenHarmony is officially supported**: fully usable on arm64 devices; an unsigned iOS build is also provided. See [Platform Support](#2-platform-support) below.
>
> 💬 **QQ dev group**: [1132306726](https://qm.qq.com/q/KQ9T6Zh7EG) (tap the number to join).

NexHub is a cross-platform media aggregator built with [Flutter](https://flutter.dev). It unifies four content types — **Anime, Manga, Novel, and Video** — into one app for browsing, searching, reading, and watching.

---

## 📚 Documentation

| Doc | Description |
| --- | --- |
| 📖 [Core Features](docs/features.en.md) | Source-as-Plugin, readers / player, Bangumi sync, network config, and other highlights |
| 🧭 [User Guide](docs/user-guide.en.md) | Install, import sources, daily usage, FAQ |
| 🛠️ [Developer Guide (incl. Source Authoring)](docs/developer-guide.en.md) | Environment setup, project structure, tiered source-authoring tutorial (Basic / Intermediate / Advanced), field reference, full examples |
| 📜 [Release Notes](RELEASE_NOTES.md) | Full changelog per version (Chinese) |

---

## 1. Introduction

**NexHub** is built around the **"Source-as-Plugin · Co-created Community"** philosophy:

- **The app only provides the "engine"** — generic capabilities such as UI, readers, player, networking, and parsing dispatch;
- **"Where content comes from" is decided by "sources."** Each source is an importable JSON config file (which may contain declarative selectors or embedded JavaScript scripts) describing how to scrape lists, details, chapters, and content from a specific site;
- **The app ships with no bundled or pre-packaged sources.** All sources are imported by users or shared within the community. Anyone can write a source JSON, import it, and parse that site's content — **without changing any application code**.

Benefits of this design:

1. **Legality & safety**: the public repository contains no "built-in sources" pointing to specific sites, reducing copyright and compliance risk;
2. **Sustainability & openness**: parsing capability is maintained by the community — when a site changes, only its source file needs updating, while the app itself stays stable.

> ⚠️ Because it ships with no sources, a freshly installed NexHub is "empty" — you need to import at least one source before seeing content. Think of it as buying a bookshelf: you still have to put books on it yourself.

---

## 2. Platform Support

### Platform status

| Platform | Status | How to get it |
| --- | --- | --- |
| Android | ✅ Fully supported | APK from the Releases page |
| Windows | ✅ Fully supported | zip / installer from the Releases page |
| Linux | ✅ Fully supported | tar.gz / deb / AppImage from the Releases page |
| macOS | ✅ Fully supported | zip / dmg from the Releases page |
| iOS | ✅ Supported (unsigned IPA) | IPA from the Releases page (self-sign & sideload) |
| **HarmonyOS / OpenHarmony (arm64 device)** | ✅ Fully supported | Unsigned HAP from the Releases page (sign it yourself and sideload) |

### 📱 HarmonyOS notes

The HarmonyOS (HarmonyOS / OpenHarmony, arm64 device) build is officially supported. Just like the Android / desktop builds, it is a **full "Source-as-Plugin" client**.

**Available on HarmonyOS**:

- Full source parsing & reading chain (including JS-scripted sources, native QuickJS bridge);
- Video playback (libmpv engine, same lineage as Android: playback speed / audio tracks / subtitles / anti-leech headers) with on-screen danmaku;
- Picture-in-picture (system floating window with control panel), system notifications, saving images into the system gallery (system confirmation dialog, permission-free), clipboard image paste;
- Offline TTS reading for novels (system CoreSpeechKit engine with speech rate / sleep timer / background playback) and self-hosted online HTTP TTS;
- Volume-key page turning in the reader (native key channel, long-press to repeat);
- Screen casting (native mDNS discovery), Material You dynamic color (live wallpaper-seed following), ECH acceleration (engine bundled in the HAP);
- Local persistence for favorites / download tasks / history (standalone file storage — survives force-kill);
- Bangumi login & sync (authorization completed in an in-app WebView);
- In-app updates (opens the browser on the Releases page for the new HAP).

**Installation (sideload)**: download `NexHub-ohos-arm64-unsigned.hap` from the Releases page → sign it yourself with an on-device signing tool and install (or install via DevEco Studio / hdc). Release artifacts are consistently unsigned; signing is left to the user.

### HarmonyOS: remaining platform differences

| Feature | Status on HarmonyOS | Workaround / notes |
| --- | --- | --- |
| Local folder import | Directory picking unavailable | Use "import files" to pick files one by one |
| Custom download directory / custom screenshot directory | System Downloads folder supported | Phones cannot pick arbitrary folders; choose between the app-private folder and system Downloads (`Download/<bundleName>`, visible in Files) |
| Plugin export / backup export | No directory picker | Saved through the system "Save as" / share sheet |
| Podcast background notification | Unavailable | In-app playback unaffected |
| Emulator (x64) | Video playback and ECH unsupported | Playback and ECH engines ship arm64-only artifacts; x64 debug builds bundle QuickJS / WebView native libs |

> These differences keep converging as system capabilities and upstream ports progress; fixes are noted in future release notes.

---

## 🗺️ Roadmap (TODO · planned · community input welcome)

The following features are **not yet implemented** and are priorities for upcoming versions. Design trade-offs are welcome in GitHub Discussions / Issues:

1. **More sync backends**: in addition to Bangumi sync, integrate AniList, MyAnimeList, Trakt, SIMKL, MDList, etc., with cross-backend two-way sync and configurable conflict strategies;
2. **AI source search / natural-language retrieval**: deeper AI assistance such as searching sources by natural language, anime/book companions, etc.

> Shipped: Manga page translation (MTL) and real-time video subtitle translation landed in **v2.0.0-beta.3**; novel translation (AI bilingual / paragraph) and AI assistance (content summary / chapter illustration) landed in **v2.0.0-beta.2**. The items above are not part of this release; their order and form will adapt to community feedback.

---

## 3. Source-as-Plugin · Co-created Community

NexHub's vitality comes from community-maintained "sources." Everyone is welcome to participate:

- **Users**: import community-shared sources and organize content as you like;
- **Creators**: write your own source JSON describing how to parse a site, and share it with others;
- **Contributors**: improve the engine, readers, player, or docs, or file Issues / PRs.

> The app only provides the engine; parsing capability comes from the community. When a site changes, only its source file needs updating, while the app itself stays stable — that is the value of "Source-as-Plugin · Co-created Community."

---

## 4. Disclaimer

> This disclaimer is drafted in accordance with the laws and regulations of the People's Republic of China (including, without limitation, the Cybersecurity Law, the Copyright Law, the Regulations on the Protection of the Right of Communication through Information Networks, and the Protection of Minors Law) and general international practice. By using this software you acknowledge that you have read, understood, and agreed to all of the following.

1. **Technical demonstration nature**: NexHub is an open-source "aggregator / reading tool" technical demonstration project. It itself **does not provide, store, or relay any copyright-protected content**, and **ships with no built-in content sources** pointing to specific sites.

2. **"Sources" are the user's responsibility**: all content in this software comes from **sources imported by users themselves**. The content on the sites a source points to, its legality, accuracy, and completeness, as well as the compliance and copyright status of the source itself, are **entirely the responsibility of the source provider and the user**, and are unrelated to the authors and contributors of this software.

3. **Comply with laws and regulations**: users must strictly comply with applicable local laws and regulations, including but not limited to cybersecurity, copyright, and information-network-transmission protections. You may use this software only for **personal study, technical research, and non-commercial purposes**. You must not use it to infringe others' copyrights, privacy, trade secrets, or other lawful rights, nor for any commercial or illegal distribution.

4. **Copyright and infringement handling**: if a source you import involves copyright-protected content, use it only within the scope authorized by the rights holder; if a rights holder believes a source or content infringes their lawful rights, please contact the source provider to remove it, and the authors of this software will cooperate as necessary.

5. **Provided "AS IS"**: this software is provided on an "AS IS" basis, without any express or implied warranty (including but not limited to fitness, reliability, virus-free, and error-free warranties). The authors and contributors **assume no liability** for any direct, indirect, incidental, special, or consequential damages arising from the use or inability to use this software.

6. **Protection of minors**: if the user is a minor, please use this software under the guidance of a guardian and comply with the Protection of Minors Law and other applicable regulations, avoiding exposure to inappropriate content.

7. **Age rating and content classification**: NexHub has a built-in **age rating (ageRating) system** — source authors should truthfully declare `ageRating` in the source JSON (`general` / `teen` (16+) / `mature` (18+)). **`mature` (18+) sources are automatically hidden by default**; users must actively enable restricted content in Settings before it appears. The app only **filters display** according to the rating rules and does **not review, endorse, or guarantee any source's actual content**; whether a site permits its content to be accessed, scraped, and distributed is for the source author and user to determine and bear responsibility for. Do not import or distribute sources or content that violate local laws or infringe the rights of others.

8. **Territorial compliance**: if the laws of your country or region prohibit or restrict the use of this software, stop using it immediately. The legality of this software in different jurisdictions is for the user to determine and bear.

9. **Account and privacy**: data generated while using this software (browsing history, imported sources, etc.) is **stored locally on your device by default**; if you enable any cloud sync or third-party service, please understand and accept that service's privacy policy and data processing practices. The public code in this repository **contains no personal privacy, keys, or credentials**.

10. **Scope of disclaimer**: this disclaimer constitutes the complete understanding between you and the authors/contributors of this software regarding its use. If any provision is held invalid, the remaining provisions remain in effect.

---

## 5. Acknowledgments

NexHub would not exist without the following projects and communities:

- [Legado](https://github.com/gedoor/legado) (and its various forks): the "book source" rule system provided core inspiration for NexHub's "Source-as-Plugin" parsing and co-creation philosophy (especially the declarative / scripted approach for novel sources). NexHub's novel paginator independently implements a pagination algorithm inspired by Legado's `ChapterProvider` without copying its source code; the upstream Legado repository does not carry an explicit open-source license, so this acknowledgment is for inspiration only and implies no license grant.
- [Mihon](https://github.com/mihonapp/mihon) (a Tachiyomi derivative, and its various forks): the extension-source architecture and manga-reader interactions provided important references for NexHub's manga parsing and reading experience. Mihon is released under the Apache License 2.0 (© Mihon contributors).
- [RSSHub](https://github.com/DIYgod/RSSHub): its RSS aggregation capability provides the service foundation for NexHub's subscription feature. RSSHub is released under AGPL-3.0 (© DIYgod); NexHub only calls its instances as a client and does not modify or redistribute its source.
- [wenyi](https://github.com/BigDawnGhost/wenyi): its novel AI-translation pipeline design (context enrichment, terminology loop, evidence-driven review and refined drafting) informed the deep optimization of NexHub's built-in novel translation. wenyi is released under the MIT License (© BigDawnGhost); NexHub copied no source code and implemented independently from its design ideas.
- **Flutter HarmonyOS community (Flutter SIG / OpenHarmony adaptation project)**: for bringing HarmonyOS platform support to the Flutter ecosystem — the NexHub HarmonyOS build is based on the community-maintained Flutter OHOS SDK and adapted third-party packages;
- [Flutter](https://flutter.dev) and the Dart team, for the excellent cross-platform framework;
- [flutter_js](https://pub.dev/packages/flutter_js) (QuickJS engine), for the safe JS sandbox for embedded source scripts;
- [xpath_selector](https://pub.dev/packages/xpath_selector) and [html](https://pub.dev/packages/html), for declarative extraction;
- [dio](https://pub.dev/packages/dio), for unified networking and cookie management;
- [provider](https://pub.dev/packages/provider), for state management;
- [dynamic_color](https://pub.dev/packages/dynamic_color), for Material You dynamic color;
- [media_kit](https://pub.dev/packages/media_kit) (libmpv engine), for video playback;
- [Bangumi](https://bgm.tv) for its open API, which makes NexHub's collection / progress / rating sync and entry details possible (NexHub only calls its public endpoints as a third-party client);
- [canvas_danmaku](https://pub.dev/packages/canvas_danmaku), for danmaku (bullet-comment) rendering;
- [cat-catch](https://github.com/xifangczy/cat-catch) and other open-source sniffer projects (cat-catch / VBrowser-Android / VidDown / pup-sniffer): their "network interception + DOM detection + API hooking" methodology provided an important reference for NexHub's built-in video sniffer (methodology only; no code introduced; the app is open-sourced under Apache-2.0);
- All developers, source authors, and users who have contributed to the "Source-as-Plugin · Co-created Community" philosophy.

---

## 6. Open-source License

This project is open-sourced under the **Apache License 2.0 (Apache-2.0)** — see the [LICENSE](LICENSE) file and the [NOTICE](NOTICE) third-party attribution file in the repository root.

Apache-2.0 allows free use, copying, modification, and distribution of this software in any project (including closed-source or commercial products), provided that: copyright and license notices are retained, changes to modified files are marked, and if the upstream contains a NOTICE file, its attribution content must be included. **This software is provided "as is", without any warranty.** If this project contains derivative content from third-party components, see [NOTICE](NOTICE) for attribution and licenses.

---

<p align="center">NexHub · Source-as-Plugin · Co-created Community</p>
