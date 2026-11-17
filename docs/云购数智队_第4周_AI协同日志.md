# 第 4 周 AI 协同日志

- 团队：云购数智队　成员：孙浩瑜　填写日期：2026-11-17

---

## 一、使用的 AI 工具 / 模型

- 工具名称：WorkBuddy（智能编程助手）　模型版本：GLM 系列（对话模型 + 快速执行模式）
- 任务内大模型：智谱 AI glm-4-flash（NL2SQL 问答与洞察，沿用第 3 周 .env 密钥管理）
- 使用方式：AI 负责 ADS 数据接口导出脚本、ECharts 大屏全栈代码、Streamlit 应用、compose 编排、故障排查；人工负责架构决策（容器内 pyhive 直连方案）、合规把关（中国地图数据源）、逐项验证与最终采纳

---

## 二、AI 协同记录表（至少 5 条）

| 序号 | 提问 / 任务描述 | AI 产出摘要 | 人工修改与验证 | 是否采纳 |
|------|----------------|-------------|----------------|----------|
| 1 | 从 Hive ADS 层导出大屏所需 8 组数据 | AI 生成 beeline 批量导出脚本（含热力图 join 查询），并转 JSON 接口文件 | 人工发现首版未处理 Hive tsv2 的科学计数法（`3.6E7` 被存成字符串）与表头前缀（`ads_kpi_overview.gmv`），AI 修复解析后重导，前端数值校验通过（GMV 3,625.63 万勾稽一致） | 是 |
| 2 | 开发 ECharts 数据大屏（折线/柱状/散点/热力/地图 + scale 自适应） | AI 产出 Flask 后端（/api 白名单接口）+ 1920×1080 大屏（7 图表 + KPI 卡片） | 人工修正 china.json 加载方式（JSON 不能作 script 标签，改 fetch + 注册后再渲染地图）；确认地图使用国标行政区划 GeoJSON（含南海诸岛、台湾省）且未使用境外瓦片源，符合地图合规要求 | 是 |
| 3 | Docker Compose 一键部署（新增 clickhouse / superset / app） | AI 扩展 compose：healthcheck 链（mysql→metastore→hiveserver2→下游）、.env 密钥注入、app 镜像 Dockerfile | 人工决策容器内 NL2SQL 无法 docker exec 的替代方案（pyhive 直连 HIVE_URI 双模式）；部署中 metastore 重启循环，AI 定位根因为 repo 目录下 JDBC 驱动被 Docker 建成空目录，复制真实 jar 后恢复 | 是 |
| 4 | Streamlit 问答应用（历史对话/加载状态/图表渲染） | AI 生成 app.py：pyecharts 自动选型（时间列→折线、少类目→饼图、其余→柱状）+ 复用 nl2sql 只读防线 | 人工重构首版代码结构（函数调用顺序缺陷）；验证容器模式问答闭环：SELECT 1 与区域聚合查询经 pyhive 返回且数值与 ADS 勾稽一致 | 是 |
| 5 | Superset 仪表板搭建 | AI 产出容器内 ORM 初始化脚本（数据源 3 个 + 数据集 9 个 + 图表 8 个 + 仪表板 + 原生筛选器），绕开 CSRF 限制 | 人工发现并要求修正：① region 地图省名不匹配（Superset GADM 用英文 NAME_1），AI 建 CASE WHEN 映射虚拟数据集修复；② CSRF 端点实为 /csrf_token/（AI 首版写错）；③ CH 数据集物理反射失败改虚拟 SQL 方式 | 是 |
| 6 | 查询优化与压力测试 | AI 生成 08_query_optimize.sql（分区裁剪/加盐聚合/ORC 预聚合三组对比）与 stress_test.py（并发压测 + P95 统计） | 人工审阅结果：小数据量下分区裁剪收益仅约 6%（4 并发 5 轮：全表扫 avg 6.08s vs 裁剪 5.69s vs 预聚合 4.62s），要求如实记录而非夸大优化效果 | 是 |
| 7 | 排查部署连环故障 | AI 依次定位：ClickHouse 空密码行为异常（改显式密码重建）、sasl C 扩展编译失败（换 pure-sasl）、Hive 401（tsv2 认证参数）、GADM 省名映射 | 人工逐一复现验证修复效果，全部踩坑记录沉淀入《部署手册》第五节，形成可复用经验库 | 是 |

