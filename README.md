# 百度热搜爬虫

定时爬取百度热搜榜单数据，支持重试机制和日志记录。

## 功能特性

- 爬取百度实时热搜榜单数据
- 支持重试机制，网络不稳定时自动重试
- 完整的日志记录系统
- JSON 格式持久化存储
- 自动按年月创建目录结构
- 面向对象设计，易于扩展

## 安装依赖

```bash
pip install -r requirements.txt
```

依赖说明：
- `requests`: HTTP 请求库
- `beautifulsoup4`: HTML 解析库
- `lxml`: 高性能 XML/HTML 解析器

## 使用方法

### 基本用法

```bash
python crawl_baidu_top.py
```

程序会自动：
1. 爬取当前热搜数据
2. 按 `年份/日期 百度实时热点.json` 格式保存
3. 如文件已存在，则追加新数据

### 输出示例

```
2025-01-15 10:30:00 - INFO - 开始执行爬虫任务...
2025-01-15 10:30:00 - INFO - 开始爬取百度realtime榜单...
2025-01-15 10:30:01 - INFO - 成功爬取 50 条热搜数据
2025-01-15 10:30:01 - INFO - 成功保存 50 条记录到: 2025/20250115 百度实时热点.json
2025-01-15 10:30:01 - INFO - 任务执行完成！
```

### JSON 输出格式

```json
{
    "热搜标题1": [
        {
            "time": "2025-01-15T10:30:01+08:00",
            "hot_index": "999999"
        }
    ],
    "热搜标题2": [
        {
            "time": "2025-01-15T10:30:01+08:00",
            "hot_index": "888888"
        }
    ]
}
```

## 配置说明

可在代码中修改以下常量：

| 常量 | 默认值 | 说明 |
|------|--------|------|
| `REQUEST_TIMEOUT` | 10 | 请求超时时间（秒） |
| `MAX_RETRIES` | 3 | 最大重试次数 |
| `RETRY_DELAY` | 2 | 重试间隔（秒） |

### 自定义配置示例

```python
crawler = BaiduHotSearchCrawler(timeout=15, max_retries=5)
```

## 项目结构

```
├── crawl_baidu_top.py    # 主程序
├── requirements.txt     # 依赖列表
├── README.md           # 项目文档
└── 2025/               # 数据存储目录
    └── 20250115 百度实时热点.json
```

## 参考项目

- https://github.com/quarrying/baidu-top-crawler
- https://github.com/bonfy/github-trending
- https://github.com/JPAdCoder/BaiduTopic-python
