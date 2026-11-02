-- ============================================================
-- 第 2 周 · 子任务 7：探索性数据分析（EDA）
-- 数据源：ydsh_dwd 层（dim_user / dim_product / dim_store / dwd_order / dwd_order_item / dwd_behavior）
-- 口径：GMV = SUM(pay_amount)；客单价 = GMV / 订单数；均为已清洗数据
-- ============================================================

-- ---------- 1. 核心经营指标 ----------
SELECT
  COUNT(DISTINCT order_id)                     AS order_cnt,
  COUNT(DISTINCT user_id)                      AS user_cnt,
  ROUND(SUM(pay_amount), 2)                    AS gmv,
  ROUND(SUM(pay_amount) / COUNT(DISTINCT order_id), 2) AS aov,
  ROUND(SUM(discount_amount), 2)               AS discount_total,
  ROUND(100.0 * SUM(discount_amount) / SUM(pay_amount + discount_amount), 2) AS discount_rate_pct
FROM ydsh_dwd.dwd_order;

-- ---------- 2. 订单状态结构（含取消率） ----------
SELECT order_status, COUNT(*) AS cnt,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM ydsh_dwd.dwd_order GROUP BY order_status ORDER BY cnt DESC;

-- ---------- 3. 支付方式 / 渠道分布 ----------
SELECT pay_type, COUNT(*) AS cnt, ROUND(SUM(pay_amount), 2) AS gmv
FROM ydsh_dwd.dwd_order GROUP BY pay_type ORDER BY gmv DESC;

SELECT channel, COUNT(*) AS cnt, ROUND(SUM(pay_amount), 2) AS gmv,
       ROUND(SUM(pay_amount) / COUNT(*), 2) AS aov
FROM ydsh_dwd.dwd_order GROUP BY channel ORDER BY gmv DESC;

-- ---------- 4. 品类销售分布（明细口径） + 品类内排名 ----------
SELECT rn, category, item_qty, sales, ROUND(100.0 * sales / SUM(sales) OVER (), 2) AS pct
FROM (
  SELECT ROW_NUMBER() OVER (ORDER BY SUM(i.item_amount) DESC) AS rn,
         p.category,
         SUM(i.quantity)      AS item_qty,
         ROUND(SUM(i.item_amount), 2) AS sales
  FROM ydsh_dwd.dwd_order_item i
  JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
  GROUP BY p.category
) t ORDER BY rn;

-- ---------- 5. 省份销售分布（用户归属地口径） ----------
SELECT u.province, COUNT(DISTINCT o.order_id) AS orders, COUNT(DISTINCT o.user_id) AS users,
       ROUND(SUM(o.pay_amount), 2) AS gmv,
       ROUND(SUM(o.pay_amount) / COUNT(DISTINCT o.order_id), 2) AS aov
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
GROUP BY u.province ORDER BY gmv DESC LIMIT 15;

-- ---------- 6. 门店 TOP10（销售额 / 单量 / 覆盖品类数） ----------
SELECT s.store_id, s.store_name, s.city, COUNT(*) AS orders,
       ROUND(SUM(o.pay_amount), 2) AS gmv,
       ROUND(SUM(o.pay_amount) / COUNT(*), 2) AS aov
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_store s ON o.store_id = s.store_id
GROUP BY s.store_id, s.store_name, s.city
ORDER BY gmv DESC LIMIT 10;

-- ---------- 7. 月度 GMV 趋势（含环比） ----------
SELECT ym, orders, gmv,
       LAG(gmv) OVER (ORDER BY ym) AS prev_gmv,
       ROUND(100.0 * (gmv - LAG(gmv) OVER (ORDER BY ym)) / LAG(gmv) OVER (ORDER BY ym), 2) AS mom_pct
FROM (
  SELECT SUBSTR(order_date, 1, 7) AS ym, COUNT(*) AS orders, ROUND(SUM(pay_amount), 2) AS gmv
  FROM ydsh_dwd.dwd_order GROUP BY SUBSTR(order_date, 1, 7)
) t ORDER BY ym;

-- ---------- 8. 会员等级贡献 ----------
SELECT u.member_level, COUNT(DISTINCT u.user_id) AS users,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(o.pay_amount), 2) AS gmv,
       ROUND(SUM(o.pay_amount) / COUNT(DISTINCT u.user_id), 2) AS arpu
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
GROUP BY u.member_level ORDER BY gmv DESC;

-- ---------- 9. 复购分析：下单次数分布 + 复购率 ----------
SELECT order_times, COUNT(*) AS user_cnt FROM (
  SELECT user_id, COUNT(*) AS order_times FROM ydsh_dwd.dwd_order GROUP BY user_id
) t GROUP BY order_times ORDER BY order_times LIMIT 12;

SELECT ROUND(100.0 * SUM(CASE WHEN order_times >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repurchase_rate_pct,
       COUNT(*) AS buyer_cnt
FROM (SELECT user_id, COUNT(*) AS order_times FROM ydsh_dwd.dwd_order GROUP BY user_id) t;

-- ---------- 10. 窗口函数：用户累计消费与消费排名（示例 10 行） ----------
SELECT user_id, order_date, pay_amount,
       SUM(pay_amount) OVER (PARTITION BY user_id ORDER BY order_timestamp
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_amount,
       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_timestamp) AS seq_no
FROM ydsh_dwd.dwd_order
WHERE user_id = 'U000001' ORDER BY order_timestamp;

-- ---------- 11. 用户消费 TOP10（RANK） ----------
SELECT rk, user_id, orders, gmv FROM (
  SELECT RANK() OVER (ORDER BY SUM(pay_amount) DESC) AS rk,
         user_id, COUNT(*) AS orders, ROUND(SUM(pay_amount), 2) AS gmv
  FROM ydsh_dwd.dwd_order GROUP BY user_id
) t WHERE rk <= 10 ORDER BY rk;

-- ---------- 12. 行为漏斗（去重用户） ----------
SELECT behavior_type,
       COUNT(*) AS events,
       COUNT(DISTINCT user_id) AS users,
       COUNT(DISTINCT product_id) AS products
FROM ydsh_dwd.dwd_behavior GROUP BY behavior_type ORDER BY events DESC;

-- ---------- 13. 高价值品类识别：客单价 vs 销量（象限判断用） ----------
SELECT p.category,
       SUM(i.quantity) AS qty,
       ROUND(SUM(i.item_amount), 2) AS sales,
       ROUND(SUM(i.item_amount) / SUM(i.quantity), 2) AS unit_avg
FROM ydsh_dwd.dwd_order_item i
JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
GROUP BY p.category ORDER BY unit_avg DESC;
