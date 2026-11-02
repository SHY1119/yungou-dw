-- ============================================================
-- 第 2 周 · 子任务 2 + 3：异常值处理、格式标准化、字段拆分合并
-- 输入：ydsh_dwd.stg_*_enum（枚举已标准化）
-- 输出：ydsh_dwd.stg_user / stg_product / stg_store / stg_order / stg_order_item / stg_behavior
--
-- 处理规则（阈值依据见 docs/数据质量清洗报告.md）：
--   金额 pay_amount ：<=0 或 >10000       → 整单剔除（无法推断真实值）
--   价格 price      ：<=0 或 >10000       → 置 NULL 并标记 price_abnormal=1（保留维度完整性）
--   数量 quantity   ：<=0 或 >10          → 明细行剔除
--   年龄 age        ：NULL / <16 / >100   → 用正常样本中位数填充，标记 age_fixed=1
--   日期            ：yyyy/MM/dd、yyyyMMdd → yyyy-MM-dd
--   手机号          ：去除 '-' 分隔符，统一 11 位
--   时间            ：behavior_time 斜杠日期 → 短横线；order_timestamp = order_date + order_time
--   地区            ：province + city → region
-- ============================================================

-- ------------------------------------------------------------
-- 一、用户：年龄异常填充、手机号去分隔符、注册日期归一、region 合并
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_user;
CREATE TABLE ydsh_dwd.stg_user STORED AS ORC AS
SELECT
  u.user_id,
  u.user_name,
  u.gender,
  CASE WHEN u.age IS NULL OR u.age < 16 OR u.age > 100 THEN m.med_age ELSE u.age END AS age,
  CASE WHEN u.age IS NULL OR u.age < 16 OR u.age > 100 THEN 1 ELSE 0 END AS age_fixed,
  u.city,
  u.province,
  CONCAT(u.province, '-', u.city) AS region,
  CASE
    WHEN u.register_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN REGEXP_REPLACE(u.register_date, '/', '-')
    WHEN u.register_date RLIKE '^[0-9]{8}$' THEN CONCAT(SUBSTR(u.register_date,1,4),'-',SUBSTR(u.register_date,5,2),'-',SUBSTR(u.register_date,7,2))
    ELSE u.register_date
  END AS register_date,
  u.member_level,
  REGEXP_REPLACE(u.phone, '-', '') AS phone,
  CASE WHEN u.email IS NULL OR TRIM(u.email) = '' THEN CAST(NULL AS STRING) ELSE TRIM(u.email) END AS email,
  CASE WHEN u.email IS NULL OR TRIM(u.email) = '' THEN 1 ELSE 0 END AS email_missing
FROM ydsh_dwd.stg_user_enum u
CROSS JOIN (
  SELECT CAST(PERCENTILE_APPROX(age, 0.5) AS INT) AS med_age
  FROM ydsh_dwd.stg_user_enum WHERE age BETWEEN 16 AND 100
) m;

-- ------------------------------------------------------------
-- 二、商品：价格异常置空并标记、上架日期补全、类目已 trim
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_product;
CREATE TABLE ydsh_dwd.stg_product STORED AS ORC AS
SELECT
  product_id,
  product_name,
  category,
  sub_category,
  brand,
  CASE WHEN price <= 0 OR price > 10000 THEN CAST(NULL AS DOUBLE) ELSE price END AS price,
  CASE WHEN price <= 0 OR price > 10000 THEN CAST(NULL AS DOUBLE) ELSE cost  END AS cost,
  CASE WHEN price <= 0 OR price > 10000 THEN 1 ELSE 0 END AS price_abnormal,
  stock,
  status,
  CASE
    WHEN launch_date IS NULL OR TRIM(launch_date) = '' THEN '2023-01-01'
    WHEN launch_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN REGEXP_REPLACE(launch_date, '/', '-')
    WHEN launch_date RLIKE '^[0-9]{8}$' THEN CONCAT(SUBSTR(launch_date,1,4),'-',SUBSTR(launch_date,5,2),'-',SUBSTR(launch_date,7,2))
    ELSE launch_date
  END AS launch_date,
  CASE WHEN launch_date IS NULL OR TRIM(launch_date) = '' THEN 1 ELSE 0 END AS launch_date_missing
FROM ydsh_dwd.stg_product_enum;

