"""HTTP 传输层测试：重试策略、退避、Retry-After、不可重试错误（修 v0 缺陷 D2/D4）。"""

from __future__ import annotations

import pytest
import requests
from requests.exceptions import ConnectionError, HTTPError, Timeout

from baidutop import http as http_layer


class FakeResponse:
    def __init__(self, status_code: int = 200, text: str = "ok", headers=None):
        self.status_code = status_code
        self.text = text
        self.headers = headers or {}

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise HTTPError(f"{self.status_code} 错误", response=self)


class FakeSession:
    """按脚本依次返回响应或抛异常。"""

    def __init__(self, outcomes):
        self.outcomes = list(outcomes)
        self.calls = []

    def get(self, url, timeout=None, params=None):
        self.calls.append({"url": url, "timeout": timeout, "params": params})
        if not self.outcomes:
            raise AssertionError("FakeSession 被调用次数超出预期")
        item = self.outcomes.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def make_client(outcomes, *, max_retries=3, backoff=2.0, max_backoff=30.0):
    session = FakeSession(outcomes)
    sleeps: list[float] = []
    client = http_layer.HttpClient(
        timeout=7,
        policy=http_layer.RetryPolicy(
            max_retries=max_retries, backoff=backoff, max_backoff=max_backoff
        ),
        session=session,
        sleep=sleeps.append,
    )
    return client, session, sleeps


# --------------------------------------------------------------- 正常路径

def test_success_first_attempt_no_sleep():
    client, session, sleeps = make_client([FakeResponse(200, "hello")])
    assert client.get_text("https://example.com") == "hello"
    assert len(session.calls) == 1
    assert sleeps == []
    assert session.calls[0]["timeout"] == 7


def test_params_and_url_passed_through():
    client, session, _ = make_client([FakeResponse(200, "x")])
    client.get_text("https://example.com", params={"tab": "realtime"})
    assert session.calls[0]["url"] == "https://example.com"
    assert session.calls[0]["params"] == {"tab": "realtime"}


# --------------------------------------------------- 5xx 重试（v0 缺陷 D2）

def test_5xx_is_retried_then_succeeds():
    client, session, sleeps = make_client([FakeResponse(500), FakeResponse(200, "recovered")])
    assert client.get_text("https://example.com") == "recovered"
    assert len(session.calls) == 2
    assert sleeps == [2.0]


def test_503_exhausts_retries_and_raises():
    client, session, sleeps = make_client([FakeResponse(503), FakeResponse(503), FakeResponse(503)])
    with pytest.raises(http_layer.HttpRetryError) as excinfo:
        client.get_text("https://example.com")
    assert len(session.calls) == 3
    assert sleeps == [2.0, 4.0]  # 最后一次不再等待
    assert "已重试 3 次" in str(excinfo.value)


@pytest.mark.parametrize("status", [408, 425, 429, 500, 502, 503, 504])
def test_all_retryable_status_retried(status):
    client, session, sleeps = make_client([FakeResponse(status), FakeResponse(200, "ok")], max_retries=2)
    assert client.get_text("https://example.com") == "ok"
    assert len(session.calls) == 2
    assert sleeps == [2.0]


def test_retry_exponential_backoff():
    client, _, sleeps = make_client(
        [FakeResponse(500)] * 4, max_retries=4, backoff=1.0
    )
    with pytest.raises(http_layer.HttpRetryError):
        client.get_text("https://example.com")
    assert sleeps == [1.0, 2.0, 4.0]


def test_backoff_is_capped():
    client, _, sleeps = make_client([FakeResponse(500)] * 5, max_retries=5, backoff=10.0, max_backoff=15.0)
    with pytest.raises(http_layer.HttpRetryError):
        client.get_text("https://example.com")
    assert sleeps == [10.0, 15.0, 15.0, 15.0]


# ------------------------------------------------------------- Retry-After

def test_retry_after_header_is_honoured():
    resp = FakeResponse(503, headers={"Retry-After": "7"})
    client, _, sleeps = make_client([resp, FakeResponse(200, "ok")], backoff=1.0)
    assert client.get_text("https://example.com") == "ok"
    assert sleeps == [7.0]


