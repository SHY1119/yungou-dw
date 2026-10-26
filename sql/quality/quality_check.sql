-- ============================================================
-- 第 1 周 · 子任务 5：数据质量预评估（五维度扫描）
-- 维度：完整性 / 唯一性 / 有效性 / 一致性 / 准确性
-- ============================================================
use ydsh_ods;

-- ========== 1. 完整性：各表关键字段空值率 ==========

-- 用户表：年龄、邮箱缺失
select 'ods_user' as tbl, count(*) as total,
  sum(case when age is null then 1 else 0 end) as age_null,
  sum(case when email is null or email = '' then 1 else 0 end) as email_null
from ods_user;

-- 商品表：上架日期缺失
select 'ods_product' as tbl, count(*) as total,
  sum(case when launch_date is null or launch_date = '' then 1 else 0 end) as launch_date_null
from ods_product;

-- 订单表：实付金额缺失
select 'ods_order' as tbl, count(*) as total,
  sum(case when pay_amount is null then 1 else 0 end) as pay_amount_null
from ods_order;

-- 订单明细：购买数量缺失
select 'ods_order_item' as tbl, count(*) as total,
  sum(case when quantity is null then 1 else 0 end) as quantity_null
from ods_order_item;

-- 行为日志：字段缺失
select 'ods_user_behavior' as tbl, count(*) as total,
  sum(case when behavior_time is null or behavior_time = '' then 1 else 0 end) as behavior_time_null
from ods_user_behavior;

-- ========== 2. 唯一性：主键重复检测 ==========

-- 用户主键重复
select 'ods_user' as tbl, count(*) as dup_rows from (
  select user_id from ods_user group by user_id having count(*) > 1) t;

-- 商品主键重复
select 'ods_product' as tbl, count(*) as dup_rows from (
  select product_id from ods_product group by product_id having count(*) > 1) t;

-- 订单主键重复（重复订单 id 个数）
select 'ods_order' as tbl, count(*) as dup_order_ids from (
  select order_id from ods_order group by order_id having count(*) > 1) t;

-- 订单主键重复（多出的记录行数）
select 'ods_order' as tbl, sum(c - 1) as extra_rows from (
  select count(*) c from ods_order group by order_id having count(*) > 1) t;

-- 订单：整行完全重复 vs 主键重复内容不同
select count(*) as exact_dup_rows from (
  select order_id, user_id, store_id, order_date, order_time, pay_amount,
         discount_amount, pay_type, order_status, channel, count(*) c
  from ods_order group by order_id, user_id, store_id, order_date, order_time,
    pay_amount, discount_amount, pay_type, order_status, channel
  having count(*) > 1) t;

-- 明细主键重复
select 'ods_order_item' as tbl, count(*) as dup_rows from (
  select item_id from ods_order_item group by item_id having count(*) > 1) t;

-- 行为日志主键重复
select 'ods_user_behavior' as tbl, count(*) as dup_rows from (
  select behavior_id from ods_user_behavior group by behavior_id having count(*) > 1) t;

-- ========== 3. 有效性：枚举取值合法性 ==========

-- 订单状态取值分布
select order_status, count(*) cnt from ods_order group by order_status order by cnt desc;

-- 支付方式取值分布
select pay_type, count(*) cnt from ods_order group by pay_type order by cnt desc;

-- 下单渠道取值分布
select channel, count(*) cnt from ods_order group by channel order by cnt desc;

-- 用户性别取值分布
select gender, count(*) cnt from ods_user group by gender order by cnt desc;

-- 会员等级取值分布
select member_level, count(*) cnt from ods_user group by member_level order by cnt desc;

-- 商品状态取值分布
select status, count(*) cnt from ods_product group by status order by cnt desc;

-- 行为类型取值分布
select behavior_type, count(*) cnt from ods_user_behavior group by behavior_type order by cnt desc;

-- ========== 4. 一致性：格式是否统一 ==========

-- 用户注册日期三种格式混用统计
select
  sum(case when register_date rlike '^\\d{4}-\\d{2}-\\d{2}$' then 1 else 0 end) as fmt_dash,
  sum(case when register_date rlike '^\\d{4}/\\d{2}/\\d{2}$' then 1 else 0 end) as fmt_slash,
  sum(case when register_date rlike '^\\d{8}$' then 1 else 0 end) as fmt_compact
from ods_user;

-- 订单日期格式混用统计
select
  sum(case when order_date rlike '^\\d{4}-\\d{2}-\\d{2}$' then 1 else 0 end) as fmt_dash,
  sum(case when order_date rlike '^\\d{4}/\\d{2}/\\d{2}$' then 1 else 0 end) as fmt_slash
from ods_order;

-- 手机号格式（带横线）统计
select
  sum(case when phone rlike '^1\\d{10}$' then 1 else 0 end) as fmt_plain,
  sum(case when phone rlike '-' then 1 else 0 end) as fmt_dashed
from ods_user;

-- ========== 5. 准确性：取值是否合理 ==========

-- 用户年龄异常（负数、超 120）
select count(*) as abnormal_age from ods_user
where age is not null and (age < 0 or age > 120);

-- 商品价格异常（负数、超大）
select count(*) as abnormal_price from ods_product
where price is not null and (price < 0 or price > 100000);

-- 订单金额异常（负数、超大）
select count(*) as abnormal_pay from ods_order
where pay_amount is not null and (pay_amount < 0 or pay_amount > 1000000);

-- 明细数量异常（0、负数、超大）
select count(*) as abnormal_qty from ods_order_item
where quantity is null or quantity <= 0 or quantity > 50;
