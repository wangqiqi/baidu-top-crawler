#!/usr/bin/env python3
"""按 .growing/temp-cleanup.json 回收项目 /tmp 残留（仅声明的 glob · 仅限 /tmp 系目录）。"""
from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import sys
import time
from pathlib import Path

EPHEMERAL_DEFAULT_AFTER = ("test", "verify", "task-verify")
PERSISTENT_DEFAULT_AFTER = ("sweep",)


def allowed_tmp_roots() -> list[Path]:
    candidates: list[Path] = []
    for key in ("TMPDIR", "TEMP", "TMP"):
        val = os.environ.get(key)
        if val:
            candidates.append(Path(val))
    if os.name != "nt":
        candidates.append(Path("/tmp"))
        var_tmp = Path("/var/tmp")
        if var_tmp.is_dir():
            candidates.append(var_tmp)
    out: list[Path] = []
    for p in candidates:
        try:
            r = p.resolve()
        except OSError:
            continue
        if r not in out:
            out.append(r)
    return out


def path_under_allowed_roots(p: Path, roots: list[Path]) -> bool:
    try:
        rp = p.resolve()
    except OSError:
        return False
    for root in roots:
        if rp == root:
            return True
        try:
            if rp.is_relative_to(root):
                return True
        except (ValueError, OSError):
            if str(rp).startswith(str(root) + os.sep):
                return True
    return False


def _is_absolute_tmp_pattern(pattern: str) -> bool:
    if pattern.startswith("/"):
        return True
    if len(pattern) >= 2 and pattern[1] == ":" and pattern[0].isalpha():
        return True
    return pattern.startswith("\\\\")


def _pattern_probe_path(pattern: str) -> Path | None:
    """Resolve literal prefix of a glob (macOS: /tmp → /private/tmp)."""
    if ".." in pattern or not _is_absolute_tmp_pattern(pattern):
        return None
    fixed = pattern.split("*", 1)[0].rstrip("/") or "/"
    try:
        if "*" not in pattern:
            return Path(pattern).resolve()
        parent = fixed if fixed != "/" else "/"
        return Path(parent).resolve()
    except OSError:
        return None


def glob_pattern_allowed(pattern: str, roots: list[Path]) -> bool:
    if ".." in pattern:
        return False
    probe = _pattern_probe_path(pattern)
    if probe is None:
        return False
    return path_under_allowed_roots(probe, roots)


def rule_applies(rule: dict, phase: str) -> bool:
    tier = rule.get("tier", "ephemeral")
    after = rule.get("after")
    if after is None:
        after = EPHEMERAL_DEFAULT_AFTER if tier == "ephemeral" else PERSISTENT_DEFAULT_AFTER
    return phase in after


def should_delete(path: Path, rule: dict, phase: str, now: float) -> bool:
    tier = rule.get("tier", "ephemeral")
    if tier == "ephemeral":
        return phase in (rule.get("after") or EPHEMERAL_DEFAULT_AFTER)
    if tier != "persistent":
        return False
    if phase != "sweep" and "sweep" not in (rule.get("after") or PERSISTENT_DEFAULT_AFTER):
        if phase not in (rule.get("after") or PERSISTENT_DEFAULT_AFTER):
            return False
    max_h = float(rule.get("max_age_hours", 24))
    try:
        age_h = (now - path.stat().st_mtime) / 3600.0
    except OSError:
        return False
    return age_h >= max_h


def collect_targets(pattern: str, roots: list[Path]) -> list[Path]:
    if not glob_pattern_allowed(pattern, roots):
        raise ValueError(f"glob 必须位于 /tmp 或 TMPDIR 下: {pattern}")
    paths = [Path(p) for p in glob.glob(pattern)]
    return [p for p in paths if path_under_allowed_roots(p, roots)]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--phase", required=True, choices=["test", "verify", "task-verify", "sweep"])
    ap.add_argument("--root", default=".")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    cfg_path = Path(args.config)
    if not cfg_path.is_file():
        return 0

    data = json.loads(cfg_path.read_text(encoding="utf-8"))
    if not data.get("enabled", True):
        return 0

    roots = allowed_tmp_roots()
    rules = data.get("rules") or []
    now = time.time()
    removed = 0
    bytes_freed = 0

    for rule in rules:
        if not rule_applies(rule, args.phase):
            continue
        pattern = rule.get("glob") or rule.get("pattern")
        if not pattern:
            continue
        try:
            targets = collect_targets(pattern, roots)
        except ValueError as e:
            print(f"[tmp-cleanup] SKIP rule {rule.get('id', '?')}: {e}", file=sys.stderr)
            continue

        for path in targets:
            if not path.exists():
                continue
            tier = rule.get("tier", "ephemeral")
            if tier == "persistent" and not should_delete(path, rule, args.phase, now):
                continue
            try:
                size = path.stat().st_size if path.is_file() else 0
                if path.is_dir():
                    size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
            except OSError:
                size = 0
            label = rule.get("id", pattern)
            if args.dry_run:
                print(f"[dry-run] would remove {path} ({label})")
            else:
                if path.is_dir():
                    shutil.rmtree(path, ignore_errors=True)
                else:
                    path.unlink(missing_ok=True)
                print(f"[tmp-cleanup] removed {path} ({label})")
            removed += 1
            bytes_freed += size

    if removed:
        mb = bytes_freed / (1024 * 1024)
        print(f"[tmp-cleanup] phase={args.phase} items={removed} ~{mb:.2f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
