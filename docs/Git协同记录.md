# Git 协同实战记录（第 3 周）

> 团队：云购数智队　成员：孙浩瑜（单人团队）　日期：2026-11-09
> 仓库：https://github.com/SHY1119/yungou-dw

## 一、流程说明（Fork 工作流的适配）

任务书要求 Fork 工作流。因本团队为单人团队，仓库属本人所有，Fork 自己的仓库无实际意义，故采用**分支工作流**（branch-based workflow）完整走通同等环节：`feature 分支开发 → push → Pull Request → Code Review → 合并 → 分支清理`。PR/Review/Issue 记录均可在 GitHub 上追溯，与 Fork 工作流的评审环节一致。

## 二、实操时间线（可追溯）

| 环节 | 操作 | 记录位置 |
|---|---|---|
| 1. 功能分支开发 | `git checkout -b feature/nl2sql`，提交 NL2SQL 接口、洞察脚本、AI 文档、字符集缺陷修复 | 提交 `f14f76f`、`f3b5e44`、`93c52d7` |
| 2. 制造真实冲突 | main 与 feature 分支**同时修改 README.md 第 38 行**（阶段状态行），各自提交 | main `b61ed0f` vs feature `f3b5e44` |
| 3. 合并与冲突解决 | `git merge main` 触发 `CONFLICT (content): Merge conflict in README.md`；手工合并双方表述（保留 main 的 MAPE 结论 + feature 的 NL2SQL 进展），`git add` 后提交 merge commit | merge commit `ecc1182` |
| 4. 推送分支 | `git push -u origin feature/nl2sql` | 远程新分支 |
| 5. Pull Request | GitHub API 创建 **PR #2**《feat: NL2SQL 智能问答接口 + AI 智能洞察》，描述含变更清单与自测结果 | https://github.com/SHY1119/yungou-dw/pull/2 |
| 6. Code Review | 在 PR 上提交评审意见（COMMENT）：✅Prompt 三防线 / ✅密钥管理 / ⚠️2 条不阻塞建议（表头过滤显式化、JOIN 边界用例） | PR #2 Reviews |
| 7. 合并 | merge 方式合并，生成 merge commit `41ad743` | PR #2 Merged |
| 8. Issue 追踪 | **Issue #1**（bug：metastore 字符集乱码）随修复验证后关闭；**Issue #3**（enhancement：Review 建议的改进项）登记待办 | Issues 页 |
| 9. 版本标记 | `git tag -a v1.0-week3` 并推送 | Tags 页 |
| 10. 分支清理 | 删除本地与远程 `feature/nl2sql`（PR 页保留完整记录） | — |

## 三、合并冲突解决过程（详录）

1. **冲突制造**：在 feature 分支将 README 第 38 行改为「🚧 feature/nl2sql 开发中」并提交；切回 main 将同一行改为「✅ 预测模型 MAPE 13.89%」并提交推送——两个分支对同一行产生了不可自动合并的分歧。
2. **冲突表现**：`git merge main` 输出 `Auto-merging README.md / CONFLICT (content)`，`git status` 显示 `UU README.md`（双方都修改）。
3. **解决策略**：该行是阶段状态描述，正确做法是**融合双方信息**而非二选一——最终版为「DWS/ADS 建设、KPI 指标计算与预测建模（MAPE 13.89%）完成；NL2SQL 智能问答接口经 PR 评审合入 ✅」。
4. **解决方式**：用 Python 脚本按 `<<<<<<< / ======= / >>>>>>>` 标记定位冲突块并替换，`git add` 标记已解决，提交 merge commit `ecc1182`。
5. **经验**：冲突解决的核心是判断语义归属——README 的阶段行属于"双方各有部分事实"的场景，应合并；若是代码逻辑冲突，则必须回溯两侧意图后再定。

## 四、单人团队下的 Review 有效性

GitHub 不允许 Approve 自己的 PR（实测返回 422），本次采用 COMMENT 型 Review 留痕。评审中提出的 2 条建议（beeline_rows 表头过滤显式化、测试集补充 JOIN 边界用例）已登记为 Issue #3 进入待办，形成"评审 → Issue → 闭环"链路。多人场景下建议配置分支保护规则（require 1 approval）强制交叉评审。
