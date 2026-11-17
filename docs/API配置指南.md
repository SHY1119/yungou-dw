# API 配置指南（大模型 / 数据源接口）

- 团队：云购数智队　成员：孙浩瑜　日期：2026-11-17

---

## 一、大模型 API（NL2SQL / AI 洞察）

### 1.1 服务选择

系统使用智谱 AI 开放平台 **glm-4-flash**（免费模型，OpenAI 兼容协议）。任何 OpenAI 协议服务均可替换（DeepSeek / 通义 DashScope 等），仅需改 `.env` 三行配置。

### 1.2 配置方式（密钥安全管理）

**宿主机运行**（NL2SQL 脚本 / 洞察脚本）：

```bash
# scripts/nl2sql/.env（该文件已被 .gitignore 排除）
LLM_API_KEY=你的APIKey
LLM_BASE_URL=https://open.bigmodel.cn/api/paas/v4/
LLM_MODEL=glm-4-flash
```

**容器运行**（Streamlit app）：密钥经根目录 `.env` → `docker-compose.yml` `environment` 注入容器环境变量，镜像内无明文：

```yaml
app:
  environment:
    LLM_API_KEY: ${LLM_API_KEY}
    LLM_BASE_URL: ${LLM_BASE_URL:-https://open.bigmodel.cn/api/paas/v4/}
    LLM_MODEL: ${LLM_MODEL:-glm-4-flash}
```

### 1.3 最小化调用验证

```python
from openai import OpenAI
client = OpenAI(api_key=os.environ['LLM_API_KEY'],
                base_url=os.environ['LLM_BASE_URL'])
resp = client.chat.completions.create(
    model='glm-4-flash', temperature=0, max_tokens=512,
    messages=[{'role': 'user', 'content': '你好，请回复“连通正常”'}])
print(resp.choices[0].message.content)
```

### 1.4 Key 轮换与安全规范

- 轮换：智谱控制台生成新 Key → 更新 `.env` → `docker compose up -d app --force-recreate`
- 禁止硬编码：代码中只读 `os.environ`；提交前用 `git log -p | grep -i "api_key"` 自查历史
- 最小权限：该 Key 仅用于文本生成（NL2SQL/洞察），不授权文件/外部调用类权限

## 二、Hive 接口（NL2SQL 执行层）

| 模式 | 触发条件 | 用途 |
|---|---|---|
| beeline + docker exec | 默认（宿主机） | 开发调试，无额外依赖 |
| pyhive 直连 Thrift | 环境变量 `HIVE_URI=hive://hive@hiveserver2:10000/default?auth=NONE` | 容器内运行（Streamlit app） |

切换实现位于 `scripts/nl2sql/nl2sql.py` 的 `execute_sql()`：检测到 `HIVE_URI` 即走 pyhive，否则走 docker exec。两种模式共用同一套 Prompt / 校验逻辑，行为一致。

## 三、ClickHouse 加速层接口

```bash
# 健康检查
curl http://localhost:8123/ping            # -> Ok.

# 带认证查询（密码经 .env 注入）
curl -u default:<CLICKHOUSE_PASSWORD> "http://localhost:8123/?query=SELECT%201"
```

当前同步表：`ads.ads_sales_daily`（366 行销售日报，与 Hive ADS 勾稽一致，GMV 3,625.63 万）。
同步方式：ADS 导出 JSON → HTTP 接口 `INSERT ... FORMAT JSONEachRow`（脚本化，可定期重跑）。

## 四、数据大屏 JSON 接口（Flask）

启动：`cd vis/backend && python server.py`（端口 5000）

| 接口 | 数据内容 | 来源 |
|---|---|---|
| GET /api/kpi_overview | GMV/订单量/客单价/活跃用户/ARPU/履约率 | ads_kpi_overview |
| GET /api/sales_daily | 366 天 GMV/订单/客单价/环比 | ads_sales_daily |
| GET /api/category_top10 | 品类 Top10 销售额与占比 | ads_category_top10 |
| GET /api/region | 15 省 GMV/订单/用户数 | ads_region_sales |
| GET /api/pay_type | 4 类支付方式 GMV/订单量 | dwd_order 聚合 |
| GET /api/heatmap | 24 小时 × 8 品类 GMV | dwd_order_item join dim_product |
| GET /api/store_top10 | 门店 Top10 | ads_store_top10 |
| GET /api/user_value | 4 层用户价值 | ads_user_value |

安全设计：接口名白名单（`ALLOWED` 集合），杜绝路径穿越；数据由 Hive 导出脚本生成（`data/wk4_export_tmp` → `vis/api_data/*.json`）。

## 五、Superset REST API（可选自动化）

登录 → 取 CSRF → 调用（注意 4.1 版本 CSRF 端点为 `/api/v1/security/csrf_token/`）：

```python
import requests
s = requests.Session()
token = s.post(BASE + '/api/v1/security/login',
               json={'username': 'admin', 'password': '***',
                     'provider': 'db', 'refresh': True}).json()['access_token']
csrf = s.get(BASE + '/api/v1/security/csrf_token/').json()['result']
s.headers.update({'Authorization': f'Bearer {token}', 'X-CSRF-Token': csrf,
                  'Referer': BASE + '/'})
# 创建数据源
s.post(BASE + '/api/v1/database/', json={'database_name': '...',
        'sqlalchemy_uri': 'hive://hive@hiveserver2:10000/ydsh_ads?auth=NONE'})
```

## 六、端口速查

| 服务 | 地址 |
|---|---|
| Superset 仪表板 | http://localhost:8088/superset/dashboard/1/ |
| ECharts 大屏 | http://localhost:5000/ |
| Streamlit 问答 | http://localhost:8501/ |
| HiveServer2 Web UI | http://localhost:10002/ |
| ClickHouse HTTP | http://localhost:8123/ |