def test_retry_after_is_capped_and_garbage_ignored():
    policy = http_layer.RetryPolicy(max_retries=3, backoff=1.0, max_backoff=5.0)
    assert policy.delay_for(1, FakeResponse(503, headers={"Retry-After": "999"})) == 5.0
    assert policy.delay_for(1, FakeResponse(503, headers={"Retry-After": "abc"})) == 1.0
    assert policy.delay_for(2, None) == 2.0


# --------------------------------------------------- 网络异常与不可重试

def test_timeout_is_retried():
    client, session, sleeps = make_client([Timeout("超时"), FakeResponse(200, "ok")])
    assert client.get_text("https://example.com") == "ok"
    assert len(session.calls) == 2
    assert sleeps == [2.0]


def test_connection_error_exhausted():
    client, session, sleeps = make_client([ConnectionError("断网")] * 3)
    with pytest.raises(http_layer.HttpRetryError):
        client.get_text("https://example.com")
    assert len(session.calls) == 3
    assert sleeps == [2.0, 4.0]


@pytest.mark.parametrize("status", [400, 403, 404, 410])
def test_client_errors_are_not_retried(status):
    client, session, sleeps = make_client([FakeResponse(status)])
    with pytest.raises(HTTPError):
        client.get_text("https://example.com")
    assert len(session.calls) == 1
    assert sleeps == []


def test_bad_url_raises_immediately():
    client, session, sleeps = make_client([requests.exceptions.MissingSchema("no scheme")])
    with pytest.raises(requests.exceptions.MissingSchema):
        client.get_text("nonsense")
    assert len(session.calls) == 1
    assert sleeps == []


# --------------------------------------------------------------- 会话构造

def test_build_session_has_default_headers():
    session = http_layer.build_session()
    try:
        assert session.headers["User-Agent"] == http_layer.DEFAULT_USER_AGENT
        assert session.headers["Accept-Language"].startswith("zh-CN")
    finally:
        session.close()


def test_build_session_accepts_custom_headers():
    session = http_layer.build_session({"User-Agent": "custom"})
    try:
        assert session.headers["User-Agent"] == "custom"
    finally:
        session.close()


def test_default_policy_values():
    policy = http_layer.RetryPolicy()
    assert policy.max_retries == 3
    assert policy.backoff == 2.0
    assert 500 in policy.retryable_status
    assert 404 not in policy.retryable_status


# ------------------------------------------------- 与爬虫的接线

SAMPLE_HTML = """
<html><body>
  <div class="category-wrap">
    <div class="c-single-text-ellipsis">#郭婞淳夺中国台北东京奥运首金#</div>
    <div class="hot-index">7974352</div>
  </div>
  <div class="category-wrap">
    <div class="c-single-text-ellipsis">5.6万人接种疫苗离境后无一感染</div>
    <div class="hot-index">7956248</div>
  </div>
</body></html>
"""


def test_crawler_uses_injected_http_client():
    import crawl_baidu_top as crawler_mod

    client, session, _ = make_client([FakeResponse(200, SAMPLE_HTML)])
    crawler = crawler_mod.BaiduHotSearchCrawler(http_client=client)
    pairs = crawler.crawl_hot_search()
    assert pairs == [
        ("#郭婞淳夺中国台北东京奥运首金#", "7974352"),
        ("5.6万人接种疫苗离境后无一感染", "7956248"),
    ]
    assert "tab=realtime" in session.calls[0]["url"]


def test_crawler_propagates_retry_exhaustion():
    import crawl_baidu_top as crawler_mod

    client, _, _ = make_client([FakeResponse(500)] * 3)
    crawler = crawler_mod.BaiduHotSearchCrawler(http_client=client)
    with pytest.raises(http_layer.HttpRetryError):
        crawler.crawl_hot_search()


def test_crawler_no_data_returns_empty():
    import crawl_baidu_top as crawler_mod

    client, _, _ = make_client([FakeResponse(200, "<html><body>空</body></html>")])
    crawler = crawler_mod.BaiduHotSearchCrawler(http_client=client)
    assert crawler.crawl_hot_search() == []


def test_crawler_retry_delay_feeds_policy():
    import crawl_baidu_top as crawler_mod

    crawler = crawler_mod.BaiduHotSearchCrawler(timeout=5, max_retries=4, retry_delay=0.5)
    assert crawler.policy.backoff == 0.5
    assert crawler.policy.max_retries == 4
    assert crawler.http.timeout == 5
