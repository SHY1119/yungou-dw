-- ============================================================
-- 第 2 周 · 子任务 6：DWD 层星型模型建模与数据加载
-- 模型：以 dwd_order（订单事实）为核心
--       关联 dim_user / dim_product / dim_store / dim_date
-- 存储：ORC + SNAPPY；事实表按 order_date 分区（天粒度）
-- 主键：采用业务自然键（user_id / product_id / store_id / date_key），
--       理由见 docs/数仓架构设计文档.md「代理键 vs 自然键」
-- ============================================================

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.enforce.bucketing=true;
SET hive.exec.max.dynamic.partitions=1000;
SET hive.exec.max.dynamic.partitions.pernode=500;

-- ------------------------------------------------------------
-- 一、时间维度 dim_date（2023-01-01 ~ 2024-12-31，共 731 天）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dim_date;
CREATE TABLE ydsh_dwd.dim_date (
  date_key    string COMMENT '主键：yyyy-MM-dd',
  year        int    COMMENT '年',
  quarter     int    COMMENT '季度',
  month       int    COMMENT '月',
  day         int    COMMENT '日',
  weekday     string COMMENT '星期',
  is_weekend  string COMMENT '是否周末：Y/N',
  date_ym     string COMMENT '年月：yyyy-MM（用于月粒度汇总）'
) STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY');

-- 注：Hive 无 SEQUENCE 函数，用 POSEXPLODE(SPLIT(SPACE(n))) 生成 0..n 的整数序列
--     730 = 2024-12-31 与 2023-01-01 相差天数，共 731 天
INSERT INTO ydsh_dwd.dim_date
SELECT
  DATE_FORMAT(dt, 'yyyy-MM-dd') AS date_key,
  YEAR(dt), QUARTER(dt), MONTH(dt), DAY(dt),
  DATE_FORMAT(dt, 'EEEE') AS weekday,
  CASE WHEN DAYOFWEEK(dt) IN (1, 7) THEN 'Y' ELSE 'N' END AS is_weekend,
  DATE_FORMAT(dt, 'yyyy-MM') AS date_ym
FROM (
  SELECT DATE_ADD(TO_DATE('2023-01-01'), idx) AS dt
  FROM (SELECT 1) x
  LATERAL VIEW POSEXPLODE(SPLIT(SPACE(730), ' ')) v AS idx, val
) s;

-- ------------------------------------------------------------
-- 二、用户维度 dim_user
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dim_user;
CREATE TABLE ydsh_dwd.dim_user (
  user_id      string COMMENT '主键',
  user_name    string COMMENT '姓名',
  gender       string COMMENT '性别：男/女/未知',
  age          int    COMMENT '年龄（异常已修复）',
  age_fixed    int    COMMENT '年龄是否被修复：1/0',
  city         string,
  province     string,
  region       string COMMENT '省份-城市',
  register_date string COMMENT '注册日期 yyyy-MM-dd',
  member_level string COMMENT '会员等级：普通/银卡/金卡/钻石',
  phone        string COMMENT '11 位手机号',
  email        string,
  email_missing int   COMMENT '邮箱缺失标记：1/0'
) STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY');

INSERT INTO ydsh_dwd.dim_user
SELECT user_id, user_name, gender, age, age_fixed, city, province, region,
       register_date, member_level, phone, email, email_missing
FROM ydsh_dwd.stg_user;

-- ------------------------------------------------------------
-- 三、商品维度 dim_product
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dim_product;
CREATE TABLE ydsh_dwd.dim_product (
  product_id    string COMMENT '主键',
  product_name  string,
  category      string COMMENT '一级类目（已去空格）',
  sub_category  string,
  brand         string,
  price         double COMMENT '售价（异常已置空）',
  cost          double COMMENT '成本（异常已置空）',
  price_abnormal int   COMMENT '价格是否异常：1/0',
  stock         int,
  status        string COMMENT '在售/下架/缺货',
  launch_date   string COMMENT '上架日期（缺失已补全）',
  launch_date_missing int COMMENT '上架日期是否补全：1/0'
) STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY');

INSERT INTO ydsh_dwd.dim_product
SELECT product_id, product_name, category, sub_category, brand,
       price, cost, price_abnormal, stock, status,
       launch_date, launch_date_missing
FROM ydsh_dwd.stg_product;

-- ------------------------------------------------------------
-- 四、门店维度 dim_store
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dim_store;
CREATE TABLE ydsh_dwd.dim_store (
  store_id   string COMMENT '主键',
  store_name string,
  province   string,
  city       string,
  district   string,
  address    string,
  open_date  string COMMENT '开业日期 yyyy-MM-dd',
  area       int    COMMENT '面积（㎡）',
  manager    string
) STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY');

