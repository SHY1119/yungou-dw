-- ============================================================
-- 第 1 周 · 子任务 7：数据清洗（一）重复值检测与去重
-- 两类重复：
--   A. 整行完全重复 —— 直接保留一条
--   B. 主键重复但内容不同 —— 按 order_time 降序保留最新一条
-- 方法：row_number() over(partition by order_id order by ...)
-- 输出：dwd_order（去重后订单表）
-- ============================================================
use ydsh_ods;

-- ---------- 1. 重复检测 ----------
-- 主键重复的订单 id 个数与多余行数
select count(*) as dup_order_ids, sum(c - 1) as extra_rows
from (select order_id, count(*) c from ods_order group by order_id having count(*) > 1) t;

-- 整行完全重复组数
select count(*) as exact_dup_groups from (
  select order_id, user_id, store_id, order_date, order_time, pay_amount,
         discount_amount, pay_type, order_status, channel, count(*) c
  from ods_order
  group by order_id, user_id, store_id, order_date, order_time, pay_amount,
           discount_amount, pay_type, order_status, channel
  having count(*) > 1) t;

-- ---------- 2. 窗口函数去重 → dwd_order ----------
drop table if exists dwd_order;
create table dwd_order as
select
  order_id, user_id, store_id, order_date, order_time,
  pay_amount, discount_amount, pay_type, order_status, channel
from (
  select *,
         row_number() over (
           partition by order_id
           order by order_time desc, pay_amount desc
         ) as rn
  from ods_order
) t
where rn = 1;

-- ---------- 3. 去重前后行数差异统计 ----------
select 'ods_order' as tbl, count(*) as row_cnt from ods_order
union all
select 'dwd_order', count(*) from dwd_order;

-- 校验：dwd_order 中 order_id 应唯一
select count(*) as still_dup_ids from (
  select order_id from dwd_order group by order_id having count(*) > 1) t;
