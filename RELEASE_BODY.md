# NexHub v4.0.0-beta.1（预发布测试版）

> 四合一媒体聚合客户端（动漫 / 漫画 / 小说 / 影视）—— 源即插件 · 共创社区。

---

## 🧪 这是 4.0 的第一个公开测试版

这个 beta 的主角是**书源兼容层**：把 Legado 风格书源的导入、规则求值、发现页、登录与多类型分发整套打通。相对 v3.6.0 共 42 个提交，几乎都集中在这条线。

> - **本次发布的是 `feature/legado-booksource-compat` 分支**，尚未合并进主分支；产物从该分支构建，版本号为 v4.0.0-beta.1。
> - **兼容性**：现有源、书架 / 收藏 / 阅读进度不受影响；兼容能力依据源文件声明自动识别，不需要你手动改旧源。
> - **测试版提醒**：新规则引擎覆盖面大，个别非常规源仍可能解析失败；遇到请保存应用内「运行日志」反馈，便于定位。

> ⚠️ **本应用不内置任何内容源**，首次打开是空的，这是正常现象。请先导入至少一个源 JSON 才能看到内容。源由社区共享维护，请自行评估其合规性与内容合法性。

---

## ✨ 本次更新内容

### 🧩 书源兼容：导入保真 + 规则引擎

- **导入保真**：书源里的 `ruleData` / `jsLib` 等字段不再被丢弃；源变量并入源管理并可持久化，重启后脚本变量仍在。
- **规则语法对齐**：ElementsSingle（下标 / 排除 / 区间 / `tag.` `class.` `id.` `text.` 前缀）、XPath（谓词 / 并集 / 复合规则）、JSONPath 全集、`textNodes` 逐文本节点语义、`replaceRegex` 多形态、`@js:` 内嵌脚本展开、`@put` 无括号写法、`bookUrlPattern` 语义；正则方言（内联标志、`\Q..\E`、占有量词、原子分组）就地翻译。
- **详情 / 目录 / 正文**：修正 baseUrl 分工、后处理时序、简介缺失、目录错序等一批语义差异；媒体直链按 legado 语义直接作为正文处理。

### ☕ `java.*` 规则桥

- **Java 互操作**：纯 JS 实现 `Packages` / `JavaImporter`，覆盖 Cipher / Base64 / Arrays / String / hutool / GZIP / okhttp3 / Jsoup 等高频类；未注册的类保持报错，不伪造结果。
- **加密与摘要**：AES（ECB/CBC + PKCS5/7）、DES / 3DES、SHA / HMAC、RSA 常用路径（`createAsymmetricCrypto` + SPKI/PKCS#8 解析），分块与 hex/base64 识别；OAEP / EC / CTR / GCM 等未支持形态明确返回空。
- **字体还原**：`queryTTF` / `replaceFont` 纯 JS 解析 sfnt 字形表，还原被字体混淆的字符。
- **网络族**：`java.ajax/get/post/head` 支持自定义头、`followRedirects:false`、`StrResponse` 超集（body / code / headers / cookies / url / isSuccessful / raw 等），播放地址与 API 类源不再因读响应元数据而崩。
- **动态规则重放**：`java.*` 由确定性重放协议支撑（记录调用 → 宿主求值 → 回填缓存 → 重跑，最多 4 轮），settle 上限提到 16 轮 / 120 秒，多跳脚本能收敛。

### 🔎 发现页与分类

- **源行内嵌选项栏**：对齐 ExploreKind 的 url / text / button / toggle / select 六类选项，值按源持久化；点击分类直达对应标签页。
- **分类更全**：动态分类脚本支持占位符抓取后重放，跨页去重、空页自动连翻，首个分类失效有兜底；GSON 宽松解析修复了 29 个源的分类缺失。

### 📺 多类型书源分发

- `bookSourceType=2`（图片 / 漫画）自动接入漫画模块，`images` 走适配后的正文管线；音频 / 视频源落入媒体栏，阅读器里出现章节播放卡片，播放优先确定性解析直链，不再等 15 秒嗅探；相关章节文案已补中英本地化。

### 🔐 登录与请求语义

- **登录三件套**：`loginCheckJs` 消费、WebView 登录、`loginUi` 表单；登录脚本进入上下文作用域，表单值可被规则读取，失败不再假报成功。
- **WebView 取数**：新增无头 WebView 取源器（`java.webView` 与 URL 选项 `webView:true`），`webJs` 可在 WebView 内执行并把结果回灌给规则解析；反爬路由会把 `sourceRegex` 一并喂入，避免校验页解析落空。
- **Cookie / Referer**：响应 `Set-Cookie` 按源落库并自动回放；请求头对齐 legado——默认不再兜底注入 Referer（图片同样处理），存量 Referer 做迁移，带 `##` 后缀的源不再全链路失败。
- **上下文隔离**：规则上下文改为 Zone 传递，修复 `await` 之后上下文丢失与多源并发串上下文；cookie host 改为 domain-match，仿冒域不再收走登录 cookie；删除源时释放池化引擎并清理该源 cookie / 变量。

### 🧪 测试与已知限制

- 书源兼容测试套件 **84/84** 通过，另含桥 / 上下文 / 正则兼容层测试与独立校验脚本。
- 少数 Java API（约 2.6% 调用 / 3% 源）尚未覆盖；不支持的形态一律明确降级，不会给出错误结果。
- WebView 相关路径（无头取源、webJs、登录表单）需要更多真机环境验证；遇到问题请优先反馈应用内运行日志。

---

## ⬆️ 安装与升级

- 本版是分支 beta，Android / Windows / Linux / macOS / iOS / 鸿蒙产物发布在同一个预发布 Release 下。
- 沿用同一签名密钥，可直接覆盖安装。鸿蒙 HAP 依旧不带签名，需自行签名后侧载。

## 📄 免责声明

- NexHub 不内置任何内容源，所有内容均来自你自行导入的「源」；请在导入前自行确认来源的合法性与安全性，使用产生的风险由用户自行承担。