INSERT INTO ydsh_dwd.dim_store
SELECT store_id, store_name, province, city, district, address, open_date, area, manager
FROM ydsh_dwd.stg_store;

-- ------------------------------------------------------------
-- 五、订单事实表 dwd_order（分区表，按订单日期）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dwd_order;
CREATE TABLE ydsh_dwd.dwd_order (
  order_id        string COMMENT '订单号',
  user_id         string COMMENT '外键 → dim_user',
  store_id        string COMMENT '外键 → dim_store',
  order_timestamp string COMMENT '下单时间 yyyy-MM-dd HH:mm:ss',
  order_time      string COMMENT '下单时刻 HH:mm:ss',
  pay_amount      double COMMENT '实付金额（度量）',
  discount_amount double COMMENT '优惠金额（度量）',
  pay_type        string COMMENT '支付方式',
  order_status    string COMMENT '订单状态',
  channel         string COMMENT '下单渠道'
) PARTITIONED BY (order_date string COMMENT '分区：订单日期 yyyy-MM-dd')
STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY');

INSERT OVERWRITE TABLE ydsh_dwd.dwd_order PARTITION (order_date)
SELECT order_id, user_id, store_id, order_timestamp, order_time,
       pay_amount, discount_amount, pay_type, order_status, channel,
       order_date
FROM ydsh_dwd.stg_order;

-- ------------------------------------------------------------
-- 六、订单明细事实表 dwd_order_item（分区表，冗余 user_id 便于分析）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dwd_order_item;
CREATE TABLE ydsh_dwd.dwd_order_item (
  item_id     string COMMENT '明细号',
  order_id    string COMMENT '外键 → dwd_order',
  product_id  string COMMENT '外键 → dim_product',
  quantity    int    COMMENT '购买数量（度量）',
  unit_price  double COMMENT '单价（度量）',
  discount    double COMMENT '明细优惠（度量）',
  item_amount double COMMENT '明细金额（度量）'
) PARTITIONED BY (order_date string COMMENT '分区：所属订单日期')
STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY');

INSERT OVERWRITE TABLE ydsh_dwd.dwd_order_item PARTITION (order_date)
SELECT item_id, order_id, product_id, quantity, unit_price, discount, item_amount, order_date
FROM ydsh_dwd.stg_order_item;

-- ------------------------------------------------------------
-- 七、用户行为事实表 dwd_behavior（分区表，按日期）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dwd_behavior;
CREATE TABLE ydsh_dwd.dwd_behavior (
  behavior_id  string,
  user_id      string COMMENT '外键 → dim_user',
  product_id   string COMMENT '外键 → dim_product',
  behavior_type string COMMENT '浏览/收藏/加购/购买',
  behavior_time string COMMENT 'yyyy-MM-dd HH:mm:ss',
  session_id   string
) PARTITIONED BY (dt string COMMENT '分区：行为日期')
STORED AS ORC TBLPROPERTIES ('orc.compress'='SNAPPY');

INSERT OVERWRITE TABLE ydsh_dwd.dwd_behavior PARTITION (dt)
SELECT behavior_id, user_id, product_id, behavior_type, behavior_time, session_id,
       SUBSTR(behavior_time, 1, 10) AS dt
FROM ydsh_dwd.stg_behavior;

-- ------------------------------------------------------------
-- 八、验证
-- ------------------------------------------------------------
SELECT 'dim_date' AS t, COUNT(*) AS cnt FROM ydsh_dwd.dim_date;
SELECT 'dim_user', COUNT(*) FROM ydsh_dwd.dim_user;
SELECT 'dim_product', COUNT(*) FROM ydsh_dwd.dim_product;
SELECT 'dim_store', COUNT(*) FROM ydsh_dwd.dim_store;
SELECT 'dwd_order', COUNT(*) FROM ydsh_dwd.dwd_order;
SELECT 'dwd_order_item', COUNT(*) FROM ydsh_dwd.dwd_order_item;
SELECT 'dwd_behavior', COUNT(*) FROM ydsh_dwd.dwd_behavior;
SELECT 'order 分区数', COUNT(*) FROM (SELECT DISTINCT order_date FROM ydsh_dwd.dwd_order) t;
SELECT '事实表用户关联率(%)', ROUND(100.0 * SUM(CASE WHEN d.user_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
  FROM ydsh_dwd.dwd_order f LEFT JOIN ydsh_dwd.dim_user d ON f.user_id = d.user_id;
SELECT '明细商品关联率(%)', ROUND(100.0 * SUM(CASE WHEN d.product_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2)
  FROM ydsh_dwd.dwd_order_item f LEFT JOIN ydsh_dwd.dim_product d ON f.product_id = d.product_id;
