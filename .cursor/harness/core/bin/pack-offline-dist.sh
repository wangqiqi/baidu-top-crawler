#!/usr/bin/env bash
# 母版离线分发包：staging → tar.gz + 同级 USAGE.md / USAGE.html → .growing/offline-dist/
# 不含 .git · .growing · node_modules；可选脱敏 URL 与绝对 home 路径。
set -euo pipefail

usage() {
  cat <<EOF
用法: $0 [母版仓库根] [选项]

默认母版根：SUPER_CURSOR_HOME / 脚本向上探测含 .cursor/harness/core 的目录。

产出目录（git 忽略）: <母版>/.growing/offline-dist/
  <name>.tar.gz
  <name>-USAGE.md
  <name>-USAGE.html

选项:
  --output-dir <dir>     覆盖默认 .growing/offline-dist
  --strip-urls           文本文件中移除 http(s) URL（保留可读性，链到 offline 占位）
  --strip-home           将本机 \$HOME 前缀替换为 ~/
  --name <basename>      覆盖自动生成的包名（默认 super-cursor-<version>-<timestamp>）
  -h, --help

入口: bash install-super-cursor.sh --pack-offline [选项]
EOF
}

resolve_mother_root() {
  local arg="${1:-}"
  if [[ -n "$arg" && "$arg" != -* && -d "$arg/.cursor/harness/core" ]]; then
    echo "$(cd "$arg" && pwd)"
    return 0
  fi
  local candidate
  for candidate in "${SUPER_CURSOR_HOME:-}" "${CURSOR_AI_HOME:-}"; do
    if [[ -n "$candidate" && -d "$candidate/.cursor/harness/core" ]]; then
      echo "$(cd "$candidate" && pwd)"
      return 0
    fi
  done
  local walk
  walk="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [[ "$walk" != "/" ]]; do
    if [[ -d "$walk/harness/core" ]]; then
      echo "$(cd "$walk/.." && pwd)"
      return 0
    fi
    walk="$(dirname "$walk")"
  done
  echo "错误: 未找到母版 .cursor/harness/core" >&2
  return 1
}

changelog_version() {
  local cl="$1/CHANGELOG.md"
  [[ -f "$cl" ]] || { echo "0.0.0"; return 0; }
  sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' "$cl" | grep -v Unreleased | head -1
}

MOTHER=""
STRIP_URLS="false"
STRIP_HOME="false"
OUTPUT_DIR=""
NAME_OVERRIDE=""

