-- ============================================================
-- 第 1 周 · 子任务 4：ODS 贴源层建表（云购生活新零售）
-- 数据库：ydsh_ods；6 张表字段类型与 CSV 一致，跳过表头
-- ============================================================

create database if not exists ydsh_ods;
use ydsh_ods;

-- 1. 用户信息表（预期 1000 行）
drop table if exists ods_user;
create table ods_user (
  user_id        string,
  user_name      string,
  gender         string,
  age            int,
  city           string,
  province       string,
  register_date  string,
  member_level   string,
  phone          string,
  email          string
) row format delimited fields terminated by ','
  tblproperties ('skip.header.line.count'='1');

-- 2. 商品信息表（预期 600 行）
drop table if exists ods_product;
create table ods_product (
  product_id    string,
  product_name  string,
  category      string,
  sub_category  string,
  brand         string,
  price         double,
  cost          double,
  stock         int,
  status        string,
  launch_date   string
) row format delimited fields terminated by ','
  tblproperties ('skip.header.line.count'='1');

-- 3. 门店信息表（预期 60 行）
drop table if exists ods_store;
create table ods_store (
  store_id    string,
  store_name  string,
  province    string,
  city        string,
  district    string,
  address     string,
  open_date   string,
  area        int,
  manager     string
) row format delimited fields terminated by ','
  tblproperties ('skip.header.line.count'='1');

-- 4. 订单主表（预期 15600 行，含约 600 条重复）
drop table if exists ods_order;
create table ods_order (
  order_id         string,
  user_id          string,
  store_id         string,
  order_date       string,
  order_time       string,
  pay_amount       double,
  discount_amount  double,
  pay_type         string,
  order_status     string,
  channel          string
) row format delimited fields terminated by ','
  tblproperties ('skip.header.line.count'='1');

-- 5. 订单明细表（预期 37549 行）
drop table if exists ods_order_item;
create table ods_order_item (
  item_id     string,
  order_id    string,
  product_id  string,
  quantity    int,
  unit_price  double,
  discount    double
) row format delimited fields terminated by ','
  tblproperties ('skip.header.line.count'='1');

-- 6. 用户行为日志表（预期 60000 行）
drop table if exists ods_user_behavior;
create table ods_user_behavior (
  behavior_id    string,
  user_id        string,
  product_id     string,
  behavior_type  string,
  behavior_time  string,
  session_id     string
) row format delimited fields terminated by ','
  tblproperties ('skip.header.line.count'='1');

show tables;
