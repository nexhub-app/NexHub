**[简体中文](./developer-guide.md)** | [English](./developer-guide.en.md)

# 🛠️ 开发者指南

> 面向贡献者与源作者。环境准备、项目结构、以及最重要的——**源编写分级教程**（基础 / 中级 / 高级）与完整示例。
>
> 📚 在线版源编写教程（含双语与更多动图演示）：<https://nexhub-app.github.io/website/>；本文档与其内容一致并持续同步。

## 4.1 环境准备

- 安装 [Flutter SDK](https://flutter.dev)（本项目要求 **Flutter 3.47.0**，Dart 3.x）；
- 配置好对应平台的编译环境（如 Android Studio / Xcode / Visual Studio 等）；
- 确认 `flutter doctor` 无明显报错。

## 4.2 获取与运行代码

```bash
git clone https://github.com/nexhub-app/nexhub.git
cd nexhub
flutter pub get
flutter run
```

选择目标设备（模拟器 / 真机 / 桌面端）即可启动。

## 4.3 构建发布包

```bash
# Android
flutter build apk
# Windows
flutter build windows
# 其它平台以此类推
```

## 4.4 项目结构

```
nexhub/
├── lib/                  # 应用主体代码（Dart）
│   ├── core/             # 核心能力：网络请求、解析调度、源仓库、阅读器/播放器基础设施
│   │   ├── models/       # 数据模型（如 PluginConfig 源配置）
│   │   ├── resolver/     # 解析引擎调度（builtin / script / webview / hybrid）
│   │   ├── scraper/      # 列表/详情/章节抓取与抽取
│   │   └── services/     # 源仓库、历史、下载等服务
│   ├── features/         # 各业务模块：首页、源管理、漫画、小说、影视、设置、下载……
│   └── l10n/             # 多语言资源（中文 / 英文）
├── assets/               # 资源（图标、通用热搜词等；不含任何站点源）
├── plugins/              # 源目录（见下方说明）
│   └── builtin/          # ⚠️ 此目录在仓库中仅保留占位，不提交任何源 JSON
├── test/                 # 单元测试（含源 JSON 校验，无内置源时自动跳过）
├── android/ ios/ linux/ macos/ windows/ web/   # 各平台工程
└── pubspec.yaml          # 依赖与资源声明
```

**关于 `plugins/builtin/`**：本仓库**不会**把任何 `.json` 源文件提交进去（已在 `.gitignore` 中排除）。该目录仅以 `.gitkeep` 占位，保证工程结构完整、可正常构建。真正的源由你保存在本地、或来自社区共享，**不进入公开仓库**。

**已被排除、绝不入库的内容**：

- `plugins/builtin/*.json`（任何内置 / 预备源）
- `reference/`（源的本地备份与示例）
- `docs/` 下仅白名单公开文档入库（`features.md` / `user-guide.md` / `developer-guide.md` / `GITHUB_ISSUE_TEMPLATE.md` 及其 `.en.md` 英文版）；其余内部开发文档、重开发提示词与计划、测试数据扫描脚本等均不入库
- `build/`、`sdk/`（构建产物与 Flutter SDK，体积巨大）
- `.workbuddy/`、`.trae/`、`.qoder/`、`.probe_tmp/`（本地工具与探针临时产物）
- 根目录的临时脚本（如 `tmp_*.mjs`、`run_probe.*`、`net_check.*`）

---

## 4.5 源即插件：如何编写与贡献一个源

NexHub 的解析能力完全由源 JSON 驱动。一个源是一个 JSON 文件，描述如何从一个站点抓取内容。

### 4.5.1 源层级网站设置指南（site / network）

每个源的「站点元信息」与「网络访问方式」都写在源文件里，这就是**源层级的网站设置**：

**`site`（必填）**——站点基本信息：

| 子键 | 类型 | 说明 |
| --- | --- | --- |
| `site.domain` | string | 站点主域名（如 `example.com`） |
| `site.baseUrl` | string | 站点根地址（如 `https://example.com`），用于拼接相对链接 |
| `site.userAgent` | string? | 可选，自定义 UA |
| `site.cookies` | string? | 可选，站点 Cookie（如 `session=xxx`） |
| `site.headers` | object? | 可选，自定义请求头 |
| `site.mirrors` | array? | 可选，镜像站列表，每项 `{name, domain, baseUrl}`（站点主域失效时自动切换） |
| `site.publishPageUrl` | string? | 可选，发布页地址（站点主域失效时的导航页，可从中提取备用镜像） |
| `site.publishMirrorSelector` | string? | 可选，发布页镜像提取规则（正则字符串或 CSS 选择器） |

**`network`（可选，v0.4.0 新增）**——源级网络覆盖，让源可以自带「推荐网络配置」：

| 子键 | 类型 | 说明 |
| --- | --- | --- |
| `network.proxy` | object? | 代理覆盖，如 `{ "mode": "manual", "protocol": "http", "host": "...", "port": 7890 }` |
| `network.dns` | object? | DNS 覆盖，如 `{ "mode": "doh", "dohUrl": "https://cloudflare-dns.com/dns-query" }` 或 `{ "mode": "custom", "servers": ["8.8.8.8"] }`；另有 `resolveSuffix` / `resolveSuffixDomains`（见下方说明） |
| `network.hosts` | array? | Hosts 覆盖，每项 `{ "ip": "1.2.3.4", "host": "example.com", "enabled": true }` |
| `network.sni` | object? | SNI 覆盖，如 `{ "enabled": true, "defaultSni": "-" }`；值为 `-` 表示免 SNI，普通域名表示以该域名作 SNI，`domainSni` 为 `{"匹配域名": "SNI值"}` 映射（键可用 `.example.com` 后缀通配） |
| `network.ech` | object? | ECH 覆盖，如 `{ "enabled": true, "echConfigList": "<base64>" }`；原生引擎驱动，对直连 HTTPS 生效（见下方说明） |

规则：某子键**缺省 = 继承全局设置**；填写了则**整方面覆盖全局**。生效优先级：**用户对源的 UI 覆盖 > 源 JSON 的 `network` 块 > 全局设置 > 默认值**。非法值只告警、不会导致源无法启用。

> **`sni` 生效说明**：对「https 直连」真实生效（TLS 握手在应用内完成，SNI 可被覆盖为配置值或置 `-` 免 SNI；免 SNI 配合 hosts 钉定可达 IP 可绕过按 SNI 的连接阻断，Cloudflare 边缘接受无 SNI 握手并按 Host 头路由）。走代理时不生效。
>
> 💡 ECH 现已接通：应用内置原生 ECH 引擎（OpenSSL），对直连 HTTPS 真实生效，不再依赖外部代理。作用域分应用级（接管任意 https 域，不支持 ECH 的站点由原生侧逐域自适应回落，不会搞断正常站点）、源级（只接管该源 `site.baseUrl` 的 host，可在源 JSON `network.ech` 或 UI 覆盖单独开关）、Bangumi 专用；原生库随 Android APK（arm64-v8a / armeabi-v7a / x86_64 三架构）、Windows 桌面端与鸿蒙 HAP（arm64-v8a）打包；macOS / Linux 暂未打包原生库，整套自动降级为直连。其余（proxy / dns / hosts / sni）依旧全部真实生效。

> **`dns.resolveSuffix`（解析后缀）**：把「目标主机 + 后缀」交给 DNS 查询，用查到的地址建连，请求头里的 Host 仍是原主机名。
> 用途：站点主域被 DNS 污染时，查一个不受干扰的别名（如 CDN 提供的别名域）拿到真实地址，**配置文件里不需要写死任何 IP**——地址由每台设备用自己的 DNS 现算，因此适合公开发布的源。
>
> | 子键 | 类型 | 说明 |
> | --- | --- | --- |
> | `resolveSuffix` | string? | 形如 `".alias-cdn.example"`（须以 `.` 开头）；空表示不启用 |
> | `resolveSuffixDomains` | array? | 后缀的作用域：精确域名或以 `.` 开头的子域通配（如 `.example.org` 命中 `a.example.org`）。**留空 = 对全部主机生效**，通常应显式列出，避免给图片节点等无关主机加一次必然失败的解析 |
>
> 失败处理：后缀查询失败或返回空 → 自动回退原主机名解析，不会变成硬错误。
> 典型组合：`{ "mode": "system", "resolveSuffix": "...", "resolveSuffixDomains": ["..."] }` + `{ "sni": { "enabled": true, "defaultSni": "-" } }`。

### 4.5.2 源编写教程（基础 / 中级 / 高级）

本节与官网《源编写教程》同源同步：按难度分三档、共 22 节，每节给出说明、字段表与代码示例。在线版（双语、带目录跳转）见 [NexHub 官网 · 源编写教程](https://nexhub-app.github.io/website/docs-tutorial.html)。

> 协议细节以本仓库 `lib/core/models/plugin_config.dart` 的实际解析为准；本文与官网同步维护，两者若有出入以代码为准。

#### 🟢 基础（入门必读）

##### 一、源文件是什么

源（Source）是一个 JSON 文件，它描述了「如何去某个网站抓取动漫 / 漫画 / 小说 / 影视」。NexHub 只提供通用引擎，所有站点专属的解析逻辑都写在这个文件里——这就是「源即插件」。

应用内置一个 JS 沙箱：能用声明式选择器（jsonpath / css / xpath）直接抽取字段，也能在源里内嵌 JavaScript 处理复杂页面。你写的源文件，别人一键就能导入使用，无需更新整个 App。

##### 二、基础字段（每个源都有）

每个源的「头部」都是这些通用字段。填好后 App 才能识别、管理与升级你的源。

注意：源模型不会读取 lang / builtin 这两个键——写进文件也会被忽略，请勿当作功能字段；author（作者）已是正式字段，会显示在源详情中。

年龄分级（ageRating）也属于基础字段：可填 general（全年龄）/ teen（青少年 16+）/ mature（成人 18+），兼容别名如 all / 16 / r18 / nsfw 等；缺省为 general。mature 在默认设置下会自动对未开启年龄确认的用户隐藏。

解析方式（parser.type）的详细取值见第十二、十三节。

| 字段 / 键 | 说明 |
| --- | --- |
| `id` | 唯一标识，如 manga_demo。同名源按 version 决定升级/跳过，请避免与他人重复。 |
| `name` | 显示名称，如「示例漫画」。 |
| `author` | 可选，源作者名（显示在源详情中，方便溯源与致谢）。 |
| `version` | 整数版本号（会被强制转为整数，默认 1）。同名源按版本号升级/跳过。 |
| `type` | 媒体类型：animeSource（影视/动漫）/ mangaSource（漫画）/ novelSource（小说）。 |
| `site` | 站点信息对象（必填）：domain、baseUrl（站点根地址，用于拼接相对链接）、mirrors 镜像站列表，可选 userAgent / cookies / headers。 |
| `parser` | 解析配置：{ type, overrides?, script? }。type 取 builtin / hybrid / script。 |
| `ageRating` | 可选。年龄分级 general / teen / mature；缺省 general，mature 默认隐藏。 |
| `enabled` | 可选，是否启用（默认 true）。 |

```json
{
  "id": "demo_anime",
  "name": "演示动漫",
  "version": 1,
  "type": "animeSource",
  "ageRating": "general",
  "site": {
    "domain": "example.com",
    "baseUrl": "https://example.com",
    "mirrors": [ { "name": "主站", "domain": "example.com", "baseUrl": "https://example.com" } ]
  },
  "parser": { "type": "hybrid", "overrides": { "latest": { "type": "builtin" } } }
}
```

#### 🟡 中级（功能与解析）

##### 三、搜索模块（search / ruleSearch）

用户点击搜索框输入关键词时触发。两种范式：

- 影视/漫画（范式A）：在 routes 里定义 search 的 url（含 {keyword} 占位），selectors 或 script 把结果列表抽出来。
- 小说（范式B，Legado 兼容）：用 ruleSearch 字段以 CSS 选择器声明每条结果的书名、作者、封面、详情链接。

返回字段通常含：id（详情页标识）、title、cover、detailUrl。

| 字段 / 键 | 说明 |
| --- | --- |
| `routes.search.url` | 范式A：搜索接口，{keyword} 为关键词、{page} 为页码。 |
| `selectors.list / bookList` | 结果容器选择器（jsonpath 或 css）。 |
| `selectors.title / bookName` | 书名/标题字段。 |
| `selectors.cover / bookCoverUrl` | 封面图地址，相对路径会自动拼接 baseUrl。 |
| `selectors.id / bookUrl` | 用于后续打开详情页的标识或链接。 |

```js
// 范式A：routes + selectors（影视）
"routes": {
  "search": { "url": "/s?wd={keyword}&page={page}", "method": "get", "responseType": "json" }
},
"selectors": {
  "list": "$.list",
  "title": "$.vod_name",
  "cover": "$.vod_pic",
  "id": "$.vod_id"
}

// 范式B：小说 ruleSearch（Legado 兼容）
"ruleSearch": {
  "bookList": ".bookbox",
  "bookName": ".bookname a@text",
  "bookAuthor": ".author@text",
  "bookCoverUrl": ".bookimg img@src",
  "bookUrl": ".bookname a@href"
}
```

##### 四、发现 / 分类模块（discovery / ruleExplore）

「首页」与「按分类浏览」使用此模块。范式A 用 latest/explore/category 路由 + categoryEntries 分类表；范式B 用 ruleExplore + exploreUrl（每行「分类名::链接」）。

首页板块由 homeSections 定义（标题、路由、样式 grid/list、数量）。

| 字段 / 键 | 说明 |
| --- | --- |
| `category.categoryEntries` | 范式A：分类数组，每项 {id, title}，点击后拼接进 category 路由。 |
| `homeSections` | 首页展示的板块（最新更新、热门等），引用某个路由并限制条数。 |
| `exploreUrl` | 范式B：换行分隔的「分类名::URL」，用于发现页。 |

```json
"category": {
  "categoryEntries": [
    { "id": "all", "title": "全部" },
    { "id": "1", "title": "动漫" },
    { "id": "2", "title": "剧场版" }
  ]
},
"homeSections": [
  { "id": "latest", "title": "最新更新", "route": "latest", "style": "grid", "limit": 18 }
]
```

##### 五、详情 / 目录模块（detail / ruleBookInfo）

点开一部作品时加载。负责：标题、封面、简介、作者/主演、标签、状态、目录（章节/话数）列表。

范式A 用 detail 路由 + selectors.detail 与 episodes 选择器；范式B 用 ruleBookInfo（作品信息）+ ruleToc（章节列表，含 chapterList / chapterName / chapterUrl）。

| 字段 / 键 | 说明 |
| --- | --- |
| `selectors.detail` | 范式A：对象，逐字段抽取标题/封面/简介/演员等。 |
| `selectors.episodes` | 范式A：章节链接选择器，如 ul li a。 |
| `ruleBookInfo.tocUrl` | 范式B：进入目录页的链接；留空则详情页本身即目录。 |
| `ruleToc.chapterList` | 范式B：章节项选择器；nextTocUrl 支持目录分页。 |

```js
// 范式A
"selectors": {
  "detail": {
    "title": "$.list[0].vod_name",
    "cover": "$.list[0].vod_pic",
    "description": "$.list[0].vod_content"
  },
  "episodes": "ul.anthology-list-play li a"
}

// 范式B（小说）
"ruleToc": {
  "chapterList": ".chapter li a",
  "chapterName": "@text",
  "chapterUrl": "@href",
  "nextTocUrl": "a:contains(下一页)@href"
}
```

##### 六、正文 / 章节内容模块（content / ruleContent）

打开具体一章时加载：

- 小说（范式B）：ruleContent.content 抽取正文文本（可用 @textNodes 取干净文本，nextContentUrl 支持正文分页）。
- 漫画：先由 chapters 路由/脚本拿到话列表，再由 images 模块解析出该话的图片地址数组。
- 影视：由 video 模块解析出可播放的视频地址。

| 字段 / 键 | 说明 |
| --- | --- |
| `ruleContent.content` | 小说正文选择器，常用 #content@textNodes 取段落文本。 |
| `ruleContent.nextContentUrl` | 正文「下一页」链接，自动连读。 |
| `chapters（漫画）` | 返回话列表，每项含 id 与详情链接，供 images 使用。 |
| `images（漫画）` | 返回该话的图片 URL 数组，支持解密函数。 |

```json
"ruleContent": {
  "content": "#nr1@textNodes",
  "title": "#nr_title@text",
  "nextContentUrl": "a:contains(下一页)@href"
}

// 漫画 images（脚本返回图片数组）
"images": {
  "type": "script",
  "function": "parseImages",
  "script": "function parseImages(html, context){ /* 解析并解密图片URL */ return [url1, url2]; }"
}
```

##### 七、视频解析模块（player / video）

影视源的核心。由 video 路由拿到播放页 HTML，再用选择器 / 脚本 / WebView 抽出真实视频地址（m3u8 / mp4）。

三种解析方式：声明式选择器（如 //video/@src）、内嵌 JS（overrides.type:"script"）、或 WebView 渲染后抽取（overrides.type:"webview"，常用于 m3u8 或需要执行页面 JS 才能拿到地址的场景）。

弹幕（danmaku）若源站提供，可在 video 模块额外返回弹幕接口地址。多线路：在 episodes 里若同一集有多个解析地址，App 会自动提供「线路切换」。

异步数据：需先请求接口再解析时，脚本返回 {__meta:true,__fetchUrl,...}，由引擎预取后再调用处理函数（详见第十三节）。

| 字段 / 键 | 说明 |
| --- | --- |
| `routes.video.url` | 播放页地址（通常为 episodes 取出的链接）。 |
| `overrides.video.type` | 该接口解析方式：builtin / css / xpath / jsonpath / script / webview。视频常用 webview 提取 m3u8。 |
| `selectors.video` | 视频地址选择器，如 //video/@src 或 jsonpath 抽取（声明式时）。 |
| `__meta 异步` | 需先请求接口再解析时，脚本返回 {__meta:true,__fetchUrl,...}，由引擎预取后再调用处理函数（详见第十三节）。 |

```js
// 方式一：声明式
"routes": { "video": { "url": "{url}", "method": "get", "responseType": "html" } },
"parser": { "type": "hybrid", "overrides": { "video": { "type": "webview" } } }

// 方式二：脚本先抓取接口再解析
function parseVideo(html, context){
  var api = extractApi(html);
  return { __meta: true, __fetchUrl: api, __processor: "__processVideo" };
}
function __processVideo(json, context){
  return json.url; // 返回真实播放地址
}
```

##### 八、漫画图片解析（images）

漫画源最常用的脚本模块。站点常对图片地址加密，需要在脚本里解密。images 函数接收详情页/接口数据，返回该话的图片 URL 数组。

注意：很多韩漫/国漫站把图片地址用自定义算法混淆，解密逻辑就写在这里。

| 字段 / 键 | 说明 |
| --- | --- |
| `function` | 入口函数名，如 parseImages，与 overrides.images.function 对应。 |
| `返回` | 字符串数组，每个元素是一张图片的完整 URL。 |
| `context.baseUrl` | 脚本内可用的站点 baseUrl，用于补全相对路径。 |

```js
function parseImages(raw, context){
  var baseUrl = (context.baseUrl || '').replace(/\/$/, '');
  // 解密 raw 得到真实地址列表
  var urls = decrypt(raw);
  return urls.map(function(u){ return u.indexOf('/')===0 ? baseUrl+u : u; });
}
```

##### 九、网络收藏（webFavorite）

如果你的源站本身提供「我的书架 / 收藏」这类网页，可以声明 webFavorite，让 App 在在线浏览页多出一个「网络收藏」Tab。用户在这里看到的收藏来自源站账号（需登录），不是 App 本地收藏。

声明方式：在源顶层加 webFavorite 对象。enabled 默认 true；title 为该 Tab 的显示名；route / url 是「查看收藏列表」的路由或地址；addRoute / addUrl 是「加入收藏」的路由或地址，支持 {id} / {detailUrl} / {title} 占位符（自动替换为当前作品的标识 / 详情链接 / 标题）；requireLogin 为 true 时要求先登录才能访问。

注意：webFavorite 与 App 本地收藏相互独立——本地收藏由 App 管理，网络收藏走源站接口。

| 字段 / 键 | 说明 |
| --- | --- |
| `enabled` | 可选，是否启用网络收藏 Tab（默认 true）。 |
| `title` | 可选，Tab 显示名，如「我的书架」。 |
| `route / url` | 查看收藏列表的路由名或完整地址；二选一，route 需在 routes 中定义。 |
| `addRoute / addUrl` | 加入收藏的路由或地址，支持 {id} / {detailUrl} / {title} 占位符。 |
| `requireLogin` | 可选，true 时要求先登录源站。 |

```json
"webFavorite": {
  "title": "我的书架",
  "route": "webFavorite",
  "url": "/user/bookshelf",
  "addUrl": "/user/favorite/add?id={id}",
  "requireLogin": true
}
```

##### 十、源公告（announcement）

源作者可以用 announcement 给使用该源的用户发布一条公告（如「站点换域名，请更新源」）。公告会以横幅（banner）形式展示在源的首页与详情页顶部。

announcement 是源顶层的可选对象：title 为必填（公告标题）；body 为可选正文；url 为可选「查看详情」链接；updatedAt 为可选更新时间（Unix 秒，用于显示「几天前」）。不填 url 时，整条公告不可点击。

| 字段 / 键 | 说明 |
| --- | --- |
| `title` | 必填，公告标题。 |
| `body` | 可选，公告正文。 |
| `url` | 可选，点击公告跳转的链接（如迁移说明页）。 |
| `updatedAt` | 可选，更新时间，Unix 秒级时间戳。 |

```json
"announcement": {
  "title": "站点已更换域名",
  "body": "旧域名 example-old.com 已停用，请更新到新域名。",
  "url": "https://example.com/notice",
  "updatedAt": 1700000000
}
```

##### 十一、周期表 / 周更列表（schedule）

想让源在首页展示「周更表 / 时间表」（周一到周日每天更新了哪些作品）？用 homeSections 里 style 为 schedule 的板块即可，App 会按星期分组渲染。

做法：

1. 在 homeSections 加一项 { id, title, route:'week', style:'schedule', limit:0, more:false }。route 名字可自定（这里用 week）。
2. 在 routes 里定义同名的 week 路由，其返回结果需带「星期」字段（App 按该字段把作品分到周一到周日）。

这样用户打开源首页就能看到按星期排列的更新表。limit:0 表示不限制条数；more:false 表示不显示「查看更多」。

| 字段 / 键 | 说明 |
| --- | --- |
| `homeSections[].style` | 设为 'schedule' 即开启周期表板块。 |
| `homeSections[].route` | 周期表数据的路由名（需与 routes 中的定义一致）。 |
| `routes.week` | 返回带星期字段的列表；App 据此分到周一~周日。 |
| `limit / more` | limit:0 不限制条数；more:false 隐藏「查看更多」。 |

```json
"homeSections": [
  { "id": "week", "title": "周更列表", "route": "week", "style": "schedule", "limit": 0, "more": false }
],
"routes": {
  "week": { "url": "/api/weekly", "method": "get", "responseType": "json" }
}
```

#### 🔴 高级（脚本与实战）

##### 八（续）、图片字节解密（imageTransform）

部分图床对**图片字节本身**加密（浏览器端由站点自带 JS 解密渲染），无论怎么配 Referer/UA，客户端拿到的图片都是密文，直接解码失败。这类源可在源顶层声明 imageTransform 段：列出需要解密的 CDN host，并声明解密算法，引擎在图片下载层统一解密（密钥/算法全部来自源 JSON，引擎不写死任何站点逻辑）。

适用：覆盖社区常见的图片字节加密方式——aes-cbc / aes-ecb / rc4 / xor；IV 支持「文件头前缀字节」/「固定值」/「全零」；填充支持 pkcs7 / none；密钥与 IV 支持 utf8 / base64 / hex 编码。解密后的明文进磁盘缓存，保存/分享自动继承。

注意：matchHosts 必须枚举**所有**可能下发图片的 CDN host（部分站点按镜像域名轮换图床，漏一个 host 该镜像的图就是坏图）。

| 字段 / 键 | 说明 |
| --- | --- |
| `matchHosts` | 需要解密的图片 CDN host 列表（精确匹配，忽略大小写）。 |
| `decrypt.algo` | 解密算法：aes-cbc / aes-ecb / rc4 / xor。 |
| `decrypt.key / keyEncoding` | 密钥字节；keyEncoding 支持 utf8（缺省）/ base64 / hex。 |
| `decrypt.ivSource` | IV 来源：prefixBytes（密文文件前 ivLength 字节为 IV，最常见）/ fixed（用 decrypt.iv 固定值）/ none（全零 IV）。 |
| `decrypt.padding` | 填充：pkcs7（缺省）/ none（密文长度恒为 16 倍数）。 |

```json
"imageTransform": {
  "matchHosts": ["cdn.example.com", "cdn-mirror.example.com"],
  "decrypt": {
    "algo": "aes-cbc",
    "key": "16字节密钥原文",
    "keyEncoding": "utf8",
    "ivSource": "prefixBytes",
    "ivLength": 16,
    "padding": "pkcs7"
  }
}
```

##### 十二、选择器语法速查

解析方式分「顶层 parser.type」与「每个 API 的 overrides.type」两层：

- 顶层 parser.type 只取三种：builtin（纯声明式）、hybrid（声明式 + 按 API 用 overrides 覆盖，最常用）、script（全部走 JS 沙箱）。
- 每个 API 可在 overrides 里指定 overrides.type，决定该接口实际怎么解析：builtin / xpath / jsonpath / css（四种声明式子类型，归入同一套抽取引擎）/ script（JS 沙箱）/ webview（用内嵌浏览器渲染后抽取，常用于 m3u8 提取）/ webview-html（WebView 取回 HTML 再走解析，常用于反爬搜索）。

声明式选择器语法按 overrides.type 选一种：

- jsonpath：以 $ 开头，适合 JSON 接口（如 $.list[0].vod_name）。
- css：标准 CSS 选择器，适合 HTML（如 .bookname a）。
- xpath：以 // 或 ./ 开头，适合 HTML（如 //video/@src）。

小说源（Legado 兼容）额外支持「自定义语法」：@text 取文本、@href/@src 取属性、@textNodes 取干净正文、|| 为回退选择器、a:contains(文字) 按文本筛选、用 .0/.1/-1 取第 N 个。

| 字段 / 键 | 说明 |
| --- | --- |
| `顶层 parser.type` | builtin / hybrid / script 三选一，决定整源默认解析方式。 |
| `overrides.<api>.type` | 每个 API 单独指定：builtin / xpath / jsonpath / css / script / webview / webview-html。 |
| `$.field` | jsonpath，抽取 JSON 字段。 |
| `.class a@text` | css + @text 取元素文本。 |
| `//video/@src` | xpath 取属性值。 |
| `a:contains(下一页)@href` | 小说源：按可见文本筛选链接。 |

```js
// 顶层：hybrid + 各 API 指定解析方式
"parser": { "type": "hybrid", "overrides": {
  "search": { "type": "jsonpath" },
  "video": { "type": "webview" },
  "detail": { "type": "css" }
} }
// jsonpath
"title": "$.vod_name"
// css（HTML）
"bookName": ".bookname a@text"
// xpath（HTML）
"video": "//video/@src"
```

##### 十三、内嵌 JS 脚本约定

当声明式选择器搞不定时，用 parser.overrides 写 JS。每个模块可指定 type:"script" 并给出 function 名与 script 源码。

重要约定：

1. 函数签名固定为 parseXxx(html, context)，html 为页面字符串，context 含 baseUrl、log 等。
2. 必须同步返回结果（数组或对象）。
3. 需要异步数据时，返回 {__meta:true, __fetchUrl, __processor} 协议对象，引擎会先预取该 URL，再调用 __processor 同步处理函数——这是唯一安全的异步通道。
4. 不要写死任何站点常量到 App，全部留在源文件。
5. 沙箱已预置 atob / btoa（浏览器语义 polyfill，宽松剥离非法字符与尾部 =），脚本可直接调用，无需在源里内嵌同名 polyfill；若源脚本自带同名声明则覆盖默认值。同一 JsEngine 实例内顶层变量跨 meta 多跳持续可见，多跳各跳的 __processor 不再重放整段脚本，符合「同一 JsEngine 内全局持续可见」的约定。

| 字段 / 键 | 说明 |
| --- | --- |
| `function` | 入口函数名，与 overrides.`<module>`.function 对应。 |
| `context.baseUrl` | 当前源的主站地址，补全相对链接用。 |
| `context.log` | 可选日志函数，便于调试（context.log('msg')）。 |
| `__meta 协议` | 异步预取：返回该对象，引擎取数后回调 __processor。 |

```json
"parser": {
  "type": "hybrid",
  "overrides": {
    "search": {
      "type": "script",
      "function": "parseList",
      "script": "function parseList(html, context){ /* 解析并返回数组 */ return []; }"
    }
  }
}
```

##### 十四、进阶：源级网络 / 评论 / 登录（v0.4.0）

v0.4.0 起，源还能声明一些「站点级」能力，让 App 在不改引擎的前提下适配更复杂的站点：

- network（可选）：源级网络覆盖。子键 proxy / dns / hosts / sni / ech，逐项选「继承全局」或「单独覆盖」。缺省即继承全局设置，非法值只告警、不会让源无法启用。其中 sni 对直连 HTTPS 真实生效（defaultSni 填 - 即免 SNI，配合 hosts 钉 IP 可绕过按 SNI 的封锁）；ech 由内置原生引擎驱动，作用域分应用级 / 源级 / Bangumi 专用（对直连 HTTPS 真实生效）。
- comments（可选）：声明该源的评论能力。provider 默认 source（评论来自源站）；routes 声明 list / replies / post / reply / like / report 等路由（未声明的按钮不渲染）；selectors 用同一套 JSONPath/CSS/XPath 引擎抽取内容。
- 登录（可选，声明在 comments.login 段）：三种方式，可组合——
   1. WebView 登录：login.url 填登录页地址，App 用 WebView 打开让用户登录，成功后捕获会话 Cookie 存本地。
2. Cookie 登录：login.checkCookie 填「代表已登录的 Cookie 键名」，App 据此快速判定；也可在 site.cookies 直接粘贴整段会话 Cookie，全源请求自动携带。
3. API Key 登录：login.sendTokenAs 设为 "key"，用户在「源详情 → 登录」面板粘贴密钥，App 存本地密钥库，并在受保护请求上追加 Authorization: `<authScheme> <密钥>`（默认前缀 Key）。适合「登录给的是 access_token，但收藏 / 个人页却要单独 API Key」的站点（部分站点的新版 API 明确要求 Key `<api_key>`，而非 Bearer）。
- 令牌携带方式 login.sendTokenAs：null（只靠 Cookie）/ "bearer"（Authorization: Bearer `<checkCookie 对应 Cookie 值>`）/ "key"（Authorization: `<authScheme> <手动密钥>`，即 API Key 登录）。
- 登录态二次确认：login.checkUrl + login.loggedInSelector（GET checkUrl，选择器命中非空即视为登录有效）。

凭据只存本地，不会上传；未声明登录时，该源按「只读 / 免登录」处理。

| 字段 / 键 | 说明 |
| --- | --- |
| `network` | 源级代理 / DNS / Hosts / SNI / ECH 覆盖；缺省继承全局设置。 |
| `network.sni` | SNI 覆盖，如 { "enabled": true, "defaultSni": "-" }；- 为免 SNI，普通域名以该域名作 SNI，另可用 domainSni 做「域名→SNI」后缀通配。对直连 HTTPS 真实生效，走代理时不生效。 |
| `network.ech` | ECH 覆盖（如 { "enabled": true, "configs": [...] }）。由内置原生引擎驱动，对直连 HTTPS 真实生效；作用域分应用级 / 源级 / Bangumi 专用；当前随 Android（三架构）与 Windows 桌面端打包，macOS / Linux 暂未打包原生库自动降级。 |
| `comments.provider / routes / selectors` | 声明源站评论；routes.list 为必需（声明 comments 时），其余按需。 |
| `comments.login.url` | WebView 登录页地址；App 打开该页登录并捕获会话 Cookie（仅存本地）。 |
| `comments.login.checkCookie` | Cookie 登录：Cookie 中出现该键名即视为已登录（快速判断）。 |
| `comments.login.checkUrl / loggedInSelector` | 登录态二次探测：GET checkUrl，选择器命中非空即登录有效。 |
| `comments.login.sendTokenAs` | 令牌携带方式（登录类型）：null 只靠 Cookie；bearer → Authorization: Bearer `<checkCookie 的 Cookie 值>`；key → Authorization: `<authScheme> <手动密钥>`，即 API Key 登录。 |
| `comments.login.authScheme` | 仅 sendTokenAs==key 生效：Authorization 头前缀，默认 Key；站点要求 Token / Bearer 等前缀时改这里。 |
| `comments.login.apiKeyParam` | 仅 sendTokenAs==key 生效：密钥在本地密钥库的参数名，默认 apiKey（按 sourceId:apiKeyParam 存储）。 |
| `site.cookies` | 手动 Cookie 登录：把整段会话 Cookie 填到 site.cookies，全源请求自动携带。 |
| `生效优先级` | 用户覆盖 > 源 network 块 > 全局设置 > 默认值；改完即时生效，无需重启。 |

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
// 手动 Cookie 登录：直接在 site.cookies 粘贴整段会话 Cookie
"site": { "baseUrl": "https://example.com", "cookies": "sessionid=abc123; uid=42" }
// API Key 登录（同样写在 comments.login 段内）：sendTokenAs=key
"login": {
  "sendTokenAs": "key",    // 追加 Authorization: <authScheme> <用户粘贴的密钥>
  "authScheme": "Key",     // 默认 Key；站点要求其他前缀时改这里
  "apiKeyParam": "apiKey"  // 密钥存本地密钥库的参数名，默认 apiKey
}
```

##### 十五、源的猜你喜欢编写教程

「猜你喜欢」是详情页的推荐区块，用来展示「看了这部的人还看了什么」。给源加上它，用户不必退回搜索就能继续发现内容。

三种写法（按源类型选，也可并存）：

1. 推荐路由（推荐，影视 / 漫画 / 小说通用）：在 routes 里声明 recommend（优先）或 related，引擎打开详情时会带上 {id} 变量调用该接口，结果渲染成「猜你喜欢」区块；两者都未声明则不渲染该区块。
2. 漫画（mangaSource）：在 selectors.detail 里加 recommendations 对象，用 list / title / cover / url 从详情页直接抽取推荐列表（部分内置源采用此写法）。
3. 小说（Legado 兼容）：用 ruleBookInfo.recommendations 抽取推荐书名列表。

注意：推荐结果复用列表解析引擎，字段与 search / latest 一致（id / title / cover / detailUrl），多数情况下照抄 search 的 selectors 就能跑通。

| 字段 / 键 | 说明 |
| --- | --- |
| `routes.recommend` | 推荐接口（优先）：详情页打开时带 {id} 变量调用，结果渲染为「猜你喜欢」。 |
| `routes.related` | 备选推荐接口；未声明 recommend 时使用，行为一致。 |
| `selectors.recommend` | 推荐结果的抽取选择器（与 search / latest 同结构：list / title / cover / id）；未声明时复用 selectors.search。 |
| `selectors.detail.recommendations（漫画）` | 对象 { list, title, cover, url }，直接从详情页抽取推荐列表。 |
| `ruleBookInfo.recommendations（小说）` | Legado 兼容字段，推荐书名选择器。 |
| `不渲染条件` | recommend 与 related 都未声明时，详情页不显示推荐区块。 |

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

##### 十六、采集 API 接口说明

「采集 API」指的是一个源对外暴露的「抓取接口集合」——也就是 routes 里定义的一个个端点（search / latest / detail / video / images …），以及每个端点用 selectors 或 overrides 声明的抽取规则。App 的引擎按这套约定逐个调用端点、把站点数据变成统一结构。

端点与覆盖层：

- 每个端点先在 routes 里定义 url（支持 {keyword}/{page}/{id}/{url}/{detailUrl} 占位符）、method、responseType、headers、params。
- 占位符数值运算：数值型占位符支持 {page-1} / {page+1} / {page*30-30}（只支持 + - * / 后接非负整数，按书写顺序从左到右求值，不做优先级）；引擎统一从 1 开始计数，站点从 0 开始用 -1，JSON API 的 offset 分页用 {page*30-30} 一次算出偏移量；非数值占位符（如关键词）不处理，结果为负则夹到 0。
- 抽取方式由 parser.overrides.<端点> 决定：builtin / xpath / jsonpath / css / script / webview / webview-html。
- 声明式端点用 selectors.<端点> 指定选择器；脚本端点用 overrides.<端点>.script 提供函数。

异步协议 __meta：当端点需要先请求另一个接口才能解析（例如视频先调 API 拿真实地址），脚本返回 { __meta:true, __fetchUrl, __processor }。引擎会先预取 __fetchUrl，再把结果交给 __processor 同步处理。这是沙箱里唯一安全的异步通道。

常用端点一览：search（搜索）、latest（最新）、explore / category（发现/分类）、detail（详情+目录）、episodes（剧集列表）、video（视频地址）、chapters（漫画话列表）、images（漫画图片）、week（周更表）。具体字段名见各模块小节与「源字段速查」。

路由 body 与可选参数：端点可在 routes 里声明 body（POST/PUT 的请求体）与 headers；路径占位符支持可选写法 {k?}（命中时取该段、未命中则整段省去），便于适配「有时带分类、有时不带」的站点路由。

| 字段 / 键 | 说明 |
| --- | --- |
| `routes.<name>` | 端点地址与方法；占位符 {keyword}/{page}/{id}/{url} 自动替换。 |
| `parser.overrides.<name>` | 该端点的解析方式：builtin / xpath / jsonpath / css / script / webview / webview-html。 |
| `selectors.<name>` | 声明式端点的抽取选择器。 |
| `__meta 协议` | 脚本端点需要二次请求时返回 {__meta:true,__fetchUrl,__processor}。 |

```js
// 一个端点的完整声明（routes + overrides + selectors）
"routes": {
  "search": { "url": "/s?wd={keyword}&page={page}", "method": "get", "responseType": "json" }
},
"parser": { "type": "hybrid", "overrides": { "search": { "type": "jsonpath" } } },
"selectors": { "list": "$.list", "title": "$.vod_name", "cover": "$.vod_pic", "id": "$.vod_id" }

// 需二次请求的视频端点
function parseVideo(html, context){
  var api = extractApi(html);
  return { __meta: true, __fetchUrl: api, __processor: "__processVideo" };
}
function __processVideo(json, context){ return json.url; }
```

##### 十七、完整示例：小说源（Legado 兼容）

下面是一个完整可运行的小说源示例（Legado 兼容格式）。注意：小说源【不】使用 id / name / type / site 这些顶层字段，而是用 bookSourceName / bookSourceUrl / bookSourceType / ruleSearch / ruleToc / ruleContent / ruleBookInfo 等 Legado 字段；解析通过 parser.overrides.content 的脚本处理正文。把 example.com 换成真实站点、选择器换成真实规则即可导入。

```json
{
  "bookSourceName": "演示小说",
  "bookSourceUrl": "https://m.example.com",
  "bookSourceType": 0,
  "enabledExplore": true,
  "enabledSearch": true,
  "exploreUrl": "玄幻小说::https://m.example.com/xuanhuan/\n都市小说::https://m.example.com/dushi/",
  "bookSourceGroup": "内置书源",
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
  "bookSourceComment": "演示小说源，正文为纯 HTML"
}
```

##### 十八、完整示例：影视源（animeSource）

下面是一个完整可运行的影视源示例（animeSource）。影视源核心在 video 端点：这里用 webview 方式抽取真实播放地址（适合 m3u8 / 需执行页面 JS 才能拿到地址的站点）。注意 anime 源必须包含 latest 路由。把 example.com 换成真实站点即可导入。

```json
{
  "id": "demo_anime",
  "name": "演示影视",
  "version": 1,
  "type": "animeSource",
  "responseType": "json",
  "useWebview": true,
  "site": {
    "domain": "example.com",
    "baseUrl": "https://example.com",
    "mirrors": [ { "name": "主站", "domain": "example.com", "baseUrl": "https://example.com" } ]
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
  "category": { "categoryEntries": [ { "id": "all", "title": "全部" }, { "id": "1", "title": "动漫" } ] },
  "homeSections": [
    { "id": "latest", "title": "最新更新", "route": "latest", "style": "grid", "limit": 18 },
    { "id": "week", "title": "周更列表", "route": "week", "style": "schedule", "limit": 0, "more": false }
  ]
}
```

##### 十九、完整示例：漫画源（示例漫画 · mangaSource）

下面是以内置源「示例漫画」（demo.example）为蓝本的完整漫画源示例（mangaSource）。漫画源比影视/小说多两个关键端点：chapters（话列表）与 images（该话图片）。

要点：

- chapters 常需二次请求——脚本先取页面里的 data-mid，再返回 {__meta:true, __fetchUrl, __processor} 让引擎预取章节 API（本示例用 api.example.com），随后由 __processChapters 同步处理（异步约定见第十三节）。
- 图片地址通常加密：把解密逻辑写在 overrides.images.script 的 parseImages 里，返回图片 URL 数组。
- 分类标签（selectors.category.tags）的 id 是站点真实的 slug（如 古风=gufeng，无连字符），别自己发明。

为便于阅读，本示例把真实源里冗长的正则/解密脚本压缩成了骨架（直接导入会得到空结果），请把各 script 替换成真实解析逻辑后再使用。

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

##### 二十、调试与导入

写好后如何验证？

1. 用浏览器开发者工具（F12）核对真实页面的 HTML/JSON 结构与选择器是否匹配。
2. 在 App 内「导入源」粘贴 JSON，若解析失败，检查 JSON 格式（注意转义引号与换行）。
3. 脚本类源可在 overrides 里用 context.log() 打印中间结果辅助定位。
4. 先在本地用一份最小数据源跑通一个模块（如 search），再逐步补全 detail / video / images。
5. 分享：把 JSON 文件发给朋友，或提交到社区源仓库，别人一键导入即可。

| 字段 / 键 | 说明 |
| --- | --- |
| `导入方式` | App 内「源管理 / 导入源」→ 粘贴或选文件。 |
| `常见错误` | JSON 语法错误、选择器返回空、相对链接未补 baseUrl、脚本抛出异常。 |
| `版本升级` | 提高 version，同名源导入时自动覆盖旧版。 |

##### 二十一、源字段速查

下面按「顶层字段 / site / parser / routes / 选择器 / 高级块」给出一份较完整的字段速查。除 id、name、type、site、parser 外，其余字段均可选；源模型会忽略未知键（如 author / lang / builtin），请勿把它们当功能字段使用。

完整约束以仓库源码 lib/core/models/plugin_config.dart 为准，本表覆盖日常编写最常用的字段。

| 字段 / 键 | 说明 |
| --- | --- |
| `id` | 必填。源唯一标识（建议 域名_类型 之类，避免与他人重复）；同名源按 version 升级/跳过。 |
| `name` | 必填。展示名称。 |
| `version` | 整数版本号（默认 1）。导入时 ≥ 已装版本才覆盖，< 已装版本不覆盖（防误装旧版冲掉新源）。 |
| `type` | 必填。animeSource（影视/动漫）/ mangaSource（漫画）/ novelSource（小说）。 |
| `responseType` | 可选。json \| html，决定默认解析引擎；可被各路由的 responseType 覆盖。 |
| `useWebview` | 可选布尔。true 时该源整体用 WebView 渲染后抽取（适合强反爬站）。 |
| `site.domain` | 必填。站点主域名。 |
| `site.baseUrl` | 必填。站点根地址，用于拼接相对链接。 |
| `site.userAgent / cookies / headers` | 可选。全局请求 UA / Cookie / 自定义头。 |
| `site.mirrors[]` | 可选。镜像站列表，每项 {name, domain, baseUrl}。 |
| `site.publishPageUrl / publishMirrorSelector` | 可选。主域失效时的发布页与镜像提取规则（正则或 CSS）。 |
| `parser.type` | 必填。builtin / hybrid / script 三选一，决定整源默认解析方式。 |
| `parser.overrides.<api>` | 可选。按 API 指定解析方式：builtin / xpath / jsonpath / css / script / webview / webview-html。 |
| `parser.script / entrypoints` | 可选。script 模式下的 JS 源码与入口函数映射。 |
| `routes.<name>` | 可选。各接口地址，支持字符串写法或 {url, method, headers, params, responseType, parser} 对象；{keyword}/{page}/{id}/{url} 占位符自动替换。 |
| `selectors` | 可选。声明式选择器（JSONPath / CSS / XPath），与 parser.overrides 配合。 |
| `category.dynamicCategories / categoryEntries` | 可选。动态分类推断或静态分类表 [{id,title}]。 |
| `routes.categories` | 可选。动态分类接口：返回 [{id, title}]（script / jsonpath 皆可）。优先生效，请求失败自动回落 `categoryEntries`。 |
| `homeSections[]` | 可选。首页板块：{id, title, route, style, limit}；缺省回退单块「最新更新」。 |
| `filters` | 可选。动态筛选：groups（筛选组）、byCategory（按分类覆盖）、defaults（分类默认参数）。 |
| `stealthMode` | 可选布尔。开启更激进的反检测请求策略。 |
| `antiHotlinking.referer / headers / userAgent` | 可选。反盗链：补 Referer / 头 / 特定 UA。 |
| `mediaHostRewrite` | 可选。媒体域名改写映射 `{"原host": "目标host"}`（精确匹配，大小写不敏感）。封面等媒体 URL 的 host 按映射改写后再加载，适用于「签名 CDN 禁 Referer」「主 CDN 拒直连」等需要切换备用 CDN 的场景。 |
| `webviewConfig.adblock / timeoutSeconds` | 可选。WebView 广告拦截开关与超时（默认 true / 20s）。 |
| `comments` | 可选。评论配置：provider(source/bangumi)、routes(list 必需，replies/post/reply/like/report 可选)、selectors、login(url=WebView 登录页 + checkCookie=Cookie 键名 + checkUrl/loggedInSelector=登录态探测)。 |
| `network` | 可选。源级网络覆盖：proxy / dns / hosts / sni / ech；缺省继承全局，非法值只告警不阻断启用。（sni 与 ech 均对直连 HTTPS 真实生效） |
| `announcement` | 可选。源公告：{title, body?, url?, updatedAt?}。 |
| `webFavorite` | 可选。网络收藏：enabled / title / route / url / addRoute / addUrl / requireLogin；声明后在线浏览显示「网络收藏」Tab。 |
| `ageRating` | 可选。年龄分级：general(全年龄) / teen(青少年16+) / mature(成人18+)。兼容别名 all/16/r18/nsfw 等；缺省 general。mature 在默认设置下自动隐藏。 |
| `deprecated / migrationMessage` | 可选。标记弃用并给出迁移提示文案。 |
| `enabled / enabledExplore / isHidden` | 可选布尔。是否启用 / 是否出现在探索 / 是否隐藏。 |

```js
// 顶层字段骨架（仅示意，非完整源）
{
  "id": "demo_anime",
  "name": "演示动漫",
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

### 4.5.3 导入规则、补充说明与贡献

**导入与版本规则（务必注意）**：

- 源作者发新版，只需把 JSON 里的 `version` 调大；
- 导入同名（`id`）源时：版本 **≥ 已安装版本** → 替换（高版本升级 / 同版本重新导入以应用你的编辑）；版本 **< 已安装版本** → 跳过，防止误装旧版冲掉新源；
- 内置源不可被覆盖；导入时会保留原有的「启用 / 隐藏」状态。

**`comments` 子字段补充（v0.4.0 新增，全部可选）**：

| 字段 | 说明 |
| --- | --- |
| `comments.provider` | 默认 `source`（评论来自源站）。`bangumi` 目前**仅解析、未实现** |
| `comments.routes.list` | **必需**（声明 `comments` 时）；评论列表路由 |
| `comments.routes.replies` / `post` / `reply` / `like` / `report` | 可选；**未声明则对应按钮不渲染** |
| `comments.selectors` | `items` / `commentId` / `author` / `avatar` / `content` / `time` / `likeCount` / `replyCount` / `hasMore` / `success` 等 |
| `comments.login.url` | 需要登录时的 WebView 登录页地址 |
| `comments.login.checkCookie` | Cookie 中出现该键名即视为已登录 |
| `comments.login.checkUrl` + `loggedInSelector` | 可选的二次探测 |
| `comments.login.sendTokenAs` | 令牌携带方式（登录类型）：`null` 只靠 Cookie / `bearer` → `Authorization: Bearer <checkCookie 的 Cookie 值>` / `key` → `Authorization: <authScheme> <手动密钥>`（**API Key 登录**） |
| `comments.login.authScheme` | 仅 `sendTokenAs==key` 生效；`Authorization` 头前缀，默认 `Key` |
| `comments.login.apiKeyParam` | 仅 `sendTokenAs==key` 生效；密钥在本地密钥库的参数名，默认 `apiKey`（按 `sourceId:apiKeyParam` 存储） |

**批量预取多个页面（`__fetchUrls`）**：

脚本端点需要「逐个跟进 N 个页面」时（如画廊页只给缩略图入口，原图要进每个页面取），改用批量协议：引擎在 Dart 侧并发抓取，再一次性交回脚本同步处理。

```json
{
  "__meta": true,
  "__fetchUrls": ["/p/1", "/p/2", "/p/3"],
  "__fetchResponseType": "text",
  "__processor": "__processPages"
}
```

- `__fetchResponseType`：`json`（默认）/ `text`；
- `__fetchConcurrency`：并发数，默认 6、上限 16；
- `__fetchHeaders` / `__fetchMethod` / `__fetchBody`：附加请求头 / 方法（默认 `get`，可 `post`）/ POST 请求体；
- `__processor` 收到的是**按输入顺序**排列的响应数组；单条失败该位置为 `null`，不中断整批；
- 同一 `JsEngine` 实例内 `__meta` 支持链式多跳（上限 4 跳），顶层变量跨跳持续可见。

**贡献方式**：

1. 在自己的分支编写源 JSON，导入应用验证抓取是否正确；
2. 如需分享，通过社区渠道发布你的源 JSON（**请勿将源提交到本应用仓库**——仓库只托管引擎）；
3. 想改进引擎 / 阅读器 / 播放器 / 文档，欢迎提交 Issue 与 Pull Request。

> 共创的前提是**合规与尊重版权**：只解析你有权访问、且允许抓取的公开内容；不要将源用于侵犯他人合法权益的场景。

## 4.6 测试

```bash
flutter test
```

测试套件包含源 JSON 校验等；当本地没有内置源时，相关用例会自动跳过（契合开源无源模式）。
