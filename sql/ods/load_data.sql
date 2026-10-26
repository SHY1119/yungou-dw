-- ============================================================
-- 第 1 周 · 子任务 4：ODS 层数据导入（load data local inpath）
-- CSV 已由 docker cp 拷贝至 hive-hiveserver2 容器 /tmp/ 目录
-- ============================================================
use ydsh_ods;

load data local inpath '/tmp/ods_user.csv' overwrite into table ods_user;
load data local inpath '/tmp/ods_product.csv' overwrite into table ods_product;
load data local inpath '/tmp/ods_store.csv' overwrite into table ods_store;
load data local inpath '/tmp/ods_order.csv' overwrite into table ods_order;
load data local inpath '/tmp/ods_order_item.csv' overwrite into table ods_order_item;
load data local inpath '/tmp/ods_user_behavior.csv' overwrite into table ods_user_behavior;

-- 行数校验（与数据字典预期对比）
select 'ods_user' as tbl, count(*) as cnt from ods_user
union all
select 'ods_product', count(*) from ods_product
union all
select 'ods_store', count(*) from ods_store
union all
select 'ods_order', count(*) from ods_order
union all
select 'ods_order_item', count(*) from ods_order_item
union all
select 'ods_user_behavior', count(*) from ods_user_behavior;
