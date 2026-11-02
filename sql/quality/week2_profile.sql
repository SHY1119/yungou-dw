-- ============================================================
-- 第 2 周 · 清洗前取值画像扫描（profile）
-- 目的：为枚举映射与格式标准化提供真实取值依据
-- 库：ydsh_ods（ODS 贴源层）
-- ============================================================

-- ---------- 一、枚举字段取值分布 ----------
SELECT fld, val, cnt FROM (
  SELECT 'user.gender' AS fld, COALESCE(gender, '<NULL>') AS val, COUNT(*) AS cnt
    FROM ydsh_ods.ods_user GROUP BY COALESCE(gender, '<NULL>')
  UNION ALL
  SELECT 'user.member_level', COALESCE(member_level, '<NULL>'), COUNT(*)
    FROM ydsh_ods.ods_user GROUP BY COALESCE(member_level, '<NULL>')
  UNION ALL
  SELECT 'order.pay_type', COALESCE(pay_type, '<NULL>'), COUNT(*)
    FROM ydsh_ods.ods_order GROUP BY COALESCE(pay_type, '<NULL>')
  UNION ALL
  SELECT 'order.order_status', COALESCE(order_status, '<NULL>'), COUNT(*)
    FROM ydsh_ods.ods_order GROUP BY COALESCE(order_status, '<NULL>')
  UNION ALL
  SELECT 'order.channel', COALESCE(channel, '<NULL>'), COUNT(*)
    FROM ydsh_ods.ods_order GROUP BY COALESCE(channel, '<NULL>')
  UNION ALL
  SELECT 'behavior.behavior_type', COALESCE(behavior_type, '<NULL>'), COUNT(*)
    FROM ydsh_ods.ods_user_behavior GROUP BY COALESCE(behavior_type, '<NULL>')
  UNION ALL
  SELECT 'product.status', COALESCE(status, '<NULL>'), COUNT(*)
    FROM ydsh_ods.ods_product GROUP BY COALESCE(status, '<NULL>')
) t ORDER BY fld, cnt DESC;

-- ---------- 二、日期格式分布 ----------
SELECT fmt, COUNT(*) AS cnt FROM (
  SELECT CASE
           WHEN register_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'yyyy-MM-dd'
           WHEN register_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN 'yyyy/MM/dd'
           WHEN register_date RLIKE '^[0-9]{8}$'                     THEN 'yyyyMMdd'
           WHEN register_date IS NULL OR TRIM(register_date) = ''    THEN 'EMPTY'
           ELSE 'other' END AS fmt
  FROM ydsh_ods.ods_user) t GROUP BY fmt ORDER BY cnt DESC;

SELECT fmt, COUNT(*) AS cnt FROM (
  SELECT CASE
           WHEN order_date RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN 'yyyy-MM-dd'
           WHEN order_date RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}$' THEN 'yyyy/MM/dd'
           WHEN order_date RLIKE '^[0-9]{8}$'                   THEN 'yyyyMMdd'
           ELSE 'other' END AS fmt
  FROM ydsh_ods.ods_order) t GROUP BY fmt ORDER BY cnt DESC;

-- ---------- 三、手机号格式分布 ----------
SELECT fmt, COUNT(*) AS cnt FROM (
  SELECT CASE
           WHEN phone RLIKE '^1[0-9]{10}$'                    THEN '11位纯数字(规范)'
           WHEN phone RLIKE '^[0-9]{3}-[0-9]{4}-[0-9]{4}$'    THEN '带横线'
           WHEN phone IS NULL OR TRIM(phone) = ''             THEN 'EMPTY'
           ELSE 'other' END AS fmt
  FROM ydsh_ods.ods_user) t GROUP BY fmt ORDER BY cnt DESC;

-- ---------- 四、行为时间格式分布 ----------
SELECT fmt, COUNT(*) AS cnt FROM (
  SELECT CASE
           WHEN behavior_time RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN 'yyyy-MM-dd HH:mm:ss'
           WHEN behavior_time RLIKE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'                              THEN '仅日期'
           WHEN behavior_time RLIKE '^[0-9]{4}/[0-9]{2}/[0-9]{2}.*'                             THEN '斜杠日期'
           ELSE 'other' END AS fmt
  FROM ydsh_ods.ods_user_behavior) t GROUP BY fmt ORDER BY cnt DESC;

-- ---------- 五、数值异常分位数（用于设定 P99 阈值） ----------
SELECT 'order.pay_amount' AS fld,
       ROUND(MIN(pay_amount), 2)              AS min_v,
       ROUND(PERCENTILE(pay_amount, 0.5), 2)  AS p50,
       ROUND(PERCENTILE(pay_amount, 0.99), 2) AS p99,
       ROUND(PERCENTILE(pay_amount, 0.999), 2) AS p999,
       ROUND(MAX(pay_amount), 2)              AS max_v FROM ydsh_ods.ods_order
UNION ALL
SELECT 'item.quantity',
       MIN(quantity), PERCENTILE(quantity, 0.5), PERCENTILE(quantity, 0.99),
       PERCENTILE(quantity, 0.999), MAX(quantity) FROM ydsh_ods.ods_order_item
UNION ALL
SELECT 'product.price',
       ROUND(MIN(price),2), ROUND(PERCENTILE(price,0.5),2), ROUND(PERCENTILE(price,0.99),2),
       ROUND(PERCENTILE(price,0.999),2), ROUND(MAX(price),2) FROM ydsh_ods.ods_product;

-- ---------- 六、category / brand 空格与大小写问题计数 ----------
SELECT 'category.首尾空格' AS issue, COUNT(*) AS cnt FROM ydsh_ods.ods_product WHERE category <> TRIM(category)
UNION ALL
SELECT 'category.非中文标准值', COUNT(*) FROM ydsh_ods.ods_product WHERE TRIM(category) NOT IN ('数码家电','服饰鞋包','食品生鲜','美妆个护','家居生活','母婴玩具','运动户外','图书文娱')
UNION ALL
SELECT 'brand.首尾空格', COUNT(*) FROM ydsh_ods.ods_product WHERE brand <> TRIM(brand);
