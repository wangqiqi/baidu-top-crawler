"""
百度实时热点爬虫工具
爬取百度热搜榜单数据并写入 v1 紧凑 Markdown（权威格式见 docs/data-format.md）
"""

from __future__ import annotations

import argparse
import logging
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from bs4 import BeautifulSoup

from baidutop import format as fmt
from baidutop import http as http_layer
from baidutop import store

# 配置常量
BAIDU_TOP_URL = "https://top.baidu.com/board"
REQUEST_TIMEOUT = 10
MAX_RETRIES = 3
RETRY_DELAY = 2
ROOT = Path(__file__).resolve().parent
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)


class BaiduHotSearchCrawler:
    """百度热搜爬虫类"""

    def __init__(
        self,
        timeout: int = REQUEST_TIMEOUT,
        max_retries: int = MAX_RETRIES,
        retry_delay: float = RETRY_DELAY,
        http_client: Optional[http_layer.HttpClient] = None,
    ):
        """
        初始化爬虫

        Args:
            timeout: 请求超时时间（秒）
            max_retries: 最大重试次数
            retry_delay: 重试基础间隔（秒）
            http_client: 注入自定义 HTTP 客户端（测试用）
        """
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.logger = logging.getLogger(__name__)
        self.policy = http_layer.RetryPolicy(max_retries=max_retries, backoff=retry_delay)
        self.http = http_client or http_layer.HttpClient(
            timeout=timeout,
            policy=self.policy,
            logger=self.logger,
        )

    def _make_request_with_retry(self, url: str) -> str:
        """
        带重试机制的HTTP请求（退避策略见 baidutop.http.RetryPolicy）

        Args:
            url: 请求URL

        Returns:
            响应文本内容

        Raises:
            HttpRetryError: 重试用尽仍失败
        """
        return self.http.get_text(url)

    def crawl_hot_search(self, board: str = "realtime") -> List[Tuple[str, str]]:
        """
        爬取百度热搜榜单

        Args:
            board: 榜单类型，默认realtime（实时热点）

        Returns:
            热搜标题和热度指数的列表

        Raises:
            RequestException: 爬取失败
        """
        url = f"{BAIDU_TOP_URL}?tab={board}"
        self.logger.info(f"开始爬取百度{board}榜单...")

        try:
            html_content = self._make_request_with_retry(url)
            soup = BeautifulSoup(html_content, "lxml")

            record_tags = soup.find_all("div", class_=lambda x: x and "category-wrap" in x)

            if not record_tags:
                self.logger.warning("未找到热搜数据，可能页面结构已更新")
                return []

            results: List[Tuple[str, str]] = []
            for item in record_tags:
                title_tag = item.find("div", class_=lambda x: x and "c-single-text-ellipsis" in x)
                hot_index_tag = item.find("div", class_=lambda x: x and "hot-index" in x)

                if title_tag and hot_index_tag:
                    title = title_tag.get_text(strip=True)
                    hot_index = hot_index_tag.get_text(strip=True)
                    results.append((title, hot_index))

            self.logger.info(f"成功爬取 {len(results)} 条热搜数据")
            return results

        except Exception as e:
            self.logger.error(f"爬取热搜失败: {e}")
            raise

    # 时区工具保留为静态方法，兼容既有调用方式
    @staticmethod
    def get_utc8_now() -> datetime:
        """获取当前UTC+8时间"""
        return fmt.now_utc8()


def build_records(
    pairs: Sequence[Tuple[str, str]], date: str, captured_at: datetime
) -> List[fmt.Record]:
    """把抓取结果转成 v1 记录（同一批共用同一时刻，避免跨日错位）。"""
    token = fmt.format_datetime(captured_at, date)
    return [fmt.Record(title=title, time=token, hot=hot) for title, hot in pairs]


def run_once(
    *,
    root: Path = ROOT,
    board: str = "realtime",
    crawler: Optional[BaiduHotSearchCrawler] = None,
    captured_at: Optional[datetime] = None,
) -> Dict[str, Any]:
    """执行一次抓取并落盘，返回统计信息。"""
    logger = logging.getLogger(__name__)
    now = captured_at or fmt.now_utc8()
    date = now.strftime("%Y-%m-%d")
    target = store.md_path_for(root, date)

    crawler = crawler or BaiduHotSearchCrawler(timeout=REQUEST_TIMEOUT, max_retries=MAX_RETRIES)
    logger.info("开始执行爬虫任务...")
    pairs = crawler.crawl_hot_search(board=board)
    if not pairs:
        logger.warning("未获取到数据，任务终止")
        return {"date": date, "path": str(target), "crawled": 0, "added": 0, "skipped": 0, "total": 0}

    records = build_records(pairs, date, now)
    stats = store.append_records(
        target, records, date=date, generated=now.isoformat()
    )
    logger.info(
        f"成功写入 {stats['added']} 条记录到: {target}（跳过重复 {stats['skipped']} 条，累计 {stats['total']} 条）"
    )
    logger.info("任务执行完成！")
    return {"date": date, "path": str(target), "crawled": len(pairs), **stats}


def setup_logging(level: int = logging.INFO) -> None:
    """配置日志系统"""
    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def main(argv: Optional[Sequence[str]] = None) -> int:
    """主函数"""
    parser = argparse.ArgumentParser(description="抓取百度实时热点并写入 v1 Markdown")
    parser.add_argument("--root", type=Path, default=ROOT, help="数据仓库根目录")
    parser.add_argument("--board", default="realtime", help="榜单类型")
    parser.add_argument("--verbose", action="store_true", help="输出 DEBUG 日志")
    args = parser.parse_args(argv)

    setup_logging(logging.DEBUG if args.verbose else logging.INFO)
    logger = logging.getLogger(__name__)

    try:
        result = run_once(root=args.root, board=args.board)
        return 0 if result["crawled"] else 1
    except Exception as e:
        logger.error(f"程序执行失败: {e}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
