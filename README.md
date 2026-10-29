# 云购生活新零售 —— 企业级数据仓库与经营分析可视化系统

> 课程：企业项目实战实训（数据科学与大数据技术）
> 团队仓库 · 第 1 周：项目启动 · 环境搭建 · Git 基础 · 数据导入与数据清洗（一）

## 团队信息

- **队名**：云购数智队
- **口号**：数据驱动零售，智慧创造生活
| 角色 | 成员 | 职责 |
|---|---|---|
| 项目经理（兼数仓工程师） | 孙浩瑜 | 统筹进度、数仓架构设计、Git 版本管理 |
| 数据工程师 | 孙浩瑜 | 数据导入、清洗、ODS/DWD 建模与 ETL 脚本 |
| 数据分析师 | 孙浩瑜 | 数据质量预评估、探索性分析 |
| 可视化/部署工程师 | 孙浩瑜 | Docker 部署、环境运维、文档 |

## 技术栈

| 类别 | 技术 / 工具 |
|---|---|
| 数据仓库 | Apache Hive 4.0.1（ODS→DWD→DWS→ADS） |
| 关系型数据库 | MySQL 8.0（Metastore 元数据库、ADS 结果回写） |
| 容器化部署 | Docker + Docker Compose |
| 版本控制 | Git + GitHub |
| 后续引入 | Python(pandas/sklearn)、大模型 API(NL2SQL)、Superset/ECharts |

## 项目目标

基于"云购生活"新零售企业 2024 年全年模拟经营数据（6 张表、11 万+ 条），搭建
ODS → DWD → DWS → ADS 四层数仓，完成数据清洗、经营分析与可视化呈现。

## 阶段计划

| 周次 | 主题 | 状态 |
|---|---|---|
| 第 1 周 | 环境搭建、Git 规范、ODS 导入、数据质量预评估、清洗（一） | ✅ 进行中 |
| 第 2 周 | 数据清洗（二）与数仓建模 | ⏳ |
| 第 3 周 | KPI 指标计算与探索性分析 | ⏳ |
| 第 4 周 | AI 智能洞察（NL2SQL） | ⏳ |
| 第 5 周 | 可视化大屏与综合答辩 | ⏳ |

## 仓库结构

```
yungou-dw/
├── docker-compose.yml        # MySQL + Hive Metastore + HiveServer2 编排
├── docs/                     # 文档（环境搭建笔记、数据质量预评估表）
├── sql/
│   ├── ods/                  # ODS 层建表与数据导入脚本
│   ├── clean/                # 数据清洗脚本（缺失值、重复值）
│   └── quality/              # 数据质量五维度扫描脚本
├── scripts/                  # 辅助脚本
└── data/                     # 模拟数据（.csv 已 gitignore，不入库）
```

## 环境启动

```bash
docker compose up -d     # 启动 MySQL / Hive Metastore / HiveServer2
docker ps                # 验证三个容器均为 Up
```

- HiveServer2 JDBC：`jdbc:hive2://localhost:10000`（beeline -n hive）
- MySQL 元数据库：`127.0.0.1:3307`（hive/hive123，库名 metastore）
- HiveServer2 Web UI：http://localhost:10002

## 提交规范（Conventional Commits）

`feat:` 新功能 · `fix:` 修复 · `docs:` 文档 · `sql:` 数仓脚本 · `chore:` 杂项
