<div align="center">

  <img src="assets/icon/icon.png" width="128" alt="NexHub" />

# NexHub

四合一媒体聚合客户端（动漫 / 漫画 / 小说 / 影视）—— 源即插件 · 共创社区模式的开源阅读 / 观看工具

[![Flutter](https://img.shields.io/badge/Flutter-3.47.0-02569B?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.4.0%20%3C4.0.0-0175C2?logo=dart&logoColor=white)](https://dart.dev/)
[![Release](https://img.shields.io/github/v/release/nexhub-app/NexHub?logo=github)](https://github.com/nexhub-app/NexHub/releases)
[![CI](https://github.com/nexhub-app/NexHub/actions/workflows/build.yml/badge.svg)](https://github.com/nexhub-app/NexHub/actions/workflows/build.yml)
[![Downloads](https://img.shields.io/github/downloads/nexhub-app/NexHub/total?logo=github)](https://github.com/nexhub-app/NexHub/releases)
[![Stars](https://img.shields.io/github/stars/nexhub-app/NexHub?style=flat&logo=github)](https://github.com/nexhub-app/NexHub/stargazers)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg?logo=apache&logoColor=white)](LICENSE)
[![QQ 群](https://img.shields.io/badge/QQ%E7%BE%A4-1132306726-1EBAFC?logo=tencentqq&logoColor=white)](https://qm.qq.com/q/KQ9T6Zh7EG)

<br/>

<img src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white" alt="Android" />
<img src="https://img.shields.io/badge/iOS-000000?logo=apple&logoColor=white" alt="iOS" />
<img src="https://img.shields.io/badge/Windows-0078D4?logo=windows&logoColor=white" alt="Windows" />
<img src="https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white" alt="macOS" />
<img src="https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black" alt="Linux" />
<img src="https://img.shields.io/badge/HarmonyOS-0A59F7?logoColor=white" alt="HarmonyOS / OpenHarmony" />

<br/>

**[简体中文](./README.md)** | [English](./README.en.md)

</div>

> 当前最新版 **v3.4.0（正式版）**。上一版本为 **v3.3.0**（正式版，翻译与阅读体验升级 + 鸿蒙 PC 适配）。项目持续迭代中，欢迎通过 Pull Request / issues 贡献代码和想法。完整更新历史见 [RELEASE_NOTES](./RELEASE_NOTES.md)。
>
> 📱 **鸿蒙（HarmonyOS / OpenHarmony）正式支持**：arm64 真机完整可用，另提供 iOS 未签名构建；详情见下方[「平台支持」](#二平台支持)。
>
> 💬 **QQ 开发交流群**：[1132306726](https://qm.qq.com/q/KQ9T6Zh7EG)（点群号即可加群）。

NexHub 是一个基于 [Flutter](https://flutter.dev) 构建的跨平台媒体聚合客户端，把「动漫、漫画、小说、影视」四类内容统一到一个应用里浏览、搜索、阅读与观看。

---

## 📚 文档导航

| 文档 | 说明 |
| --- | --- |
| 📖 [核心特色详解](docs/features.md) | 源即插件、阅读器 / 播放器、Bangumi 同步、网络配置等特色能力详解 |
| 🧭 [用户使用指南](docs/user-guide.md) | 获取安装、导入源、日常使用、常见问题 |
| 🛠️ [开发者指南（含源编写）](docs/developer-guide.md) | 环境准备、项目结构、源编写分级教程（基础 / 中级 / 高级）、字段规范、完整示例 |
| 📜 [更新历史](RELEASE_NOTES.md) | 各版本完整更新日志 |

---

## 一、项目简介

**NexHub** 的核心设计理念是 **「源即插件 · 共创社区」**：

- **应用只提供「引擎」**，负责界面、阅读器、播放器、网络请求、解析调度等通用能力；
- **「内容从哪来」由「源」决定**。每个源是一份可导入的 JSON 配置文件（可包含声明式选择器，或内嵌 JavaScript 脚本），描述如何从一个具体站点抓取列表、详情、章节与内容；
- **应用不内置、不打包任何预备源**。所有源由用户自行导入，或在社区中共享。任何人都可以自己写一份源 JSON，导入后即可解析该站点的内容，**无需改动任何应用代码**。

这种设计的收益：

1. **合法与安全**：公开仓库不包含任何指向具体站点的「内置源」，降低版权与合规风险；
2. **可持续与开放**：解析能力由社区共同维护，站点改版只需更新对应源文件，应用本体保持稳定。

> ⚠️ 正因为「不内置源」，首次安装后的 NexHub 是「空的」——你需要导入至少一个源，才能看到内容。这就像买了一个书架，但书要自己放上去。

---

## 二、平台支持

### 各平台状态

| 平台 | 状态 | 获取方式 |
| --- | --- | --- |
| Android | ✅ 完整支持 | Release 页 APK |
| Windows | ✅ 完整支持 | Release 页 zip / 安装包 |
| Linux | ✅ 完整支持 | Release 页 tar.gz / deb / AppImage |
| macOS | ✅ 完整支持 | Release 页 zip / dmg |
| iOS | ✅ 支持（未签名 IPA） | Release 页 IPA（自签侧载） |
| **HarmonyOS / OpenHarmony（arm64 真机）** | ✅ 完整支持 | Release 页未签名 HAP（自行签名侧载） |

### 📱 鸿蒙版说明

NexHub 鸿蒙版（HarmonyOS / OpenHarmony，arm64 真机）已正式支持。与 Android / 桌面端一致，鸿蒙版**同样是完整的「源即插件」客户端**。

**鸿蒙版可用能力**：

- 源解析与阅读全链路（含内嵌 JS 脚本源，QuickJS 原生桥）；
- 视频播放（libmpv 内核，与 Android 同源，支持倍速 / 音轨 / 字幕 / 防盗链头）与弹幕同屏渲染；
- 画中画（系统小窗，含控制面板）、系统通知、图片保存进系统相册（系统确认框，免权限）、剪贴板图片粘贴；
- 小说离线朗读（系统 CoreSpeechKit 引擎，支持语速 / 睡眠定时 / 后台朗读）与自建在线 HTTP TTS；
- 阅读器音量键翻页（原生按键通道，支持长按连续翻页）；
- 投屏（原生 mDNS 设备发现）、Material You 莫奈取色（壁纸主色实时跟随）、ECH 加速（引擎随 HAP 打包）；
- 收藏 / 下载任务 / 历史记录的本地持久化（独立文件存储，应用强杀后不丢）；
- Bangumi 账号登录与同步（应用内 WebView 完成授权）；
- 应用内更新（跳转浏览器发布页下载新版 HAP）。

**安装方式（侧载）**：从 Release 页下载 `NexHub-ohos-arm64-unsigned.hap` → 使用端侧签名工具对安装包自行签名后安装（或通过 DevEco Studio / hdc 安装）。发布物统一不带签名，签名环节交由使用者完成。

### 鸿蒙版平台差异（未完成项）

| 功能 | 鸿蒙现状 | 替代方案 / 说明 |
| --- | --- | --- |
| 本地文件夹导入 | 目录选择暂不可用 | 改走「导入文件」逐个选择 |
| 自定义下载目录 / 自定义截图目录 | 支持系统「下载」目录 | 鸿蒙手机不支持任意文件夹选择；可在应用私有目录与系统「下载」（`Download/<bundleName>`，文件管理可见）之间切换 |
| 插件导出 / 备份导出 | 无目录选择 | 通过系统「另存为」/ 分享保存 |
| 播客后台通知栏 | 暂不可用 | 应用内播放不受影响 |
| 模拟器（x64） | 不支持视频播放 / ECH 加速 | 播放内核与 ECH 引擎仅有 arm64 产物；x64 调试构建已带 QuickJS / WebView 原生库 |

> 以上差异随系统能力与上游适配进展持续收敛，修复项会在后续版本发布说明中标注。

---

## 🗺️ 路线规划（TODO · 规划中 · 欢迎参与）

以下功能**尚未实现**，是后续版本的重点方向。设计存在大量取舍，欢迎到 GitHub Discussions / Issues 提意见：

1. **增加其他同步方式**：在现有 Bangumi 同步之外，接入 AniList、MyAnimeList、Trakt、SIMKL、MDList 等更多后端，并支持跨后端双向同步与可配置冲突策略；
2. **AI 搜源 / 自然语言检索**：在应用内用自然语言搜源、看番 / 看书助手等更深度的 AI 辅助。

> 已实现：漫画页翻译（MTL）与视频字幕实时翻译已在 **v2.0.0-beta.3** 落地；小说翻译（AI 双语 / 段落翻译）、AI 辅助（内容摘要 / 章节配图）已在 **v2.0.0-beta.2** 落地。以上规划项不含在本次发布中；具体落地顺序与形态会以社区反馈调整。

---

## 三、源即插件 · 共创社区

NexHub 的生命力来自社区共同维护的「源」。我们欢迎任何人参与：

- **使用方**：导入社区共享的源，按自己需要组织内容；
- **创作者**：编写自己的源 JSON，描述如何解析某个站点，分享给他人；
- **贡献者**：完善引擎、阅读器、播放器、文档，或提出 Issue / PR。

> 应用只提供引擎，解析能力来自社区。站点改版只需更新对应源文件，应用本体保持稳定——这就是「源即插件 · 共创社区」的价值。

---

## 四、免责声明

> 本声明依据中华人民共和国相关法律法规（包括但不限于《中华人民共和国网络安全法》《中华人民共和国著作权法》《信息网络传播权保护条例》《中华人民共和国未成年人保护法》等）及一般国际惯例拟定。使用本软件即表示你已阅读、理解并同意本声明全部内容。

1. **技术演示性质**：NexHub 是一款开源的「聚合 / 阅读工具」技术演示项目，其本身**不提供、不存储、不中转任何受版权保护的内容**，也**不内置任何指向具体站点的内容源**。

2. **「源」由用户自行负责**：本软件的所有内容均来自用户**自行导入**的「源」。源所对应的站点内容、其合法性、准确性、完整性，以及源本身的合规性与版权状况，**完全由源的提供方与使用方负责**，与本软件作者及贡献者无关。

3. **遵守法律法规**：使用者应当严格遵守所在地法律法规，包括但不限于网络安全、著作权、信息网络传播权保护等相关规定。你仅可将本软件用于**个人学习、技术研究与非商业用途**，不得利用本软件实施任何侵犯他人著作权、隐私权、商业秘密或其它合法权益的行为，不得用于任何商业用途或非法传播。

4. **版权与侵权处理**：若你导入的源涉及受版权保护的内容，请仅在与权利人授权范围相符的前提下使用；如权利人认为相关源或内容侵犯其合法权益，请联系该源的提供方予以移除，本软件作者将予以必要配合。

5. **「按现状」提供**：本软件按「现状（AS IS）」提供，不作任何明示或默示的担保（包括但不限于适用性、可靠性、无病毒、无错误的担保）。对于因使用或无法使用本软件所导致的任何直接、间接、偶然、特殊或后果性损失，作者与贡献者**不承担任何责任**。

6. **未成年人保护**：若使用者为未成年人，请在监护人的指导下使用本软件，并遵守《中华人民共和国未成年人保护法》等相关规定，避免接触不适宜的内容。

7. **年龄限制与内容分级**：NexHub 内置**年龄分级（ageRating）体系**——源作者应在源 JSON 中如实声明 `ageRating`（`general` 全年龄 / `teen` 青少年 16+ / `mature` 成人 18+）。**`mature`（18+）源在默认设置下会自动隐藏**，用户需在设置中主动开启年龄限制内容后才会显示。应用只负责按分级规则**过滤展示**，**不对任何源的实际内容作审查、背书或担保**；源所指向的站点是否允许其内容被访问、抓取与传播，由源作者与使用者自行判断并承担相应责任。请勿导入、传播违反所在地法律法规或侵犯他人权益的源与内容。

8. **地域合规**：如果你所在国家或地区的法律禁止或限制本软件的使用，请立即停止使用。本软件在不同司法管辖区的合法性由使用者自行判断与承担。

9. **账号与隐私**：使用本软件过程中产生的浏览历史、导入的源等数据，**默认仅保存在你本地设备**；若你启用任何云同步或第三方服务，请自行了解并接受该服务方的隐私政策与数据处理方式。本仓库的公开代码**不包含任何个人隐私、密钥或凭据**。

10. **免责范围**：本声明构成你与本软件作者及贡献者之间就本软件使用的完整谅解。如本声明任何条款被认定为无效，不影响其余条款的效力。

---

## 五、致谢

感谢以下项目与社区，NexHub 的建立离不开它们：

- [Legado](https://github.com/gedoor/legado)（及其各类改版）的「书源」规则系统，为 NexHub「源即插件」的解析与共创理念提供了核心启发（尤其小说源的声明式 / 脚本式写法）。NexHub 小说分页器以独立 Dart 实现借鉴了 Legado `ChapterProvider` 的分页算法，未复制其源码；Legado 上游仓库未附带明确的开源许可证，本致谢仅作启发署名，不暗示任何许可授权。
- [Mihon](https://github.com/mihonapp/mihon)（Tachiyomi 衍生版，及其各类改版）的扩展源架构与漫画阅读器交互，为 NexHub 的漫画解析与阅读体验提供了重要参考。Mihon 以 Apache License 2.0 发布（© Mihon contributors）。
- [RSSHub](https://github.com/DIYgod/RSSHub) 的 RSS 聚合能力为 NexHub 的订阅功能提供了服务基础。RSSHub 以 AGPL-3.0 发布（© DIYgod），NexHub 仅作为客户端调用其实例，未修改或再分发其源码。
- [wenyi](https://github.com/BigDawnGhost/wenyi) 的小说 AI 翻译管线设计（上下文增强、术语闭环、证据驱动审查与精译合成），为 NexHub 内置小说翻译的深度优化提供了重要参考。wenyi 以 MIT License 发布（© BigDawnGhost），NexHub 未复制其源码，仅借鉴设计思想独立实现。
- **Flutter 鸿蒙社区（Flutter SIG / OpenHarmony 适配项目）**：为 Flutter 生态带来鸿蒙平台支持，NexHub 鸿蒙版基于社区维护的 Flutter 鸿蒙版 SDK 与三方库适配成果构建；
- [Flutter](https://flutter.dev) 与 Dart 团队，提供优秀的跨平台框架；
- [flutter_js](https://pub.dev/packages/flutter_js)（quickjs 内核），为源内嵌脚本提供安全的 JS 沙箱；
- [xpath_selector](https://pub.dev/packages/xpath_selector) 与 [html](https://pub.dev/packages/html)，提供声明式抽取能力；
- [dio](https://pub.dev/packages/dio)，统一的网络请求与 Cookie 管理；
- [provider](https://pub.dev/packages/provider)，状态管理；
- [dynamic_color](https://pub.dev/packages/dynamic_color)，Material You 动态配色；
- [media_kit](https://pub.dev/packages/media_kit)（libmpv 内核），影视播放能力；
- [Bangumi 番组计划](https://bgm.tv) 提供开放 API，使 NexHub 的收藏 / 进度 / 评分同步与条目资料展示成为可能（NexHub 仅作为第三方客户端调用其公开接口）；
- [canvas_danmaku](https://pub.dev/packages/canvas_danmaku)，弹幕渲染；
- [猫抓 cat-catch](https://github.com/xifangczy/cat-catch) 等开源嗅探项目（cat-catch / VBrowser-Android / VidDown / pup-sniffer）的「网络拦截 + DOM 检测 + API 钩子」嗅探方法论，为 NexHub 内置嗅探功能提供了重要参考（仅借鉴方法论，未引入其代码，应用以 Apache-2.0 协议开源）；
- 所有为「源即插件 · 共创社区」理念做出贡献的开发者、源作者与用户。

---

## 六、开源协议

本项目以 **Apache License 2.0（Apache-2.0）** 协议开源，详见仓库根目录的 [LICENSE](LICENSE) 文件与 [NOTICE](NOTICE) 第三方署名文件。

Apache-2.0 允许在任何项目中免费使用、复制、修改与分发本软件（含闭源或商业产品），但须：保留版权与许可声明、在修改文件中标注变更、若上游含 NOTICE 文件须随附其署名内容。**本软件按「原样」提供，不提供任何担保。** 如本项目包含第三方组件的衍生内容，其署名与许可见 [NOTICE](NOTICE)。

---

<p align="center">NexHub · 源即插件 · 共创社区</p>
