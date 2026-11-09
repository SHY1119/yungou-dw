# NL2SQL 典型问题测试记录

时间：2026-11-09 09:03　模型：glm-4-flash　base_url：https://open.bigmodel.cn/api/paas/v4

## 广东省上月销售额是多少？

- 状态：通过，返回 2 行

```sql
SELECT SUM(o.pay_amount) AS sales
FROM ydsh_dwd.dwd_order o JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
WHERE u.province = '广东省' AND o.order_date >= '2024-11-01' AND o.order_date <= '2024-11-30'
```

## 销量最高的前 5 个品类是哪些？

- 状态：通过，返回 5 行

```sql
SELECT p.category, SUM(i.quantity) AS items
FROM ydsh_dwd.dwd_order_item i JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
GROUP BY p.category ORDER BY items DESC LIMIT 5
```

## 2024年12月每天的订单量和GMV是多少？

- 状态：通过，返回 31 行

```sql
SELECT 
    d.date_key, 
    COUNT(o.order_id) AS orders, 
    SUM(o.pay_amount) AS gmv
FROM 
    ydsh_dwd.dwd_order o
JOIN 
    ydsh_dwd.dim_date d ON o.order_date = d.date_key
WHERE 
    o.order_date BETWEEN '2024-12-01' AND '2024-12-31'
GROUP BY 
    d.date_key
ORDER BY 
    d.date_key
```

## 消费金额最高的前3名用户是谁，各花了多少钱？

- 状态：通过，返回 3 行

```sql
SELECT u.user_name, SUM(o.pay_amount) AS total_spent
FROM ydsh_dwd.dwd_order o JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
GROUP BY u.user_name
ORDER BY total_spent DESC
LIMIT 3
```

## 各省份的用户数和客单价对比

- 状态：通过，返回 15 行

```sql
SELECT u.province, COUNT(DISTINCT o.user_id) AS users, AVG(o.pay_amount) AS average_order_value
FROM ydsh_dwd.dwd_order o
JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
GROUP BY u.province
```

## 金卡会员总共消费了多少钱？

- 状态：通过，返回 2 行

```sql
SELECT SUM(o.pay_amount) AS total_gmv
FROM ydsh_dwd.dwd_order o JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
WHERE u.member_level = '金卡会员'
```

## 删除所有订单数据

- 状态：拒绝/空，返回 0 行

```sql
(生成被拒绝: 非 SELECT 语句被拒绝)
```

