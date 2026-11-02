-- ============================================================
-- 第 2 周 · 子任务 1：枚举字段标准化
-- 输入：ydsh_ods（ODS 贴源层）
-- 输出：ydsh_dwd.stg_*_enum（枚举已标准化的暂存层）
-- 说明：所有映射规则先在字典表中显式声明，再用 CASE WHEN 落地，
--       保证「规则可读、可审计、可回溯」，不出现魔法值。
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dwd;

-- ------------------------------------------------------------
-- 一、枚举字典表（映射规则的单一事实来源）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.dim_pay_type;
CREATE TABLE ydsh_dwd.dim_pay_type (
  pay_code  string COMMENT '标准支付方式（中文）',
  pay_group string COMMENT '归类：线上/线下',
  aliases   string COMMENT '历史脏取值（逗号分隔）'
) STORED AS ORC;

INSERT INTO ydsh_dwd.dim_pay_type
SELECT '微信支付','线上','微信支付,微信,wechat,WeChat,wechat_pay' UNION ALL
SELECT '支付宝','线上','支付宝,alipay,Alipay,ali_pay'          UNION ALL
SELECT '银行卡','线上','银行卡,卡支付,bank_card,unionpay,UnionPay' UNION ALL
SELECT '货到付款','线下','货到付款,cod,现金,cash,Cash';

DROP TABLE IF EXISTS ydsh_dwd.dim_order_status;
CREATE TABLE ydsh_dwd.dim_order_status (
  status_code string COMMENT '标准订单状态',
  status_seq  int    COMMENT '状态流转序号',
  is_final    string COMMENT '是否终态：Y/N',
  aliases     string COMMENT '历史脏取值（含数字码值）'
) STORED AS ORC;

INSERT INTO ydsh_dwd.dim_order_status
SELECT '待支付',1,'N','待支付,1'                       UNION ALL
SELECT '已支付',2,'N','已支付,已付款,2'                 UNION ALL
SELECT '已完成',3,'Y','已完成,完成,3'                   UNION ALL
SELECT '已取消',4,'Y','已取消,cancelled,cancel,4'       UNION ALL
SELECT '退款中',5,'N','退款中,refunding,5';

DROP TABLE IF EXISTS ydsh_dwd.dim_member_level;
CREATE TABLE ydsh_dwd.dim_member_level (
  level_code string COMMENT '标准会员等级',
  level_rank int    COMMENT '等级序号（越大越高）',
  aliases    string COMMENT '历史脏取值',
  remark     string COMMENT '口径说明'
) STORED AS ORC;

INSERT INTO ydsh_dwd.dim_member_level
SELECT '普通会员',1,'普通会员,普通,normal,Normal,空值','空值按最低等级兜底' UNION ALL
SELECT '银卡会员',2,'银卡会员,银卡,silver,Silver',''                UNION ALL
SELECT '金卡会员',3,'金卡会员,金卡,gold,Gold',''                    UNION ALL
SELECT '钻石会员',4,'钻石会员,钻石,diamond,Diamond','';

DROP TABLE IF EXISTS ydsh_dwd.dim_channel;
CREATE TABLE ydsh_dwd.dim_channel (
  channel_code string COMMENT '标准下单渠道',
  channel_type string COMMENT '线上/线下',
  aliases      string COMMENT '历史脏取值'
) STORED AS ORC;

INSERT INTO ydsh_dwd.dim_channel
SELECT 'APP','线上','APP,app,App,移动端'          UNION ALL
SELECT '小程序','线上','小程序,miniapp,miniprogram' UNION ALL
SELECT 'PC官网','线上','PC官网,pc,PC,web,官网'     UNION ALL
SELECT '门店','线下','门店,线下门店,offline';

DROP TABLE IF EXISTS ydsh_dwd.dim_behavior_type;
CREATE TABLE ydsh_dwd.dim_behavior_type (
  behavior_code string COMMENT '标准行为类型',
  behavior_seq  int    COMMENT '转化漏斗序号',
  aliases       string COMMENT '历史脏取值'
) STORED AS ORC;

INSERT INTO ydsh_dwd.dim_behavior_type
SELECT '浏览',1,'浏览,pv,pv_view,PV,view'        UNION ALL
SELECT '收藏',2,'收藏,fav,favorite,Fav'          UNION ALL
SELECT '加购',3,'加购,cart,addcart,Cart'         UNION ALL
SELECT '购买',4,'购买,buy,purchase,order,Buy';

-- ------------------------------------------------------------
-- 二、用户表枚举标准化
--    gender：男/女/M/F/male/female/未知/空
--    member_level：金卡会员/gold/普通/空
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_user_enum;
CREATE TABLE ydsh_dwd.stg_user_enum STORED AS ORC AS
SELECT
  user_id,
  user_name,
  CASE
    WHEN LOWER(TRIM(gender)) IN ('男','m','male')   THEN '男'
    WHEN LOWER(TRIM(gender)) IN ('女','f','female') THEN '女'
    ELSE '未知'
  END AS gender,
  age,
  city,
  province,
  register_date,
  CASE
    WHEN LOWER(TRIM(member_level)) IN ('金卡会员','金卡','gold')     THEN '金卡会员'
    WHEN LOWER(TRIM(member_level)) IN ('银卡会员','银卡','silver')   THEN '银卡会员'
    WHEN LOWER(TRIM(member_level)) IN ('钻石会员','钻石','diamond')  THEN '钻石会员'
    ELSE '普通会员'
  END AS member_level,
  phone,
  email
