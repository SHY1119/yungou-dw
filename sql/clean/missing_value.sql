-- ============================================================
-- 第 1 周 · 子任务 6：数据清洗（一）缺失值诊断与处理
-- 策略：
--   1) ods_user.age     —— 异常值(<0 或 >120)先置 NULL，再按性别分组中位数填充
--   2) ods_user.email   —— 保留空值，新增 email_missing 标记列
--   3) ods_product.launch_date —— 按同类目最早上架日期补全
-- 输出：dwd_user / dwd_product
-- ============================================================
use ydsh_ods;

-- ---------- 1. 缺失值诊断 ----------
-- 各表缺失字段定位
select 'ods_user.age' as field, count(*) as null_cnt from ods_user where age is null
union all
select 'ods_user.email', count(*) from ods_user where email is null or email = ''
union all
select 'ods_product.launch_date', count(*) from ods_product where launch_date is null or launch_date = '';

-- 用于填充的参照值：按性别分组的年龄中位数
select gender, percentile_approx(age, 0.5) as age_median, count(*) as sample_cnt
from ods_user
where age is not null and age between 1 and 120
group by gender;

-- ---------- 2. 处理 ods_user → dwd_user ----------
drop table if exists dwd_user;
create table dwd_user as
select
  user_id,
  user_name,
  case gender                                   -- 顺带归一化性别枚举
    when 'male' then '男'  when 'M'   then '男'
    when 'female' then '女' when 'F'  then '女'
    when '未知'  then null else gender
  end as gender,
  case                                          -- 年龄：异常置空后按性别中位数填充
    when age is not null and age between 1 and 120 then age
  end as age_raw,
  coalesce(
    case when age is not null and age between 1 and 120 then age end,
    cast(percentile_approx(case when age between 1 and 120 then age end, 0.5) over (partition by gender) as int),
    cast(percentile_approx(case when age between 1 and 120 then age end, 0.5) over () as int)
  ) as age,
  city,
  province,
  register_date,
  member_level,
  phone,
  email,
  case when email is null or email = '' then 1 else 0 end as email_missing   -- 缺失标记
from ods_user;

-- 校验：dwd_user 中年龄应无空值、无异常值
select count(*) as age_null_left from dwd_user where age is null;
select count(*) as age_abnormal_left from dwd_user where age < 1 or age > 120;
select email_missing, count(*) cnt from dwd_user group by email_missing;

-- ---------- 3. 处理 ods_product.launch_date → dwd_product ----------
drop table if exists dwd_product;
create table dwd_product as
select
  p.product_id,
  p.product_name,
  trim(p.category) as category,                 -- 顺带清理类目空格
  p.sub_category,
  p.brand,
  p.price,
  p.cost,
  p.stock,
  p.status,
  coalesce(nullif(p.launch_date, ''), f.fill_date) as launch_date,   -- 缺失按同类目最早上架日期补全
  case when p.launch_date is null or p.launch_date = '' then 1 else 0 end as launch_date_missing
from ods_product p
left join (
  select trim(category) as cat, min(launch_date) as fill_date
  from ods_product
  where launch_date is not null and launch_date != ''
  group by trim(category)
) f on trim(p.category) = f.cat;

-- 校验：dwd_product 上架日期应无缺失
select count(*) as launch_date_null_left from dwd_product where launch_date is null or launch_date = '';
