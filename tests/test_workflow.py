"""CI 工作流结构测试（TASK-007）。

用 YAML 解析而不是字符串匹配，防止改坏了还"看起来对"。
注意：PyYAML 按 YAML 1.1 会把顶层 `on:` 解析成布尔 True。
"""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

WORKFLOW_PATH = Path(__file__).resolve().parent.parent / ".github" / "workflows" / "schedule.yml"
LEGACY_HOURLY_CRON = "0 * * * *"


@pytest.fixture(scope="module")
def workflow() -> dict:
    assert WORKFLOW_PATH.exists(), "workflow 文件缺失"
    return yaml.safe_load(WORKFLOW_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def triggers(workflow: dict) -> dict:
    return workflow.get("on") or workflow.get(True) or {}


@pytest.fixture(scope="module")
def job(workflow: dict) -> dict:
    jobs = workflow["jobs"]
    assert len(jobs) == 1
    return next(iter(jobs.values()))


@pytest.fixture(scope="module")
def steps(job: dict) -> list:
    return job["steps"]


def step_runs(steps: list) -> str:
    return "\n".join(str(s.get("run", "")) for s in steps)


# ------------------------------------------------------------------ 触发器

def test_has_schedule_and_manual_dispatch(triggers: dict):
    assert "schedule" in triggers
    assert "workflow_dispatch" in triggers


def test_cron_fires_four_times_a_day(triggers: dict):
    crons = [entry["cron"] for entry in triggers["schedule"]]
    assert len(crons) == 1, "只应保留一条 cron，避免重复触发"
    minute, hour, dom, month, dow = crons[0].split()
    assert dom == month == "*" and dow == "*"
    hours = hour.split(",")
    assert len(hours) == 4, f"每天应触发 4 次，实际 {len(hours)} 次"
    assert all(h.isdigit() and 0 <= int(h) <= 23 for h in hours)
    assert minute.isdigit(), "分钟应为固定值（错开整点，缓解 GitHub 定时限流）"


def test_cron_is_not_the_legacy_hourly(triggers: dict):
    crons = [entry["cron"] for entry in triggers["schedule"]]
    assert LEGACY_HOURLY_CRON not in crons, "v0 的每小时 cron 是调度饿死的根因"


def test_cron_minute_is_off_peak(triggers: dict):
    minute = triggers["schedule"][0]["cron"].split()[0]
    assert minute not in {"0", "30"}, "整点/半点最容易被 GitHub 丢弃"


# ------------------------------------------------------------------ 并发与权限

def test_concurrency_serialises_runs(workflow: dict):
    concurrency = workflow.get("concurrency")
    assert isinstance(concurrency, dict)
    assert concurrency["group"]
    assert concurrency["cancel-in-progress"] is False, "抓取任务不可中途取消，否则丢数据"


def test_permissions_allow_push(workflow: dict):
    assert workflow["permissions"]["contents"] == "write"


# ------------------------------------------------------------------ 运行环境

def test_checkout_and_python_actions_are_current(steps: list):
    uses = [s["uses"] for s in steps if "uses" in s]
    checkout = next(u for u in uses if u.startswith("actions/checkout"))
    setup = next(u for u in uses if u.startswith("actions/setup-python"))
    assert int(checkout.split("@v")[1]) >= 4
    assert int(setup.split("@v")[1]) >= 5


def test_python_version_is_supported(steps: list):
    setup = next(s for s in steps if s.get("uses", "").startswith("actions/setup-python"))
    minor = int(str(setup["with"]["python-version"]).split(".")[1])
    assert minor >= 11, "3.11 起才支持本仓 pyproject 的 requires-python"


def test_dependency_cache_enabled(steps: list):
    setup = next(s for s in steps if s.get("uses", "").startswith("actions/setup-python"))
    assert setup["with"].get("cache") == "pip"


def test_timeout_set(job: dict):
    assert job.get("timeout-minutes"), "无超时会让卡死的 run 一直占着 concurrency 组"


# ------------------------------------------------------------------ 抓取与校验

def test_runs_crawler_then_verifies_data(steps: list):
    runs = step_runs(steps)
    assert "crawl_baidu_top.py" in runs
    assert "./scripts/verify.sh --data" in runs
    crawl_idx = next(i for i, s in enumerate(steps) if "crawl_baidu_top.py" in str(s.get("run", "")))
    verify_idx = next(i for i, s in enumerate(steps) if "verify.sh --data" in str(s.get("run", "")))
    assert crawl_idx < verify_idx, "必须先抓取再校验"


# ------------------------------------------------------------------ 提交推送

def test_commit_skips_when_no_changes(steps: list):
    runs = step_runs(steps)
    assert "git diff --cached --quiet" in runs, "无变更时要跳过提交（v0 会直接失败）"


def test_rebase_before_push(steps: list):
    runs = step_runs(steps)
    assert "git pull --rebase" in runs, "push 前必须 rebase，否则 non-fast-forward 静默失败"
    assert runs.index("git pull --rebase") < runs.index("git push")


def test_commit_message_is_quoted_and_dated(steps: list):
    runs = step_runs(steps)
    assert "git commit -m \"data: 抓取 $(date -u" in runs, "提交信息必须加引号，v0 的无引号 $(date) 会踩坑"


def test_no_hardcoded_legacy_identity(steps: list):
    runs = step_runs(steps)
    assert "jwzhou" not in runs and "zhou24388@163.com" not in runs


# ------------------------------------------------------------------ 失败可见

def test_failure_is_visible(steps: list):
    runs = step_runs(steps)
    assert "GITHUB_STEP_SUMMARY" in runs, "需要 job summary"
    assert "::error::" in runs, "失败要有 annotation"
    always_steps = [s for s in steps if str(s.get("if", "")) == "always()"]
    failure_steps = [s for s in steps if str(s.get("if", "")) == "failure()"]
    assert always_steps, "摘要步骤需 if: always()"
    assert failure_steps, "需要 if: failure() 的显式失败报告"


def test_summary_reports_step_outcomes(steps: list):
    summary = next(s for s in steps if "GITHUB_STEP_SUMMARY" in str(s.get("run", "")))
    body = summary["run"]
    for outcome in ("steps.crawl.outcome", "steps.verify.outcome", "steps.commit.outcome"):
        assert outcome in body
