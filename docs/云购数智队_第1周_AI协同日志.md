# 云购数智队_第1周_AI协同日志

> 课程：企业项目实战实训 · 第 1 周（项目启动 · 环境搭建 · Git 基础 · 数据导入与清洗一）
> 队名：云购数智队　成员：孙浩瑜
> 记录原则：如实记录本周与 AI 工具协同完成各项任务的过程、产出与反思。

## 一、使用的工具 / 模型

| 工具 / 模型 | 使用场景 | 使用方式 |
|---|---|---|
| WorkBuddy（Claude 模型） | 环境搭建、docker-compose 编排、数据导入、质量预评估、清洗脚本、Git 管理 | 对话式协同，Agent 直接操作本地终端与文件 |
| Docker Desktop | Hive/MySQL 容器化运行 | 配合 AI 生成的 compose 文件使用 |
| Apache Hive 4.0.1 / MySQL 8.0 | 数仓底座 | 容器内 beeline 执行 AI 生成并经人工确认的 SQL |
| Git + GitHub | 版本管理与远程推送 | SSH 密钥认证，规范提交 |

## 二、协同记录表

| # | 时间 | 任务 | 我的输入 / 决策 | AI 的产出 | 结果 |
|---|---|---|---|---|---|
| 1 | 10-26 上午 | 编写 docker-compose.yml | 明确需求：MySQL 作为 Metastore 元数据库 + Metastore + HiveServer2 三服务编排 | 生成完整 compose 文件，含健康检查、数据卷、依赖顺序 | ✅ 采纳 |
| 2 | 10-26 上午 | 启动服务排错 | 反馈 `registry-1.docker.io` 连接超时 | 判断为国内网络问题，改用 DaoCloud 镜像源拉取并重打 tag | ✅ 成功启动 |
| 3 | 10-26 上午 | 端口冲突处理 | 反馈 3306 被占用报错 | 定位为本机 MySQL 服务冲突，改为 `3307:3306` 映射 | ✅ 成功启动 |
| 4 | 10-26 上午 | Metastore 反复重启 | 提供容器日志（ClassNotFoundException: com.mysql.cj.jdbc.Driver） | 判断镜像缺 MySQL 驱动，下载 mysql-connector-j-8.0.33.jar 挂载进容器 | ✅ schema 初始化成功 |
| 5 | 10-27 上午 | ODS 建表与导入 | 提供 6 张 CSV 与数据字典 | 生成 create_ods.sql / load_ods.sql（含类型设计、skip.header.line.count），容器内执行 load data | ✅ 行数与字典完全一致 |
| 6 | 10-27 上午 | 五维度质量预评估 | 确认评估维度口径 | 生成 quality_check.sql 并执行，产出空值/重复/异常取值/格式/准确性统计 | ✅ 发现订单重复 600 行等 7 类问题 |
| 7 | 10-27 上午 | 缺失值与重复值清洗 | 确认策略：年龄按性别中位数填充、邮箱保留标记、日期同类目补全 | 生成 missing_value.sql / dedup.sql，dwd_user/dwd_product/dwd_order 校验全部通过 | ✅ 去重 15600→15000 |
| 8 | 10-27 上午 | Git 与远程推送 | 提供真实姓名/邮箱/GitHub 用户名 | 初始化仓库、6 次规范提交、生成 SSH 密钥、修复中文用户名 SSH 编码问题、推送 GitHub | ✅ 全部推送成功 |

## 三、产出成果清单

1. `docker-compose.yml`（三服务编排，可一键启动）
2. `docs/环境搭建笔记.md`（4 个典型问题与解决记录）
3. `.gitignore` + 7 次规范提交（远程仓库 github.com/SHY1119/yungou-dw）
4. `sql/ods/create_ods.sql`、`sql/ods/load_ods.sql`（6 张表行数校验通过）
5. `sql/quality/quality_check.sql` + `docs/数据质量预评估表.md/.xlsx`
6. `sql/clean/missing_value.sql`、`sql/clean/dedup.sql`（清洗校验全部通过）
7. `README.md`（团队信息/分工/目标/计划/技术栈）

## 四、问题与解决

| 问题 | 根因 | AI 给出的解决 | 效果 |
|---|---|---|---|
| Docker Hub 拉取超时 | 国内网络直连受限 | 镜像源拉取 + 重 tag | 解决 |
| 宿主机 3306 冲突 | 本机已装 MySQL | 改映射端口 3307 | 解决 |
| Metastore 起不来 | 镜像无 MySQL JDBC 驱动 | 挂载 connector jar | 解决 |
| beeline 报 `No FileSystem for scheme "C"` | Git Bash 路径转换把容器路径改写为 Windows 路径 | 加 `MSYS_NO_PATHCONV=1` 禁用转换 | 解决 |
| ssh 报 Permission denied 且路径乱码 | Git 自带 ssh 不支持中文用户名路径 | `core.sshCommand` 改用系统 OpenSSH | 解决 |
| `update` 语句在 Hive 报错（手册示例） | Hive 普通表不支持 UPDATE | 改用 CTAS + 窗口函数重建清洗目标表 | 解决 |

## 五、反思与总结

1. **AI 显著提效的环节**：排错诊断（日志→根因→方案）、SQL 脚本生成、Git 流程操作。第 1 周原计划 10 课时的实操，在 AI 协同下压缩到约 3 课时完成，且校验结果均达到验收标准。
2. **必须人工把关的环节**：清洗策略的业务合理性（如"年龄按性别中位数填充"的决策）、提交内容的真实性与规范、对每条 AI 建议的验证后再采纳。AI 输出不能直接照搬，例如任务书示例中的 `UPDATE` 语句在 Hive 中并不适用，需要按数仓规范改为 CTAS。
3. **经验沉淀**：遇到报错时把完整日志贴给 AI 比描述现象更高效；环境类问题（网络、端口、编码）优先怀疑本机环境差异而非脚本本身。
4. **下周改进**：让 AI 生成的 SQL 增加 more 注释说明每步业务含义，便于团队评审；清洗二的枚举归一化考虑建立映射表而非硬编码 CASE WHEN。
