# 段评实机核对步骤

面向真机（Android / 鸿蒙手机或平板）。电脑只用来跑 mock 站与看日志。

---

## 0. 准备（5 分钟）

### 0.1 让手机能访问电脑的 8765（三选一）

**A. 鸿蒙真机（推荐，免管理员、免同网）：hdc 端口反连**

```powershell
$hdc = "D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc list targets          # 应看到设备号
& $hdc rport tcp:8765 tcp:8765
& $hdc fport ls              # 应看到 tcp:8765 tcp:8765 [Reverse]
```

之后手机里访问 `127.0.0.1:8765` 就是本机 —— **测试源不用改 IP**。
重插 USB / hdc 重启后要重跑一次 `rport`。

**B. Android（USB）：adb reverse**

```powershell
adb devices
adb reverse tcp:8765 tcp:8765
```

**C. 无线（局域网 IP）：需要管理员放行防火墙**

```powershell
Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Format-Table InterfaceAlias, IPAddress -AutoSize
```

```powershell
# 管理员 PowerShell 里跑
New-NetFirewallRule -DisplayName 'NexHub mock 8765' -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow -Profile Private
```

用这种方式时，测试源里的 `127.0.0.1:8765` 要换成上表的局域网 IP。

### 0.2 起 mock 站（单独开一个 PowerShell 窗口，保持不关）

```powershell
Set-Location E:\nexhub
python tool/dev/mock_review_server.py
```

看到 `段评 mock 站已启动` 即成功。首次运行若弹 Windows 防火墙提示，点「允许专用网络」。

### 0.3 本机自测

```powershell
(Invoke-WebRequest "http://127.0.0.1:8765/book/1" -UseBasicParsing).StatusCode   # 期望 200
```

### 0.4 装包（鸿蒙：构建 + 安装）

```powershell
Set-Location E:\nexhub
. .\_ohos_env.ps1
flutter build hap --debug --target-platform ohos-arm64
# 产物：E:\nexhub\build\ohos\hap\entry-default-signed.hap

$hdc = "D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc install -r "E:\nexhub\build\ohos\hap\entry-default-signed.hap"
```

> 若构建报 `SAFE_DELETE_BULK_CONFIRM_REQUIRED`（flutter_assets 批量替换被拦），
> 先删掉旧的资产目录再重建：
> `node -e "require('fs').rmSync('ohos/entry/src/main/resources/rawfile/flutter_assets',{recursive:true,force:true})"`

Android 设备改用 `flutter run -d <设备ID>` 即可。

---

## 1. 导入测试源

**走方案 A/B（端口反连）时源不用改**，直接复制原始文件内容：

```powershell
Get-Content 'E:\nexhub\tool\dev\mock_review_source.json' -Raw -Encoding utf8 | Set-Clipboard
"已复制到剪贴板（127.0.0.1:8765）"
```

**走方案 C（局域网 IP）时**改成电脑 IP 再复制：

```powershell
$src = 'E:\nexhub\tool\dev\mock_review_source.json'
$dst = Join-Path $env:TEMP 'mock_review_source.local.json'
(Get-Content $src -Raw -Encoding utf8).Replace('127.0.0.1:8765', "192.168.137.1:8765") |
  Set-Content $dst -Encoding utf8 -NoNewline
Get-Content $dst -Raw | Set-Clipboard
"已生成 $dst ，内容已复制到剪贴板"
```

> 正文图标里的点击地址由服务端按请求 Host 自动生成，不用改。

然后：App → **设置 → 源管理 → 导入 → 粘贴 JSON**（也可导入文件）。
预期：源列表出现「本地段评演示(mock)」，状态为启用、类型小说。

> 若导入后显示「已存在/版本相同跳过」，先在源管理里删掉旧的那条再导。



---

## 2. 打开章节

**在线浏览 → 小说 → 选「本地段评演示(mock)」→ 搜索 → 输入 `河岸` → 点「河岸手记」→ 目录 → 第一章 起点**

- 也支持：书源内搜索直接输任意关键词（mock 忽略关键词，固定返回这一本）。
- 预期：正文 12 段，标题为「第一章 起点」。

---

## 3. 逐项核对