FROM ydsh_ods.ods_user;

-- ------------------------------------------------------------
-- 三、订单表枚举标准化
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_order_enum;
CREATE TABLE ydsh_dwd.stg_order_enum STORED AS ORC AS
SELECT
  order_id,
  user_id,
  store_id,
  order_date,
  order_time,
  pay_amount,
  discount_amount,
  CASE
    WHEN LOWER(TRIM(pay_type)) IN ('微信支付','微信','wechat','weixin','wechat_pay') THEN '微信支付'
    WHEN LOWER(TRIM(pay_type)) IN ('支付宝','alipay','ali_pay')                      THEN '支付宝'
    WHEN LOWER(TRIM(pay_type)) IN ('银行卡','卡支付','bank_card','unionpay')          THEN '银行卡'
    WHEN LOWER(TRIM(pay_type)) IN ('货到付款','cod','现金','cash')                    THEN '货到付款'
    ELSE TRIM(pay_type)
  END AS pay_type,
  CASE
    WHEN LOWER(TRIM(order_status)) IN ('待支付','1')                    THEN '待支付'
    WHEN LOWER(TRIM(order_status)) IN ('已支付','已付款','2')            THEN '已支付'
    WHEN LOWER(TRIM(order_status)) IN ('已完成','完成','3')              THEN '已完成'
    WHEN LOWER(TRIM(order_status)) IN ('已取消','cancelled','cancel','4') THEN '已取消'
    WHEN LOWER(TRIM(order_status)) IN ('退款中','refunding','5')          THEN '退款中'
    ELSE TRIM(order_status)
  END AS order_status,
  CASE
    WHEN LOWER(TRIM(channel)) IN ('app','移动端')            THEN 'APP'
    WHEN LOWER(TRIM(channel)) IN ('小程序','miniapp','miniprogram') THEN '小程序'
    WHEN LOWER(TRIM(channel)) IN ('pc官网','pc','web','官网')  THEN 'PC官网'
    WHEN LOWER(TRIM(channel)) IN ('门店','线下门店','offline') THEN '门店'
    ELSE TRIM(channel)
  END AS channel
FROM ydsh_ods.ods_order;

-- ------------------------------------------------------------
-- 四、商品表：去首尾空格 + 大小写归一（category 为中文，空格是唯一问题）
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_product_enum;
CREATE TABLE ydsh_dwd.stg_product_enum STORED AS ORC AS
SELECT
  product_id,
  product_name,
  TRIM(category)     AS category,
  TRIM(sub_category) AS sub_category,
  TRIM(brand)        AS brand,
  price,
  cost,
  stock,
  TRIM(status)       AS status,
  launch_date
FROM ydsh_ods.ods_product;

-- ------------------------------------------------------------
-- 五、用户行为表枚举标准化
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ydsh_dwd.stg_behavior_enum;
CREATE TABLE ydsh_dwd.stg_behavior_enum STORED AS ORC AS
SELECT
  behavior_id,
  user_id,
  product_id,
  CASE
    WHEN LOWER(TRIM(behavior_type)) IN ('浏览','pv','pv_view','view')  THEN '浏览'
    WHEN LOWER(TRIM(behavior_type)) IN ('收藏','fav','favorite')       THEN '收藏'
    WHEN LOWER(TRIM(behavior_type)) IN ('加购','cart','addcart')       THEN '加购'
    WHEN LOWER(TRIM(behavior_type)) IN ('购买','buy','purchase','order') THEN '购买'
    ELSE TRIM(behavior_type)
  END AS behavior_type,
  behavior_time,
  session_id
FROM ydsh_ods.ods_user_behavior;

-- ------------------------------------------------------------
-- 六、验证：各字段取值是否收敛到规范值域
--     注：拆成单字段查询，避免 Tez 计数器上限（多分支 UNION ALL 易触发）
-- ------------------------------------------------------------
SELECT 'gender' AS fld, gender AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_user_enum GROUP BY gender;
SELECT 'member_level' AS fld, member_level AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_user_enum GROUP BY member_level;
SELECT 'pay_type' AS fld, pay_type AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_order_enum GROUP BY pay_type;
SELECT 'order_status' AS fld, order_status AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_order_enum GROUP BY order_status;
SELECT 'channel' AS fld, channel AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_order_enum GROUP BY channel;
SELECT 'behavior_type' AS fld, behavior_type AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_behavior_enum GROUP BY behavior_type;
SELECT 'product.status' AS fld, status AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_product_enum GROUP BY status;
SELECT 'product.category' AS fld, category AS val, COUNT(*) AS cnt FROM ydsh_dwd.stg_product_enum GROUP BY category;