-- ------------------------------------------------------------
-- 三、门店：开业日期归一
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_store;
CREATE TABLE ydsh_dwd.stg_store STORED AS ORC AS
SELECT
  store_id, store_name, province, city, district, address,
  CASE
    WHEN open_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN REGEXP_REPLACE(open_date, '/', '-')
    WHEN open_date RLIKE '^[0-9]{8}$' THEN CONCAT(SUBSTR(open_date,1,4),'-',SUBSTR(open_date,5,2),'-',SUBSTR(open_date,7,2))
    ELSE open_date
  END AS open_date,
  area, manager
FROM ydsh_ods.ods_store;

-- ------------------------------------------------------------
-- 四、订单：先去重（同一 order_id 保留金额最大的一条），再剔除金额异常，最后合并时间戳
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_order;
CREATE TABLE ydsh_dwd.stg_order STORED AS ORC AS
SELECT
  order_id, user_id, store_id,
  order_date,
  order_time,
  CONCAT(order_date, ' ', order_time) AS order_timestamp,
  pay_amount, discount_amount, pay_type, order_status, channel
FROM (
  SELECT
    order_id, user_id, store_id,
    CASE
      WHEN order_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN REGEXP_REPLACE(order_date, '/', '-')
      WHEN order_date RLIKE '^[0-9]{8}$' THEN CONCAT(SUBSTR(order_date,1,4),'-',SUBSTR(order_date,5,2),'-',SUBSTR(order_date,7,2))
      ELSE order_date
    END AS order_date,
    order_time, pay_amount, discount_amount, pay_type, order_status, channel,
    ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY pay_amount DESC, order_time DESC) AS rn
  FROM ydsh_dwd.stg_order_enum
) t
WHERE rn = 1
  AND pay_amount > 0
  AND pay_amount <= 10000;

-- ------------------------------------------------------------
-- 五、订单明细：数量异常剔除 + 关联订单日期（保证引用完整性）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_order_item;
CREATE TABLE ydsh_dwd.stg_order_item STORED AS ORC AS
SELECT
  i.item_id, i.order_id, i.product_id,
  i.quantity, i.unit_price, i.discount,
  o.order_date,
  ROUND(i.quantity * i.unit_price - i.discount, 2) AS item_amount
FROM (
  SELECT item_id, order_id, product_id, quantity, unit_price, discount
  FROM ydsh_ods.ods_order_item
  WHERE quantity BETWEEN 1 AND 10
) i
JOIN (SELECT order_id, order_date FROM ydsh_dwd.stg_order) o
  ON i.order_id = o.order_id;

-- ------------------------------------------------------------
-- 六、用户行为：时间格式统一
--     原始存在两种变体：yyyy/MM/dd HH:mm:ss 与 yyyy/MM/dd HH:mm（缺秒）
--     处理：斜杠转短横线；长度 16（缺秒）的补齐 ':00'
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_behavior;
CREATE TABLE ydsh_dwd.stg_behavior STORED AS ORC AS
SELECT
  behavior_id, user_id, product_id, behavior_type,
  CASE WHEN LENGTH(t) = 16 THEN CONCAT(t, ':00') ELSE t END AS behavior_time,
  session_id
FROM (
  SELECT behavior_id, user_id, product_id, behavior_type, session_id,
         REGEXP_REPLACE(behavior_time, '/', '-') AS t
  FROM ydsh_dwd.stg_behavior_enum
) x;

-- ------------------------------------------------------------
-- 七、验证：格式与阈值是否生效
-- ------------------------------------------------------------
SELECT 'age 超出 16-100 的条数' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_user WHERE age < 16 OR age > 100;
SELECT 'phone 非 11 位纯数字' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_user WHERE phone NOT RLIKE '^1[0-9]{10}$';
SELECT 'register_date 非 yyyy-MM-dd' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_user WHERE register_date NOT RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';
SELECT 'price 仍为异常值的条数' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_product WHERE price <= 0 OR price > 10000;
SELECT 'pay_amount 仍为异常值的条数' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_order WHERE pay_amount <= 0 OR pay_amount > 10000;
SELECT 'order_date 非 yyyy-MM-dd' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_order WHERE order_date NOT RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';
SELECT 'order_timestamp 非标准格式' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_order WHERE order_timestamp NOT RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$';
SELECT 'quantity 仍为异常值的条数' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_order_item WHERE quantity <= 0 OR quantity > 10;
SELECT 'behavior_time 非标准格式' AS chk, COUNT(*) AS cnt FROM ydsh_dwd.stg_behavior WHERE behavior_time NOT RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$';
SELECT '订单去重异常明细（应 0）' AS chk, COUNT(*) AS cnt FROM (SELECT order_id FROM ydsh_dwd.stg_order GROUP BY order_id HAVING COUNT(*) > 1) d;