args=("$@")
if [[ ${#args[@]} -gt 0 && "${args[0]}" != -* ]]; then
  MOTHER="$(resolve_mother_root "${args[0]}")" || exit 1
  set -- "${args[@]:1}"
else
  MOTHER="$(resolve_mother_root "")" || exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --strip-urls) STRIP_URLS="true"; shift ;;
    --strip-home) STRIP_HOME="true"; shift ;;
    --output-dir)
      [[ $# -ge 2 ]] || { echo "错误: --output-dir 需要路径" >&2; exit 1; }
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || { echo "错误: --name 需要 basename" >&2; exit 1; }
      NAME_OVERRIDE="$2"
      shift 2
      ;;
    *)
      echo "错误: 未知选项 $1" >&2
      usage
      exit 1
      ;;
  esac
done

# shellcheck source=../lib/platform.sh
source "$MOTHER/.cursor/harness/core/lib/platform.sh"

VER="$(changelog_version "$MOTHER")"
STAMP="$(date +%Y%m%d_%H%M%S)"
BASE="${NAME_OVERRIDE:-super-cursor-${VER}-${STAMP}}"
OUT="${OUTPUT_DIR:-$MOTHER/.growing/offline-dist}"
mkdir -p "$OUT"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/sc-pack.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

ROOT="$STAGING/$BASE"
mkdir -p "$ROOT"

# rsync -a（勿 -L）：保留 .cursor → harness/core 相对 symlink，避免 skills/templates 双份
pack_rsync_excludes=(
  ".git"
  ".growing"
  ".cursorGrowth"
  ".cursor-plugin"
  ".github"
  "/docs"
  "node_modules"
  "/archive"
  "/learn"
  "/plan.md"
  "/onekey_start.sh"
  "package.json"
  "package-lock.json"
  "CHANGELOG.md"
  "/AGENTS.md"
  ".gitattributes"
  "*.log"
  ".DS_Store"
)

if command -v rsync >/dev/null 2>&1; then
  rsync_args=(-a)
  local_ex=""
  for local_ex in "${pack_rsync_excludes[@]}"; do
    rsync_args+=(--exclude "$local_ex")
  done
  rsync "${rsync_args[@]}" "${MOTHER}/" "${ROOT}/"
else
  echo "WARN: 无 rsync，回退 sc_copy_tree（会展开 symlink · 体积变大）" >&2
  sc_copy_tree "$MOTHER" "$ROOT" "${pack_rsync_excludes[@]}"
fi

rm -rf "$ROOT/.git" 2>/dev/null || true

# 消费端不需要：母版组装 / 全量 verify / CI smoke / 插件轨 / 再次打包
sc_pack_prune_consumer() {
  local root="$1"
  local core="$root/.cursor/harness/core"
  local pack_bin="$root/.cursor/bin"
  local cur_bin="$core/bin"
  local cur_adaptor_bin="$root/.cursor/adaptors/cursor/bin"

  rm -f "$root/.cursor/harness/assemble.sh" "$root/.cursor/harness/clean-assembled.sh"

  local scripts=(
    template-verify.sh
    cursor-coherence.sh
    verify-super-cursor.sh
    verify-system.sh
    pack-offline-dist.sh
    consumer-smoke.sh
    ci-preflight.sh
    bugfix-smoke.sh
    runner-smoke.sh
    install-smoke.sh
    sync-plugin-subset.sh
    pack-plugin-marketplace.sh
    verify-plugin-marketplace-pack.sh
    verify-adaptor-contract.sh
    verify-changelog.sh
    verify-doc-super-cursor.sh
    verify-docs-layout.sh
    verify-growth-layout.sh
    verify-harness-layout.sh
    verify-mother-root-bin.sh
    verify-portability.sh
    verify-project-tmp-cleanup.sh
    verify-roo-compat.sh
    verify-rules-globs.sh
    verify-scripts-layout.sh
    verify-secrets.sh
    verify-config.sh
    verify-skill-bundles-ssot.sh
    verify-onekey-template.sh
    verify-install-opencode.sh
    verify-install-rules-export.sh
    verify-install-skills-export.sh
    verify-install-skills-bundle.sh
    verify-install-zcode.sh
    verify-spike-docs-sync-scope.sh
    verify-spike-marketplace-prep-scope.sh
    verify-spike-mother-hygiene-scope.sh
    verify-spike-onekey-bootstrap-scope.sh
    verify-spike-skills-bundle-scope.sh
    verify-spike-tools-skills-archive.sh
    verify-cursor-plugin-mvp.sh
    verify-cursor-plugin-manifest.sh
    verify-cursor-platform-contract.sh
    verify-spike-plugin-mvp-scope.sh
    verify-spike-plugin-agents-scope.sh
    verify-spike-plugin-phase2-scope.sh
  )
  local s
  for s in "${scripts[@]}"; do
    rm -f "$cur_bin/$s" "$pack_bin/$s" 2>/dev/null || true
  done
  if [[ -d "$cur_adaptor_bin" ]]; then
    for s in verify-cursor-plugin-mvp.sh verify-cursor-plugin-manifest.sh verify-cursor-platform-contract.sh \
      verify-spike-plugin-mvp-scope.sh verify-spike-plugin-agents-scope.sh verify-spike-plugin-phase2-scope.sh; do
      rm -f "$cur_adaptor_bin/$s" 2>/dev/null || true
    done
  fi
  # 顶层 verify 入口（symlink 目标已删则去掉断链）
  rm -f "$root/.cursor/verify-super-cursor.sh" "$root/.cursor/verify-system.sh" \
    "$root/.cursor/template-verify.sh" 2>/dev/null || true
}

sc_pack_prune_consumer "$ROOT"

if [[ -f "$ROOT/.cursor/harness/link-cursor-ide.sh" ]]; then
  bash "$ROOT/.cursor/harness/link-cursor-ide.sh" "$ROOT/.cursor" >/dev/null
fi
sc_chmod_scripts "$ROOT/.cursor"

if [[ "$STRIP_URLS" == "true" || "$STRIP_HOME" == "true" ]]; then
  sc_py="$(sc_python 2>/dev/null || true)"
  [[ -n "$sc_py" ]] || { echo "错误: --strip-* 需要 python3" >&2; exit 1; }
  "$sc_py" - "$ROOT" "$STRIP_URLS" "$STRIP_HOME" "${HOME:-}" <<'PY'
import os, re, sys
root, su, sh, home = sys.argv[1], sys.argv[2] == "true", sys.argv[3] == "true", sys.argv[4]
exts = {".md", ".mdc", ".sh", ".json", ".html", ".txt", ".yaml", ".yml", ".vue", ".ts", ".tsx", ".js"}
url_re = re.compile(r"https?://[^\s)\]\"'<>]+")
for dirpath, _, files in os.walk(root):
    for fn in files:
        path = os.path.join(dirpath, fn)
        if os.path.islink(path):
            continue
        _, ext = os.path.splitext(fn)
        if ext.lower() not in exts:
            continue
        try:
            data = open(path, encoding="utf-8", errors="surrogateescape").read()
        except OSError:
            continue
        orig = data
        if su:
            data = url_re.sub("(offline)", data)
        if sh and home and len(home) > 1:
            data = data.replace(home, "~/")
        if data != orig:
            open(path, "w", encoding="utf-8", newline="\n").write(data)
PY
fi

TAR="$OUT/${BASE}.tar.gz"
(
  cd "$STAGING"
  tar -czf "$TAR" "$BASE"
)

USAGE_MD="$OUT/${BASE}-USAGE.md"
USAGE_HTML="$OUT/${BASE}-USAGE.html"

cat >"$USAGE_MD" <<EOF
# Super Cursor 离线分发包 — 使用说明

> **本文档只描述与本压缩包同级的 \`${BASE}.tar.gz\`**，不是 cursor-ai 母版仓库的 README。  
> 解压后的目录即 **Super Cursor 母版根**（\`SUPER_CURSOR_HOME\`），再由此安装到**你的 Git 项目**。

| 项 | 值 |
|----|-----|
| 压缩包 | \`${BASE}.tar.gz\` |
| 解压后顶层目录 | \`${BASE}/\` |
| 版本 | ${VER} |
| 打包时间 | ${STAMP} |
| 脱敏 | strip-urls=${STRIP_URLS} · strip-home=${STRIP_HOME} |

---

## 一、压缩包里有什么

解压 \`${BASE}.tar.gz\` 后，应看到类似结构：

\`\`\`text
${BASE}/
├── install-super-cursor.sh    # 安装入口（必读）
├── bin/super-cursor-sync      # 配好环境变量后，在任意项目里快速同步 .cursor/
├── README.md · README.en.md   # 产品概览（可选读）
├── .gitignore · .cursorignore # 安装时可合并进目标项目
└── .cursor/                   # Harness 模板（skills · rules · hooks · templates · adaptors）
    ├── harness/core/          # 实体文件（skills 等 SSOT）
    ├── adaptors/              # 各 IDE 安装器与 layout 说明
    └── docs/                  # 文档 Markdown（quickstart · platforms 等）
\`\`\`

| 含有 | 用途 |
|------|------|
| \`install-super-cursor.sh\` | 把模板装进**目标 Git 仓库根** |
| \`.cursor/\` | Cursor 主路径 + 各 adaptor 脚本 |
| \`bin/super-cursor-sync\` | 与 \`--replace\` 等价的快捷同步（需 \`SUPER_CURSOR_HOME\`） |

| **故意不含** | 原因 |
|--------------|------|
| \`.git\` · \`.growing\` | 版本历史 / 项目 plan 属于**目标项目**，不进分发包 |
| \`.cursor-plugin\` · \`.github\` · 根 \`docs/\` | 插件轨 · CI · 文档站构建（与离线 install 无关） |
| 母版 \`verify-*\` · \`template-verify\` | 仅 cursor-ai 开发验收；目标项目用 \`platform-check\` |

**布局注意：** 包内 \`.cursor/skills\` 等多为指向 \`harness/core\` 的 **symlink**。解压后勿对目录做 \`cp -rL\` 展开，否则体积翻倍且易错。

---

## 二、冷启动（第一次使用）

「冷启动」= 你手头只有 **tar + 本说明**，尚未配置 shell，也尚未给任何项目装过 Super Cursor。

### 步骤 1 — 解压到固定位置

\`\`\`bash
mkdir -p ~/super-cursor
tar -xzf ${BASE}.tar.gz -C ~/super-cursor
cd ~/super-cursor/${BASE}
\`\`\`

建议路径长期不变（例如始终 \`~/super-cursor/${BASE}\`），便于升级时替换目录并改环境变量。

### 步骤 2 — 指定母版根（当前 shell）

\`\`\`bash
export SUPER_CURSOR_HOME="\$(pwd)"
export PATH="\$SUPER_CURSOR_HOME/bin:\$PATH"
\`\`\`

**可选（推荐）：** 写入 shell，以后任意目录都能 \`install-super-cursor\`：

\`\`\`bash
bash install-super-cursor.sh --setup-shell
source ~/.bashrc   # 或 ~/.zshrc
\`\`\`

### 步骤 3 — 选一个目标项目（必须是 Git 仓库根或有 \`.git\`）

\`\`\`bash
TARGET=/path/to/your-git-project
\`\`\`

### 步骤 4 — 按 IDE 安装（见下一节）

至少装 **Cursor** 路径（\`.cursor/\`）。其它 IDE 按需追加，**共用同一 \`.growing/\`**（在目标项目里生成，不在 tar 里）。

### 步骤 5 — 在目标项目里「开机」（Agent 冷启动）

进入 \`\$TARGET\`，在 **Cursor（或其它已装 IDE）** 打开该仓库，按顺序：

| 顺序 | 动作 | 说明 |
|------|------|------|
| 1 | \`bash .cursor/bin/platform-check.sh\` | 依赖自检（bash · git · jq/python · rsync 等） |
| 2 | 对 Agent：**\`/learn\`** | 填充项目认知；不做则 plan/闸门容易空转 |
| 3a | **已有代码（棕地）** | \`bash .cursor/bin/scaffold.sh adapt --write\`（project-profile） |
| 3b | **空仓库（绿地）** | 对 Agent：**\`/scaffold\`** 或 \`/master\` 路由 |
| 4 | **\`/master\`** → **\`/plan\`** → 确认后 **\`/run\`** | 日常闭环 |

口诀：**一次 plan 批准 · 一次 run 开跑 · 决策才停 · verify 才勾 ✅**

更细 walkthrough → 解压包内 \`.cursor/docs/quickstart.md\` · \`.cursor/docs/walkthrough.md\`

---

## 三、按 IDE / 工具安装

所有命令在 **\`\$SUPER_CURSOR_HOME\`** 下执行（或已 \`setup-shell\`）。  
\`\$TARGET\` = 目标 **Git 项目根**。

### Cursor（默认，必装若你用 Cursor）

\`\`\`bash
bash install-super-cursor.sh "\$TARGET" --replace --copy-plan
\`\`\`

| 选项 | 含义 |
|------|------|
| \`--replace\` | 先删旧 \`.cursor/\` 再拷贝（升级推荐；仅当旧目录已是 Super Cursor 安装） |
| \`--copy-plan\` | 复制 plan 模板 → \`\$TARGET/.growing/plan.md\` |
| \`--profile lite\` | 轻量 workflow（少 hooks） |
| \`--skills-bundle core\` | 23 个 skill（不含部分工具向 skill） |

产出：**\`\$TARGET/.cursor/\`** · hooks · \`\$TARGET/.growing/\`（若不存在会初始化）。  
若曾用旧名 \`.cursorGrowth/\`，install 会迁到 \`.growing/\`。

### ZCode

与 Cursor **并存**；规则在 **\`.zcode/\`**，路径改写自同一 harness core。

\`\`\`bash
# 先装 Cursor，或至少已有 .cursor/ 时也可只加 zcode：
bash install-super-cursor.sh "\$TARGET" --adaptor zcode
# 或：
bash .cursor/bin/install-adaptor-zcode.sh "\$TARGET"
\`\`\`

ZCode 需在 workspace 启用 **\`.zcode/config.json\`** 里 \`hooks.enabled: true\`。  
布局 → \`.cursor/adaptors/zcode/docs/layout.md\`

### DeepSeek（DSH）· OpenCode

OpenCode 走官方 `AGENTS.md` + `opencode.json`（无 `.opencode/` 目录）；DeepSeek Harness（dsh）为用户级 harness，无项目内安装（见各 adaptor 的 `docs/layout.md` §官方对照）：

\`\`\`bash
bash install-super-cursor.sh "\$TARGET" --adaptor opencode
\`\`\`

产出：**\`AGENTS.md\`** · **\`opencode.json\`** — 详见 \`adaptors/opencode/docs/layout.md\`

### Kiro · Trae

**规则导出**（非完整 core 树）：

\`\`\`bash
bash install-super-cursor.sh "\$TARGET" --adaptor kiro
bash install-super-cursor.sh "\$TARGET" --adaptor trae
\`\`\`

产出：**\`.kiro/\`** · **\`.trae/\`** — 见各 adaptor 的 \`docs/layout.md\`

### 多 IDE 同仓库示例

\`\`\`bash
bash install-super-cursor.sh "\$TARGET" --replace --copy-plan \\
  --adaptor zcode
\`\`\`

**共用：** \`\$TARGET/.growing/\`（plan · learn · archive · rules/local）  
**独立：** \`.cursor/\` · \`.zcode/\` · \`AGENTS.md\`（OpenCode）等互不引用，升级母版后需分别重装各 adaptor。

---

## 四、升级母版包（新 tar）

1. 解压新 tar 到新目录（或覆盖旧 \`${BASE}\` 目录）。  
2. 更新 \`SUPER_CURSOR_HOME\` 指向新目录（或重跑 \`--setup-shell\`）。  
3. 在每个目标项目：

\`\`\`bash
cd "\$TARGET"
install-super-cursor --replace
# 若用过 adaptor，再追加 --adaptor zcode 等
\`\`\`

**.growing/ 不会被 tar 覆盖**（只在目标项目本地）。

---

## 五、自检与文档

\`\`\`bash
# 在目标项目根：
bash .cursor/bin/platform-check.sh
\`\`\`

| 文档（解压包内路径） | 内容 |
|---------------------|------|
| \`.cursor/docs/quickstart.md\` | 5 分钟闭环 |
| \`.cursor/docs/platforms.md\` | Linux / macOS / Git Bash |
| \`.cursor/docs/consumer-refresh.md\` | 棕地升级 \`.cursor/\` |
| \`.cursor/adaptors/*/docs/layout.md\` | 各 IDE 目录约定 |

---

## 六、与本文件同级的文件

| 文件 | 说明 |
|------|------|
| \`${BASE}.tar.gz\` | 分发压缩包 |
| \`${BASE}-USAGE.md\` | 本说明 |
| \`${BASE}-USAGE.html\` | 本说明的 HTML 副本（便于浏览器打开） |

---

*Super Cursor ${VER} · 离线包 ${STAMP}*
EOF

# USAGE.md → 语义化 HTML（stdlib 转换，无 npm / 无 pip 依赖）
sc_py="$(sc_python 2>/dev/null || true)"
if [[ -z "$sc_py" ]]; then
  echo "WARN: 无 python，USAGE.html 退化为纯文本" >&2
  {
    echo '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">'
    echo "<title>${BASE} — Super Cursor 离线包</title></head><body><pre>"
    sed 's/&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g' "$USAGE_MD"
    echo '</pre></body></html>'
  } >"$USAGE_HTML"
else
  "$sc_py" - "$USAGE_MD" "$USAGE_HTML" "$BASE" <<'PY'
import html
import re
import sys

md_path, html_path, base_name = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(md_path, encoding="utf-8").read()
lines = text.splitlines()

def inline(s: str) -> str:
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    return s

out: list[str] = []
i = 0
n = len(lines)

def flush_paragraph(buf: list[str]) -> None:
    if not buf:
        return
    joined = " ".join(x.strip() for x in buf if x.strip())
    if joined:
        out.append(f"<p>{inline(joined)}</p>")

while i < n:
    line = lines[i]
    stripped = line.strip()

    if stripped.startswith("```"):
        lang = stripped[3:].strip() or "text"
        i += 1
        code_lines = []
        while i < n and not lines[i].strip().startswith("```"):
            code_lines.append(lines[i])
            i += 1
        if i < n:
            i += 1
        body = html.escape("\n".join(code_lines))
        cls = f' class="language-{html.escape(lang)}"' if lang else ""
        out.append(f"<pre><code{cls}>{body}</code></pre>")
        continue

    if re.match(r"^#{1,6}\s", line):
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        assert m
        level = len(m.group(1))
        out.append(f"<h{level}>{inline(m.group(2))}</h{level}>")
        i += 1
        continue

    if stripped in ("---", "***", "___"):
        out.append("<hr>")
        i += 1
        continue

    if stripped.startswith(">"):
        bq = []
        while i < n and lines[i].strip().startswith(">"):
            bq.append(lines[i].strip().lstrip(">").strip())
            i += 1
        out.append("<blockquote>" + "".join(f"<p>{inline(x)}</p>" for x in bq if x) + "</blockquote>")
        continue

    if "|" in line and i + 1 < n and re.match(r"^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$", lines[i + 1].strip()):
        rows = []
        while i < n and "|" in lines[i]:
            row = [c.strip() for c in lines[i].strip().strip("|").split("|")]
            rows.append(row)
            i += 1
        if len(rows) >= 2:
            out.append("<table>")
            out.append("<thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr></thead>")
            out.append("<tbody>")
            for row in rows[2:]:
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
            out.append("</tbody></table>")
        continue

    if re.match(r"^\d+\.\s", stripped):
        out.append("<ol>")
        while i < n and re.match(r"^\d+\.\s", lines[i].strip()):
            item = re.sub(r"^\d+\.\s+", "", lines[i].strip())
            out.append(f"<li>{inline(item)}</li>")
            i += 1
        out.append("</ol>")
        continue

    if stripped == "":
        i += 1
        continue

    if stripped.startswith("*") and stripped.endswith("*") and not stripped.startswith("**"):
        out.append(f"<p><em>{inline(stripped.strip('*').strip())}</em></p>")
        i += 1
        continue

    para = []
    while i < n:
        s = lines[i].strip()
        if s == "" or s.startswith("#") or s.startswith("```") or s.startswith(">") or s in ("---",) or (
            "|" in lines[i] and i + 1 < n and "|" in lines[i + 1] and re.match(r"^[\|\s:-]+$", lines[i + 1].strip())
        ):
            break
        if re.match(r"^\d+\.\s", s):
            break
        para.append(lines[i])
        i += 1
    flush_paragraph(para)

css = """
:root { color-scheme: light dark; }
body {
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Noto Sans SC", sans-serif;
  max-width: 46rem; margin: 0 auto; padding: 2rem 1.25rem 3rem;
  line-height: 1.65; color: #1a1a1a; background: #fafafa;
}
@media (prefers-color-scheme: dark) {
  body { color: #e8e8e8; background: #121212; }
  pre, code { background: #1e1e1e !important; border-color: #333 !important; }
  table th, table td { border-color: #444 !important; }
  blockquote { border-color: #555 !important; background: #1a1a1a !important; }
}
header.doc-header {
  margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 1px solid #ddd;
}
header.doc-header p { margin: 0.35rem 0; color: #555; font-size: 0.95rem; }
@media (prefers-color-scheme: dark) {
  header.doc-header { border-color: #333; }
  header.doc-header p { color: #aaa; }
}
h1 { font-size: 1.75rem; margin-top: 0; line-height: 1.25; }
h2 { font-size: 1.35rem; margin-top: 2rem; border-bottom: 1px solid #eee; padding-bottom: 0.35rem; }
h3 { font-size: 1.1rem; margin-top: 1.5rem; }
blockquote {
  margin: 1rem 0; padding: 0.75rem 1rem; border-left: 4px solid #3b82f6;
  background: #f0f4ff; border-radius: 0 6px 6px 0;
}
blockquote p { margin: 0.25rem 0; }
pre {
  background: #f4f4f5; border: 1px solid #e4e4e7; border-radius: 8px;
  padding: 1rem 1.1rem; overflow-x: auto; font-size: 0.88rem; line-height: 1.5;
}
code { font-family ui-monospace, "Cascadia Code", "SF Mono", Menlo, monospace; font-size: 0.9em; }
p code, li code, td code { background: #f4f4f5; padding: 0.12em 0.35em; border-radius: 4px; }
table { width: 100%; border-collapse: collapse; margin: 1rem 0; font-size: 0.92rem; }
th, td { border: 1px solid #ddd; padding: 0.5rem 0.65rem; text-align: left; vertical-align: top; }
th { background: #f4f4f5; font-weight: 600; }
hr { border: none; border-top: 1px solid #ddd; margin: 2rem 0; }
ol, ul { padding-left: 1.35rem; }
li { margin: 0.35rem 0; }
footer { margin-top: 2.5rem; font-size: 0.85rem; color: #666; }
"""

doc = "\n".join(out)
page = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(base_name)} — Super Cursor 离线包</title>
<style>{css}</style>
</head>
<body>
<header class="doc-header">
<p><strong>离线分发说明</strong> · 配套压缩包 <code>{html.escape(base_name)}.tar.gz</code></p>
</header>
<main>
{doc}
</main>
<footer>在浏览器中打开本文件即可；与 <code>{html.escape(base_name)}-USAGE.md</code> 内容一致。</footer>
</body>
</html>
"""
open(html_path, "w", encoding="utf-8", newline="\n").write(page)
PY
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  离线包已写入 → $OUT"
echo "╚══════════════════════════════════════════════════╝"
echo "  tar:  ${BASE}.tar.gz ($(du -h "$TAR" | awk '{print $1}'))"
echo "  doc:  ${BASE}-USAGE.md"
echo "        ${BASE}-USAGE.html"
echo ""
echo "  建议: install-super-cursor.sh --pack-offline --strip-urls --strip-home"
