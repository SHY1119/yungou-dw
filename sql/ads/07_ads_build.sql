-- ============================================================
-- 第 3 周 · 子任务 1：ADS 应用层建设与 KPI 指标计算
-- 口径来源：docs/指标定义文档.md
-- 原则：ADS 表直接面向业务场景（看板/日报/排行/分层），
--       只读 DWS 层（或 DWD 聚合），不再做明细级计算
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_ads;

-- ------------------------------------------------------------
-- 一、ads_kpi_overview 核心经营 KPI 总览（看板首屏，单行全周期）
--     GMV / 订单量 / 客单价 / 活跃用户数 / ARPU / 折扣率 / 履约率 / 复购率
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ads.ads_kpi_overview;
CREATE TABLE ydsh_ads.ads_kpi_overview STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  ROUND(a.gmv, 2)                                        AS gmv,
  a.orders,
  ROUND(a.gmv / a.orders, 2)                             AS aov,
  a.active_users,
  ROUND(a.gmv / a.active_users, 2)                       AS arpu,
  ROUND(a.discount / (a.gmv + a.discount), 4)            AS discount_rate,
  ROUND(a.completed_orders / a.orders, 4)                AS fulfillment_rate,
  ROUND(r.rep_users / a.active_users, 4)                 AS repurchase_rate
FROM (
  SELECT
    SUM(pay_amount)                                      AS gmv,
    COUNT(DISTINCT order_id)                             AS orders,
    COUNT(DISTINCT user_id)                              AS active_users,
    SUM(discount_amount)                                 AS discount,
    SUM(CASE WHEN order_status = '已完成' THEN 1 ELSE 0 END) AS completed_orders
  FROM ydsh_dwd.dwd_order
) a
CROSS JOIN (
  SELECT COUNT(*) AS rep_users
  FROM (
    SELECT user_id
    FROM ydsh_dwd.dwd_order
    GROUP BY user_id
    HAVING COUNT(DISTINCT order_id) >= 2
  ) t
) r;

-- ------------------------------------------------------------
-- 二、ads_sales_daily 销售日报（含 GMV 环比，供日报看板）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ads.ads_sales_daily;
CREATE TABLE ydsh_ads.ads_sales_daily STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  order_date,
  orders,
  active_users,
  gmv,
  aov,
  ROUND(100.0 * (gmv - lag_gmv) / lag_gmv, 2)            AS gmv_mom_pct
FROM (
  SELECT
    order_date, orders, active_users, gmv, aov,
    LAG(gmv) OVER (ORDER BY order_date)                  AS lag_gmv
  FROM ydsh_dws.dws_trade_day
) t;

-- ------------------------------------------------------------
-- 三、ads_category_top10 品类销售排行（相对占比口径，见指标文档）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ads.ads_category_top10;
CREATE TABLE ydsh_ads.ads_category_top10 STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  RANK() OVER (ORDER BY item_sales DESC)                 AS rk,
  category,
  items_sold,
  item_sales,
  ROUND(100.0 * item_sales / total.total_sales, 2)       AS sales_pct
FROM (
  SELECT category, SUM(items_sold) AS items_sold, ROUND(SUM(item_sales), 2) AS item_sales
  FROM ydsh_dws.dws_trade_category_day
  GROUP BY category
) c
CROSS JOIN (
  SELECT SUM(item_sales) AS total_sales
  FROM ydsh_dws.dws_trade_category_day
) total;

-- ------------------------------------------------------------
-- 四、ads_store_top10 门店销售排行
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ads.ads_store_top10;
CREATE TABLE ydsh_ads.ads_store_top10 STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT *
FROM (
  SELECT
    RANK() OVER (ORDER BY gmv DESC)                      AS rk,
    s.store_name,
    s.city,
    t.orders,
    t.gmv,
    ROUND(t.gmv / t.orders, 2)                           AS aov
  FROM (
    SELECT store_id, SUM(orders) AS orders, ROUND(SUM(gmv), 2) AS gmv
    FROM ydsh_dws.dws_store_day
    GROUP BY store_id
  ) t
  JOIN ydsh_dwd.dim_store s ON t.store_id = s.store_id
) x
WHERE rk <= 10;

-- ------------------------------------------------------------
-- 五、ads_region_sales 区域销售（用户归属省份口径）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ads.ads_region_sales;
CREATE TABLE ydsh_ads.ads_region_sales STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  province,
  SUM(users)                                             AS users,
  SUM(orders)                                            AS orders,
  ROUND(SUM(gmv), 2)                                     AS gmv,
  ROUND(SUM(gmv) / SUM(orders), 2)                       AS aov
FROM ydsh_dws.dws_region_day
GROUP BY province;

-- ------------------------------------------------------------
-- 六、ads_user_value 用户价值五层分层（按全年累计消费 NTILE(5)，R5 最高）
--     口径说明：单一消费金额维度，不引入 RFM（行为数据与订单无会话关联）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_ads.ads_user_value;
CREATE TABLE ydsh_ads.ads_user_value STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  tier,
  COUNT(*)                                               AS users,
  ROUND(SUM(u_gmv), 2)                                   AS gmv,
  ROUND(SUM(u_orders), 1)                                AS orders,
  ROUND(AVG(u_gmv), 2)                                   AS avg_user_gmv,
  ROUND(100.0 * SUM(u_gmv) / SUM(SUM(u_gmv)) OVER (), 2) AS gmv_pct
FROM (
  SELECT user_id, SUM(gmv) AS u_gmv, SUM(orders) AS u_orders,
         NTILE(5) OVER (ORDER BY SUM(gmv) DESC)           AS tier
  FROM ydsh_dws.dws_user_month
  GROUP BY user_id
) t
GROUP BY tier;

-- ------------------------------------------------------------
-- 七、验证：核心 KPI 输出
-- ------------------------------------------------------------
SELECT * FROM ydsh_ads.ads_kpi_overview;
SELECT * FROM ydsh_ads.ads_category_top10 ORDER BY rk;
SELECT * FROM ydsh_ads.ads_user_value ORDER BY tier;
