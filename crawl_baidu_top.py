"""
百度实时热点爬虫工具
用于爬取百度热搜榜单数据并保存为JSON格式
"""

import os
import json
import time
import logging
from datetime import datetime, timezone, timedelta
from collections import OrderedDict
from typing import List, Tuple, Dict, Any
from pathlib import Path

import requests
from bs4 import BeautifulSoup
from requests.exceptions import RequestException, Timeout, ConnectionError


# 配置常量
BAIDU_TOP_URL = "https://top.baidu.com/board"
REQUEST_TIMEOUT = 10
MAX_RETRIES = 3
RETRY_DELAY = 2
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"


class BaiduHotSearchCrawler:
    """百度热搜爬虫类"""
    
    def __init__(self, timeout: int = REQUEST_TIMEOUT, max_retries: int = MAX_RETRIES):
        """
        初始化爬虫
        
        Args:
            timeout: 请求超时时间（秒）
            max_retries: 最大重试次数
        """
        self.timeout = timeout
        self.max_retries = max_retries
        self.logger = logging.getLogger(__name__)
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        })
    
    def _make_request_with_retry(self, url: str) -> str:
        """
        带重试机制的HTTP请求
        
        Args:
            url: 请求URL
            
        Returns:
            响应文本内容
            
        Raises:
            RequestException: 请求失败
        """
        last_error = None
        
        for attempt in range(self.max_retries):
            try:
                self.logger.debug(f"发送请求 (尝试 {attempt + 1}/{self.max_retries}): {url}")
                response = self.session.get(url, timeout=self.timeout)
                response.raise_for_status()
                return response.text
                
            except (Timeout, ConnectionError) as e:
                last_error = e
                self.logger.warning(f"请求失败 (尝试 {attempt + 1}/{self.max_retries}): {e}")
                if attempt < self.max_retries - 1:
                    time.sleep(RETRY_DELAY)
                    
            except RequestException as e:
                last_error = e
                self.logger.error(f"HTTP请求错误: {e}")
                raise
        
        raise RequestException(f"请求失败，已重试 {self.max_retries} 次: {last_error}")
    
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
            
            results = []
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
    
    @staticmethod
    def get_utc8_now() -> datetime:
        """
        获取当前UTC+8时间
        
        Returns:
            当前时区的datetime对象
        """
        utc_now = datetime.now(timezone.utc)
        return utc_now.astimezone(timezone(timedelta(hours=8)))
    
    @staticmethod
    def save_as_json(filename: str, records: List[Tuple[str, str]]) -> None:
        """
        保存热搜数据为JSON文件
        
        Args:
            filename: 文件路径
            records: 热搜记录列表
        """
        try:
            Path(filename).parent.mkdir(parents=True, exist_ok=True)
            
            data_dict: Dict[str, List[Dict[str, Any]]] = {}
            
            if os.path.exists(filename):
                try:
                    with open(filename, "r", encoding="utf-8") as f:
                        data_dict = json.load(f, object_pairs_hook=OrderedDict)
                    logging.info(f"已加载现有文件: {filename}")
                except (json.JSONDecodeError, IOError) as e:
                    logging.warning(f"无法读取现有文件，将创建新文件: {e}")
            
            time_str = BaiduHotSearchCrawler.get_utc8_now().isoformat()
            
            for title, hot_index in records:
                if title in data_dict:
                    data_dict[title].append({
                        "time": time_str,
                        "hot_index": hot_index
                    })
                else:
                    data_dict[title] = [{
                        "time": time_str,
                        "hot_index": hot_index
                    }]
            
            with open(filename, "w", encoding="utf-8") as f:
                json.dump(data_dict, f, indent=4, ensure_ascii=False)
            
            logging.info(f"成功保存 {len(records)} 条记录到: {filename}")
            
        except IOError as e:
            logging.error(f"保存文件失败: {e}")
            raise


def setup_logging(level: int = logging.INFO) -> None:
    """
    配置日志系统
    
    Args:
        level: 日志级别
    """
    logging.basicConfig(
        level=level,
        format="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )


def main() -> None:
    """主函数"""
    setup_logging()
    logger = logging.getLogger(__name__)
    
    try:
        crawler = BaiduHotSearchCrawler(timeout=REQUEST_TIMEOUT, max_retries=MAX_RETRIES)
        
        now = BaiduHotSearchCrawler.get_utc8_now()
        year_str = now.strftime("%Y")
        date_str = now.strftime("%Y%m%d")
        
        filename = os.path.join(year_str, f"{date_str} 百度实时热点.json")
        
        logger.info(f"开始执行爬虫任务...")
        records = crawler.crawl_hot_search()
        
        if records:
            crawler.save_as_json(filename, records)
            logger.info("任务执行完成！")
        else:
            logger.warning("未获取到数据，任务终止")
            
    except Exception as e:
        logger.error(f"程序执行失败: {e}")
        raise


if __name__ == "__main__":
    main()