---

## 三、AI 产出成果清单

- **由 AI 生成的内容**：ADS→JSON 导出与转换脚本；ECharts 大屏全栈（backend/server.py、index.html、main.js、style.css）；streamlit_app/app.py 与 Dockerfile；docker-compose.yml 扩展（3 新服务 + healthcheck）；Superset ORM 初始化脚本；查询优化 SQL 与压测脚本；本手册类文档初稿
- **由人工编写的内容**：容器内 pyhive 直连架构决策；中国地图合规数据源把关；XGBoost 式的"批判性审阅"——否决首版 Streamlit 代码结构、要求如实记录压测结论；部署故障的最终决策与验证
- **人机协作完成的内容**：6 个部署故障的定位与修复（AI 定位、人工验证）；Superset 与数据省名适配方案；安全三防线在 Streamlit 端的复用与注入测试

---

## 四、问题与解决

- **遇到的问题 1**：metastore 重启循环（`ClassNotFoundException com.mysql.cj.jdbc.Driver`）。
- AI 是否有效解决：有效。AI 从"挂载源不存在时 Docker 自动建空目录"这一隐蔽行为定位根因。
- 最终如何解决：复制真实 jar 至 repo lib/ 目录，--force-recreate 恢复；数据经 volume 持久化零丢失。
- **遇到的问题 2**：Superset 区域地图不显色。
- AI 是否有效解决：部分有效。AI 首版未预判 GADM 地图使用英文省名。
- 最终如何解决：建 CASE WHEN 映射虚拟数据集（陕西省→Shaanxi 等 15 省），重指向数据源后修复。
- **遇到的问题 3**：Streamlit 容器内无法执行 docker exec 调 beeline。
- AI 是否有效解决：有效。AI 提出 pyhive 直连方案并实现 HIVE_URI 双模式切换。
- 最终如何解决：容器模式经 pyhive 直连 Thrift 协议，宿主机模式保留原 beeline 路径，共用校验逻辑。
- **遇到的问题 4**：ClickHouse 认证 403/401 反复出现。
- AI 是否有效解决：部分有效。AI 定位到空密码变量行为不确定，但首个脚本自身也有 body 传参 bug。
- 最终如何解决：显式非空密码 + 修正请求体格式（INSERT 语句与 JSONEachRow 数据合并传输）。

---

## 五、反思与总结

- **AI 协同带来的价值**：本周交付面最广（前端大屏、后端接口、BI 平台、容器编排、压测），AI 使单人一天内完成全栈部署成为可能；多次主动验证数据勾稽（GMV 3,625.63 万在 Hive/ClickHouse/大屏三处一致），避免"图表漂亮但数字错误"。
- **AI 的局限与风险**：① 隐蔽环境行为——Docker 对不存在挂载源自动建目录、ClickHouse 空密码行为不确定，AI 无法预知需实测；② 视觉渲染类 bug（地图省名、JSON 作 script 标签）AI 无法"看见"，必须人工在浏览器验证；③ 优化效果存在语境——小数据量下分区裁剪收益有限，AI 生成的方法论结论需按实际数据规模校准表述。
- **本次协作中我的能力提升**：① 掌握了从单服务到 7 服务编排的依赖与健康检查设计；② 理解了"同一代码双执行模式"（beeline/pyhive）的容器化适配思路；③ 建立了部署故障的系统性排查方法：先看退出码与日志根因，再查挂载/网络/依赖顺序。
- **对 AI 协同的改进建议**：① 涉及 bind mount 的 compose 配置，AI 应在生成时提示"确认挂载源文件已存在"；② 可视化产出应默认生成"自检清单"（数据点数、键名匹配、坐标系统一），降低浏览器验证成本；③ 压测/优化类报告应自动附上数据规模说明，防止结论被误读为普适。

---
