#!/usr/bin/env bash
# 鸿蒙（OHOS）构建前置准备 —— 一条命令完成三件事：
#   1) 启用依赖覆盖模板（pubspec_overrides.yaml 被 .gitignore 忽略，模板随仓库提交）
#   2) 补入两条仅鸿蒙需要的直接依赖（media_kit_libs_ohos / flutter_secure_storage_ohos）
#   3) 应用鸿蒙专属源码补丁 tool/ohos/ohos_src.patch
#        · RSS 通知的 ohos 平台参数与类型
#        · 画中画 EnableManual（官方包为 ImmediatePiP）
#
# 官方 Flutter SDK 构建（Android / Windows / Linux / macOS / iOS）**不需要**执行本脚本。
# 恢复官方干净状态（如需）：
#   git checkout -- pubspec.yaml lib/core/rss/rss_notification_service.dart \
#       lib/features/player/presentation/video_player_cast_pip.dart
#   rm -f pubspec_overrides.yaml && git checkout -- pubspec.lock
set -euo pipefail
cd "$(dirname "$0")/../.."

cp pubspec_overrides.ohos.yaml pubspec_overrides.yaml

PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
"$PY" - <<'PYEOF'
import io
import re

p = "pubspec.yaml"
d = io.open(p, encoding="utf-8").read()
# 注释里也写了这两个包名，不能用全文件字符串判断（曾因此漏加依赖 →
# GeneratedPluginRegistrant 缺 FlutterSecureStorageOhosPlugin → 启动 MissingPluginException）。
if not re.search(r"^  media_kit_libs_ohos:", d, re.M):
    d = d.replace(
        "  media_kit_libs_video: ^1.0.7\n",
        "  media_kit_libs_video: ^1.0.7\n  media_kit_libs_ohos: ^1.0.0\n", 1)
if not re.search(r"^  flutter_secure_storage_ohos:", d, re.M):
    d = d.replace(
        "  flutter_secure_storage: ^9.0.0\n",
        "  flutter_secure_storage: ^9.0.0\n"
        "  flutter_secure_storage_ohos:\n"
        "    git:\n"
        "      url: https://gitcode.com/CPF-Flutter/fluttertpc_flutter_secure_storage.git\n"
        "      path: flutter_secure_storage_ohos\n"
        "      ref: br_v9.2.4_ohos\n", 1)
io.open(p, "w", encoding="utf-8", newline="").write(d)
PYEOF

if git apply --check tool/ohos/ohos_src.patch 2>/dev/null; then
  git apply tool/ohos/ohos_src.patch
  echo "::notice::ohos src patch applied"
else
  echo "::warning::ohos src patch already applied or drifted"
fi

echo "::notice::OHOS prepare done (overrides + deps + src patch)"
