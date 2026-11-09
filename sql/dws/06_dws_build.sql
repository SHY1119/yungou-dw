-- ============================================================
-- 第 3 周 · 子任务 1：DWS 汇总层建设
-- 口径来源：docs/指标定义文档.md（唯一口径来源）
-- 分层约定：每张表只依赖 DWD 层，禁止跨层引用
-- 存储：ORC + SNAPPY；CTAS 全量重建，可幂等重跑
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dws;

-- ------------------------------------------------------------
-- 一、dws_trade_day 交易主题日汇总（订单粒度 → 日粒度）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dws.dws_trade_day;
CREATE TABLE ydsh_dws.dws_trade_day STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  order_date,
  COUNT(DISTINCT order_id)                                AS orders,
  COUNT(DISTINCT user_id)                                 AS active_users,
  ROUND(SUM(pay_amount), 2)                               AS gmv,
  ROUND(SUM(discount_amount), 2)                          AS discount,
  ROUND(SUM(pay_amount) / COUNT(DISTINCT order_id), 2)    AS aov,
  SUM(CASE WHEN order_status = '已完成' THEN 1 ELSE 0 END) AS completed_orders
FROM ydsh_dwd.dwd_order
GROUP BY order_date;

-- ------------------------------------------------------------
-- 二、dws_trade_month 交易主题月汇总
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dws.dws_trade_month;
CREATE TABLE ydsh_dws.dws_trade_month STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  SUBSTR(order_date, 1, 7)                                AS month,
  COUNT(DISTINCT order_id)                                AS orders,
  COUNT(DISTINCT user_id)                                 AS active_users,
  ROUND(SUM(pay_amount), 2)                               AS gmv,
  ROUND(SUM(pay_amount) / COUNT(DISTINCT order_id), 2)    AS aov
FROM ydsh_dwd.dwd_order
GROUP BY SUBSTR(order_date, 1, 7);

-- ------------------------------------------------------------
-- 三、dws_trade_category_day 品类交易日汇总
--     口径说明：金额为明细金额（相对占比口径），绝对 GMV 以订单表为准
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dws.dws_trade_category_day;
CREATE TABLE ydsh_dws.dws_trade_category_day STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  i.order_date,
  p.category,
  SUM(i.quantity)                                         AS items_sold,
  ROUND(SUM(i.item_amount), 2)                            AS item_sales
FROM ydsh_dwd.dwd_order_item i
JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
GROUP BY i.order_date, p.category;

-- ------------------------------------------------------------
-- 四、dws_store_day 门店交易日汇总
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dws.dws_store_day;
CREATE TABLE ydsh_dws.dws_store_day STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  o.store_id,
  o.order_date,
  COUNT(DISTINCT o.order_id)                              AS orders,
  COUNT(DISTINCT o.user_id)                               AS users,
  ROUND(SUM(o.pay_amount), 2)                             AS gmv
FROM ydsh_dwd.dwd_order o
GROUP BY o.store_id, o.order_date;

-- ------------------------------------------------------------
-- 五、dws_region_day 区域交易日汇总（区域 = 用户归属省份，口径见指标文档）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dws.dws_region_day;
CREATE TABLE ydsh_dws.dws_region_day STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  u.province,
  o.order_date,
  COUNT(DISTINCT o.order_id)                              AS orders,
  COUNT(DISTINCT o.user_id)                               AS users,
  ROUND(SUM(o.pay_amount), 2)                             AS gmv
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
GROUP BY u.province, o.order_date;

-- ------------------------------------------------------------
-- 六、dws_user_month 用户月度消费汇总
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dws.dws_user_month;
CREATE TABLE ydsh_dws.dws_user_month STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY') AS
SELECT
  SUBSTR(order_date, 1, 7)                                AS month,
  user_id,
  COUNT(DISTINCT order_id)                                AS orders,
  ROUND(SUM(pay_amount), 2)                               AS gmv
FROM ydsh_dwd.dwd_order
GROUP BY SUBSTR(order_date, 1, 7), user_id;

-- ------------------------------------------------------------
-- 七、验证：行数与抽样
-- ------------------------------------------------------------
SELECT 'dws_trade_day' AS t, COUNT(*) AS rows_cnt, ROUND(SUM(gmv),2) AS gmv_sum FROM ydsh_dws.dws_trade_day;
SELECT 'dws_trade_month', COUNT(*), ROUND(SUM(gmv),2) FROM ydsh_dws.dws_trade_month;
SELECT 'dws_trade_category_day', COUNT(*), ROUND(SUM(item_sales),2) FROM ydsh_dws.dws_trade_category_day;
SELECT 'dws_store_day', COUNT(*), ROUND(SUM(gmv),2) FROM ydsh_dws.dws_store_day;
SELECT 'dws_region_day', COUNT(*), ROUND(SUM(gmv),2) FROM ydsh_dws.dws_region_day;
SELECT 'dws_user_month', COUNT(*), ROUND(SUM(gmv),2) FROM ydsh_dws.dws_user_month;