| #    | 操作                           | 预期结果                                       | 不符时看                           |
| ---- | ---------------------------- | ------------------------------------------ | ------------------------------ |
| 3.1  | 打开第 1 章                      | 正文 12 段，排版正常                               | `[书源重放]` 日志、`[书源正文]`           |
| 3.2  | 看第 2 段末尾                     | **没有裂图**；有一个小圆角图标（内置图标，非源 SVG）             | 若出现裂图占位 → B 路径剥离未生效            |
| 3.3  | 点 3.2 的小图标                   | 打开应用内浏览器，页面标题「段评（源内嵌页）」                    | `[书源动作]`、`browserOpen`         |
| 3.4  | 看第 1/3/5 段末尾                 | 各有一个气泡，数字都是 `2`                            | `[段评] 气泡计数`                    |
| 3.5  | 三点菜单 →「段评」                   | 面板打开，6 条段评（头像/时间/正文），底部有输入框                | `[段评] 列表`                      |
| 3.6  | 关闭面板 → **长按第 4 段** → 工具栏「段评」 | 面板打开且选中「第 4 段」；点「全章」能切回 6 条                | 段号 = 块下标 + 1                   |
| 3.7  | 输入 `测试中文发帖` → 发送             | 提示「已发布」；列表出现该条；关面板后对应段气泡数字 +1              | 服务端日志应有 `POST /api/review/add` |
| 3.8  | 点某条的「回复」→ 输入 `收到` → 发送       | 该条下方展开区出现「收到」                              | `POST /api/review/quote`       |
| 3.9  | 点「赞」                         | 提示成功（文案为「已发布」）；服务端 `POST /api/review/vote` | —                              |
| 3.10 | 点「删除」→ 确认                    | 该条消失；气泡数字减 1                               | `POST /api/review/delete`      |
| 3.11 | 切到第二章                        | 无气泡；面板显示「本章还没有段评」                          | —                              |
| 3.12 | 阅读设置里切「翻页」模式，回第 1 章          | 气泡/图标出现在**段末行右侧余白**，不压字、不出屏                | 若挂错段 → 坐标映射问题                  |

> 3.7 / 3.10 会改动服务端内存数据，重启 mock 服务即恢复（Ctrl+C 后重新起）。

---

## 4. 真实源回归（可选，10 分钟）

本机源库（`墨辰整理书源大全7.5….json`）里有 3 个真实的「内嵌图标」源：  
洋柿子酱、七猫官方、七猫聚合。

1. 导入其中任意一个，随便开一章有正文的书。
2. 核对：
   - [ ] 段评图标**不再裂图**（会显示为内置小图标）
   - [ ] 点图标：能打开应用内浏览器（或至少不闪退/不无响应）
3. 已知限制（**不算 bug**）：源自带页面若依赖 `window.java` 桥继续取数，可能空白。  
   这类源需要改成直连接口，见 `docs/developer-guide.md` 第六（附）节。

---

## 5. 出问题时抓什么

| 现象           | 抓取内容                             |
| ------------ | -------------------------------- |
| 面板空 / 提示加载失败 | App 运行日志里 `[段评]` 开头的行（含 URL 与异常） |
| 图标点击无反应      | `[书源动作]`、`[书源重放]` 尾部 20 行        |
| 气泡挂错段 / 位置偏  | 截图 + 阅读模式（滚动/翻页）+ 字号 + 是否有插图     |
| 发帖/删除无效      | 服务端控制台日志（有没有收到对应 POST）+ 面板提示文案   |

日志（App 内「设置 → 关于/诊断 → 运行日志」也能看）：

```powershell
adb devices
adb logcat | Select-String '段评|书源动作|书源重放|browserOpen'
```

回传请附：源名、章节 URL、上述日志片段、录屏（10 秒即可）。

---

## 6. 收尾

```powershell
# 方式一：在跑 mock 的窗口按 Ctrl+C
# 方式二：任意窗口强停
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -like '*mock_review_server*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# 撤掉端口反连
$hdc = "D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
& $hdc fport rm "tcp:8765 tcp:8765"
# Android: adb reverse --remove tcp:8765

# 可选：清理临时源文件与防火墙规则
Remove-Item (Join-Path $env:TEMP 'mock_review_source.local.json') -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName 'NexHub mock 8765' -ErrorAction SilentlyContinue
```

- 删掉测试源（源管理 → 长按 → 删除），避免影响日常书源列表。
