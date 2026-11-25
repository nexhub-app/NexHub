#!/usr/bin/env python3
"""段评联调用的本地 mock 站（只依赖标准库）。

用途：没有真实段评源时，在本机起一个「小说站 + 段评接口」，配合
`tool/dev/mock_review_source.json` 验证书架在线阅读器的段评能力：
面板列表、全章/本段切换、发帖、回复、赞/踩、删除、正文段尾气泡，
以及「源内嵌图标 + 点击动作（java.showBrowser）」这条原生路径。

用法：
    python tool/dev/mock_review_server.py [--port 8765] [--host 0.0.0.0]

- 手机走端口反连（hdc rport / adb reverse）时：源里用 127.0.0.1:8765
- 走局域网时：把源里的 host 换成电脑 IP
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

# ── 数据 ──────────────────────────────────────────────────────────────────
# 段评按章节存：章 id → [条目]。p 是**正文段落序号**（0 起，插图不算），
# 与本项目阅读器的段评锚点口径一致。
_REVIEWS: dict[int, list[dict]] = {
    1: [
        {"id": 0, "p": 0, "user": "读者甲", "time": "3 分钟前",
         "content": "开篇这句就把人拽进去了。", "up": 2, "down": 0, "replies": []},
        {"id": 1, "p": 0, "user": "读者乙", "time": "5 分钟前",
         "content": "文笔很稳，追了。", "up": 1, "down": 0, "replies": []},
        {"id": 2, "p": 2, "user": "读者丙", "time": "10 分钟前",
         "content": "这里的伏笔后面会收吗？", "up": 0, "down": 1,
         "replies": ["会收，作者埋了两处。", "同问，看到后面就懂了。",
                     "第三处也有线索。"]},
        {"id": 3, "p": 2, "user": "读者丁", "time": "12 分钟前",
         "content": "第三段节奏突然快了。", "up": 4, "down": 0, "replies": []},
        {"id": 4, "p": 4, "user": "读者戊", "time": "1 小时前",
         "content": "这段对话写得好。", "up": 0, "down": 0, "replies": []},
        {"id": 5, "p": 4, "user": "读者己", "time": "2 小时前",
         "content": "笑死，这俩人绝了。", "up": 6, "down": 0, "replies": []},
    ],
    # 第二章刻意没有段评：用于验证「换章后气泡与面板都清空」。
    2: [],
}

_CHAPTERS = [
    {"id": 1, "title": "第一章 起点", "paragraphs": [
        "夜色落在旧城的屋脊上，像谁把一层灰布轻轻盖了下来。",
        "林昭站在巷口，手里的车票被汗浸得有些软。",
        "他数过这条巷子里的灯，一共七盏，今晚只剩四盏亮着。",
        "风从身后追上来，带着河水的腥气。",
        "「再等五分钟。」他对自己说。",
        "五分钟里，没有人经过。",
        "第八分钟，一辆黑色的车停在巷子另一头。",
        "车门开了一半，又关上。",
        "林昭把车票塞回口袋，转身往河边走。",
        "他听见自己的脚步声在墙上弹回来，一下，又一下。",
        "河面比想象中安静。",
        "远处有人在收网，网绳绷紧的声音很轻。",
    ]},
    {"id": 2, "title": "第二章 河岸", "paragraphs": [
        "河岸的石阶长了青苔，踩上去有些滑。",
        "林昭在第三级台阶坐下，把鞋脱了。",
        "水很凉，凉得让人清醒。",
        "他想起很多年前，也是这样的夜。",
    ]},
]

_LOCK = threading.Lock()
_AVATAR_PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAF0lEQVQoU2NkYGD4z0AEYBxV"
    "SFKgAgYGBgYA1QAB0kGmXwAAAABJRU5ErkJggg=="
)
_BUBBLE_SVG = (
    '<svg xmlns="http://www.w3.org/2000/svg" width="44" height="28" '
    'viewBox="0 0 44 28"><rect x="1" y="1" width="42" height="26" rx="8" '
    'fill="#4f6bed" stroke="#dbe4ff"/><text x="22" y="19" '
    'text-anchor="middle" font-family="sans-serif" font-size="13" '
    'fill="#fff">评</text></svg>'
)
_CHAPTER_URL_RE = re.compile(r"/book/\d+/(\d+)\.html")


def _chapter_id(query: dict) -> int:
    """从 chapterUrl（优先）或 chapterId 解析章节号。"""
    raw_url = (query.get("chapterUrl") or [""])[0]
    m = _CHAPTER_URL_RE.search(raw_url)
    if m:
        return int(m.group(1))
    try:
        return int((query.get("chapterId") or ["1"])[0])
    except ValueError:
        return 1


def _bubble_data_uri(origin: str) -> str:
    encoded = base64.b64encode(_BUBBLE_SVG.encode("utf-8")).decode("ascii")
    click = "java.showBrowser('%s/panel', '')" % origin
    options = json.dumps({"style": "TEXT", "click": click}, ensure_ascii=False)
    return f"data:image/svg+xml;base64,{encoded},{options}"


def _page(title: str, body: str) -> bytes:
    return (
        "<!doctype html><html><head><meta charset='utf-8'>"
        f"<title>{title}</title>"
        "<style>body{font:16px/1.7 system-ui,'Segoe UI',sans-serif;"
        "max-width:760px;margin:24px auto;padding:0 16px;color:#222}"
        "h1{font-size:20px}a{color:#2f6fed}"
        ".muted{color:#888;font-size:13px}</style></head>"
        f"<body>{body}</body></html>"
    ).encode("utf-8")


def _reviews_html(items: list[dict]) -> str:
    rows = []
    for r in items:
        replies = "".join(
            "<div class='reply'><span class='rcontent'>%s</span></div>" % x
            for x in r["replies"]
        )
        rows.append(
            "<div class='rv' data-p='%d' data-id='%d'>"
            "<div class='avatar'><img src='/avatar.png'></div>"
            "<div class='body'>"
            "<div class='time'>%s</div>"
            "<div class='content'>%s</div>"
            "<div class='meta'>"
            "<span class='up'>%d</span><span class='down'>%d</span>"
            "</div>"
            "<div class='replies'>%s</div>"
            "</div></div>"
            % (r["p"], r["id"], r["time"], r["content"], r["up"], r["down"], replies)
        )
    return "<h1>本章段评</h1>" + ("".join(rows) or "<div class='muted'>暂无段评</div>")


class Handler(BaseHTTPRequestHandler):
    server_version = "NexHubMockReviews/2.0"

    def log_message(self, fmt: str, *args) -> None:
        print(f"  {self.command} {self.path}")

    # ── 工具 ──
    def _send(self, body: bytes, ctype: str = "text/html; charset=utf-8",
              code: int = 200) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj) -> None:
        self._send(json.dumps(obj, ensure_ascii=False).encode("utf-8"),
                   "application/json; charset=utf-8")

    def _form(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode("utf-8", "replace") if length else ""
        return {k: v[0] for k, v in parse_qs(raw).items()}

    # ── GET ──
    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path == "/":
            self._send(_page("mock", "<h1>段评 mock 站</h1>"
                             "<p><a href='/book/1'>书籍详情</a></p>"
                             "<p class='muted'>配合 tool/dev/mock_review_source.json 使用</p>"))
            return
        if path == "/search":
            keyword = (query.get("q") or [""])[0]
            self._send(_page("搜索", "<h1>搜索：%s</h1><ul id='list'>"
                            "<li><a href='/book/1'>河岸手记</a>"
                            "<span class='author'>作者：示例</span></li></ul>"
                            % (keyword or "（空）")))
            return
        if path == "/avatar.png":
            self._send(_AVATAR_PNG, "image/png")
            return
        if path == "/panel":
            self._send(_page("段评", "<h1>段评（源内嵌页）</h1>"
                            "<p>这个页面由书源 click 脚本通过 "
                            "<code>java.showBrowser</code> 打开，"
                            "用于验证「内嵌图标 + 点击动作」这条原生路径。</p>"))
            return
        if path == "/book/1":
            self._send(_page("书籍", "<h1>河岸手记</h1><p class='muted'>作者：示例</p>"
                            "<p>一本用来联调段评的假书。</p>"
                            "<p><a href='/book/1/toc'>查看目录</a></p>"))
            return
        if path == "/book/1/toc":
            links = "".join(
                "<li><a href='/book/1/%d.html'>%s</a></li>" % (c["id"], c["title"])
                for c in _CHAPTERS
            )
            self._send(_page("目录", "<h1>目录</h1><ul id='list'>%s</ul>" % links))
            return
        if path.startswith("/book/1/") and path.endswith(".html"):
            try:
                cid = int(path.rsplit("/", 1)[-1].split(".")[0])
            except ValueError:
                self._send(_page("404", "<h1>404</h1>"), code=404)
                return
            chapter = next((c for c in _CHAPTERS if c["id"] == cid), None)
            if chapter is None:
                self._send(_page("404", "<h1>404</h1>"), code=404)
                return
            origin = "http://%s" % (self.headers.get("Host") or "127.0.0.1:8765")
            bubble = _bubble_data_uri(origin)
            parts = []
            for i, p in enumerate(chapter["paragraphs"]):
                # 第 1 章第 2 段末尾放一个「内嵌可点击图标」，验证源原生气泡路径；
                # 第 2 章不放（用来验证「无图标、无段评」的干净章）。
                tail = ("<img src=\"%s\">" % bubble) if (cid == 1 and i == 1) else ""
                parts.append("<p>%s%s</p>" % (p, tail))
            self._send(_page(chapter["title"],
                             "<h1>%s</h1><div id='chapter'>%s</div>"
                             % (chapter["title"], "".join(parts))))
            return
        if path == "/api/reviews":
            cid = _chapter_id(query)
            pid_raw = (query.get("pid") or [""])[0]
            with _LOCK:
                items = [dict(r) for r in _REVIEWS.get(cid, [])]
            if pid_raw:
                try:
                    target = int(pid_raw)
                except ValueError:
                    target = -1
                item = next((r for r in items if r["id"] == target), None)
                rows = [] if item is None else [
                    {"id": i, "p": item["p"], "time": "%d 分钟前" % (i + 1),
                     "content": x, "up": 0, "down": 0, "replies": []}
                    for i, x in enumerate(item["replies"])
                ]
                self._send(_reviews_html(rows).encode("utf-8"))
                return
            self._send(_reviews_html(items).encode("utf-8"))
            return
        self._send(_page("404", "<h1>404</h1>"), code=404)

    # ── POST ──
    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        form = self._form()

        def _int(v, default=-1):
            try:
                return int(v)
            except (TypeError, ValueError):
                return default

        with _LOCK:
            if path == "/api/review/add":
                cid = _chapter_id(form)
                items = _REVIEWS.setdefault(cid, [])
                p = _int(form.get("p"), 0)
                content = (form.get("content") or "").strip() or "（空）"
                items.append({
                    "id": (max((r["id"] for r in items), default=-1) + 1),
                    "p": p, "user": "我", "time": "刚刚",
                    "content": content, "up": 0, "down": 0, "replies": [],
                })
                self._json({"code": 0})
                return
            if path == "/api/review/quote":
                cid = _chapter_id(form)
                rid = _int(form.get("id"))
                text = (form.get("content") or "").strip() or "（空）"
                item = next((r for r in _REVIEWS.get(cid, []) if r["id"] == rid), None)
                if item is None:
                    self._json({"code": 1, "msg": "not found"})
                    return
                item["replies"].append(text)
                self._json({"code": 0})
                return
            if path == "/api/review/vote":
                merged = {**query, **form}
                cid = _chapter_id(merged)
                rid = _int((merged.get("id") or ["-1"])[0])
                kind = (merged.get("type") or ["up"])[0]
                item = next((r for r in _REVIEWS.get(cid, []) if r["id"] == rid), None)
                if item is None:
                    self._json({"code": 1, "msg": "not found"})
                    return
                if kind == "down":
                    item["down"] += 1
                else:
                    item["up"] += 1
                self._json({"code": 0})
                return
            if path == "/api/review/delete":
                merged = {**query, **form}
                cid = _chapter_id(merged)
                rid = _int((merged.get("id") or ["-1"])[0])
                items = _REVIEWS.get(cid, [])
                for i, r in enumerate(items):
                    if r["id"] == rid:
                        items.pop(i)
                        self._json({"code": 0})
                        return
                self._json({"code": 1, "msg": "not found"})
                return
        self._json({"code": 404})


def main() -> None:
    parser = argparse.ArgumentParser(description="段评 mock 站")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"段评 mock 站已启动：http://127.0.0.1:{args.port}")
    print(f"  书籍详情  http://127.0.0.1:{args.port}/book/1")
    print(f"  段评接口  http://127.0.0.1:{args.port}/api/reviews?chapterUrl=/book/1/1.html")
    print("  第 1 章 6 条段评（第 1/3/5 段各 2 条），第 2 章无段评")
    print("  Ctrl+C 结束；数据存内存，重启即恢复预置。")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
