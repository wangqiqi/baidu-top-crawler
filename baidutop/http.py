"""HTTP 传输层：超时 / 连接错误 / 可重试状态码统一退避重试。

修复 v0 缺陷 D2（``RequestException`` 直接抛出 → 5xx 不重试）与 D4（退避硬编码、日志割裂）。
可重试：超时、连接错误、408/425/429/500/502/503/504；其余 4xx 立即失败不重试。
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, FrozenSet, Optional

import requests
from requests import Response
from requests.exceptions import ConnectionError, HTTPError, RequestException, Timeout

DEFAULT_TIMEOUT = 10
DEFAULT_MAX_RETRIES = 3
DEFAULT_BACKOFF = 2.0
DEFAULT_MAX_BACKOFF = 30.0
DEFAULT_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)
DEFAULT_HEADERS: Dict[str, str] = {
    "User-Agent": DEFAULT_USER_AGENT,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
}

RETRYABLE_STATUS: FrozenSet[int] = frozenset({408, 425, 429, 500, 502, 503, 504})


class HttpRetryError(RequestException):
    """已按策略重试用尽仍失败。"""


@dataclass(frozen=True)
class RetryPolicy:
    """重试策略：指数退避 + 上限 + 可重试状态码集合。"""

    max_retries: int = DEFAULT_MAX_RETRIES
    backoff: float = DEFAULT_BACKOFF
    max_backoff: float = DEFAULT_MAX_BACKOFF
    retryable_status: FrozenSet[int] = field(default=RETRYABLE_STATUS)

    def delay_for(self, attempt: int, response: Optional[Response] = None) -> float:
        """第 ``attempt`` 次（1 起）失败后的等待秒数；优先尊重 ``Retry-After``。"""
        if response is not None:
            header = response.headers.get("Retry-After") if response.headers else None
            if header:
                try:
                    return min(float(header), self.max_backoff)
                except ValueError:
                    pass
        return min(self.backoff * (2 ** (attempt - 1)), self.max_backoff)


def build_session(headers: Optional[Dict[str, str]] = None) -> requests.Session:
    """构造带默认头的 Session。"""
    session = requests.Session()
    session.headers.update(DEFAULT_HEADERS if headers is None else headers)
    return session


class HttpClient:
    """可注入 session / sleep 的抓取客户端（便于离线测试）。"""

    def __init__(
        self,
        *,
        timeout: float = DEFAULT_TIMEOUT,
        policy: Optional[RetryPolicy] = None,
        session: Optional[Any] = None,
        sleep: Callable[[float], None] = time.sleep,
        logger: Optional[logging.Logger] = None,
    ) -> None:
        self.timeout = timeout
        self.policy = policy or RetryPolicy()
        self.session = session if session is not None else build_session()
        self._sleep = sleep
        self.logger = logger or logging.getLogger(__name__)

    def get_text(self, url: str, *, params: Optional[Dict[str, Any]] = None) -> str:
        """GET 并返回响应文本；按策略重试，失败抛 :class:`HttpRetryError`。"""
        last_error: Optional[Exception] = None

        for attempt in range(1, self.policy.max_retries + 1):
            self.logger.debug(f"发送请求 (尝试 {attempt}/{self.policy.max_retries}): {url}")
            try:
                response = self.session.get(url, timeout=self.timeout, params=params)
            except (Timeout, ConnectionError) as exc:
                last_error = exc
                self._handle_retry(attempt, url, exc, None)
                continue
            except RequestException:
                # URL 非法等本地错误：立即失败，重试无意义
                raise

            status = getattr(response, "status_code", None)
            if status in self.policy.retryable_status:
                last_error = HTTPError(f"{status} 服务端错误: {url}", response=response)
                self._handle_retry(attempt, url, last_error, response)
                continue

            try:
                response.raise_for_status()
            except HTTPError:
                raise  # 4xx 等不可重试错误

            if attempt > 1:
                self.logger.info(f"第 {attempt} 次尝试成功: {url}")
            return response.text

        raise HttpRetryError(
            f"请求失败，已重试 {self.policy.max_retries} 次: {url}（最后错误: {last_error}）"
        )

    def _handle_retry(
        self,
        attempt: int,
        url: str,
        error: Exception,
        response: Optional[Response],
    ) -> None:
        """记录日志并退避；最后一次尝试不再等待。"""
        if attempt >= self.policy.max_retries:
            self.logger.error(f"请求失败（已达最大重试次数 {self.policy.max_retries}）: {url} — {error}")
            return
        delay = self.policy.delay_for(attempt, response)
        self.logger.warning(f"请求失败 (尝试 {attempt}/{self.policy.max_retries}): {error} · {delay:.1f}s 后重试")
        self._sleep(delay)
