-- ============================================================
-- 第 4 周 · 子任务 5：Hive 查询优化对比实验
-- 目标：验证分区裁剪 / 数据倾斜规避对查询耗时的影响
-- 执行：beeline 逐条运行，耗时记录见 docs/部署手册.md 与 scripts/stress_test.py 输出
-- ============================================================

-- ------------------------------------------------------------
-- 实验 1：分区裁剪
-- 同一业务口径（2024-11 订单金额汇总），两种写法对比
-- ------------------------------------------------------------

-- 写法 A（未裁剪）：对非分区列 order_timestamp 做函数过滤 → 全表扫描 366 个分区
SELECT SUM(pay_amount) AS gmv
FROM ydsh_dwd.dwd_order
WHERE SUBSTR(order_timestamp, 1, 7) = '2024-11';

-- 写法 B（分区裁剪）：直接过滤分区列 order_date → 仅扫描 30 个分区
SELECT SUM(pay_amount) AS gmv
FROM ydsh_dwd.dwd_order
WHERE order_date BETWEEN '2024-11-01' AND '2024-11-30';

-- 验证分区裁剪生效（EXPLAIN 计划中只出现目标分区）
EXPLAIN
SELECT SUM(pay_amount)
FROM ydsh_dwd.dwd_order
WHERE order_date BETWEEN '2024-11-01' AND '2024-11-30';

-- ------------------------------------------------------------
-- 实验 2：数据倾斜规避（大 key 加盐打散）
-- 场景：按 user_id 统计行为次数，头部用户行为量远超均值造成 reducer 长尾
-- ------------------------------------------------------------

-- 写法 A（未处理倾斜）：直接 GROUP BY
SELECT user_id, COUNT(1) AS cnt
FROM ydsh_dwd.dwd_behavior
GROUP BY user_id
ORDER BY cnt DESC
LIMIT 10;

-- 写法 B（两阶段加盐聚合）：先加盐局部聚合，再去盐全局聚合
WITH salted AS (
  SELECT
    CONCAT(user_id, '_', CAST(FLOOR(RAND() * 10) AS STRING)) AS salt_key,
    1 AS one
  FROM ydsh_dwd.dwd_behavior
),
partial AS (
  SELECT salt_key, COUNT(1) AS cnt
  FROM salted
  GROUP BY salt_key
)
SELECT
  SPLIT(salt_key, '_')[0] AS user_id,
  SUM(cnt) AS cnt
FROM partial
GROUP BY SPLIT(salt_key, '_')[0]
ORDER BY cnt DESC
LIMIT 10;

-- ------------------------------------------------------------
-- 实验 3：ORC 列式存储 + 谓词下推验证
-- ads 层表为 STORED AS ORC（SNAPPY），对比 dwd 层 TEXTORC?  dwd 为 text。
-- 观察：同口径聚合在 ORC 表（ads_sales_daily 已预聚合）与明细表上的耗时差异
-- ------------------------------------------------------------

-- 明细层实时聚合（扫描 14399 行订单全量）
SELECT COUNT(1) AS orders, SUM(pay_amount) AS gmv
FROM ydsh_dwd.dwd_order;

-- ADS 预聚合表（ORC，仅 366 行）：应明显更快
SELECT SUM(orders) AS orders, SUM(gmv) AS gmv
FROM ydsh_ads.ads_sales_daily;
