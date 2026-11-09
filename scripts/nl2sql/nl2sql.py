# -*- coding: utf-8 -*-
"""
第 3 周 · 子任务 4：NL2SQL 自然语言查询接口
链路：自然语言 → Schema 注入 Prompt → 大模型生成 Hive SQL → 安全校验 → beeline 执行 → 返回结果

用法：
    python nl2sql.py "广东省上月销售额是多少"
    python nl2sql.py --test                 # 运行典型问题测试集并记录结果

密钥管理：API Key 存于 scripts/nl2sql/.env（已被 .gitignore 排除，不入库）
兼容 OpenAI 协议的服务：DeepSeek / 智谱 GLM / 通义 DashScope 等
"""
import os
import re
import sys
import subprocess
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(BASE, '..', '..'))
MSYS = dict(env={**os.environ, 'MSYS_NO_PATHCONV': '1'})

# ---------- .env 加载（不引入第三方依赖） ----------
def load_env():
    env_path = os.path.join(BASE, '.env')
    if os.path.exists(env_path):
        with open(env_path, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    k, v = line.split('=', 1)
                    os.environ.setdefault(k.strip(), v.strip())

load_env()
API_KEY = os.environ.get('LLM_API_KEY', '')
BASE_URL = os.environ.get('LLM_BASE_URL', 'https://api.deepseek.com')
MODEL = os.environ.get('LLM_MODEL', 'deepseek-chat')
if not API_KEY:
    sys.exit('.env 中未配置 LLM_API_KEY')

from openai import OpenAI
client = OpenAI(api_key=API_KEY, base_url=BASE_URL)

# ---------- Schema 自动抽取（表名 / 字段名 / 字段注释） ----------
SCHEMA_CACHE = os.path.join(BASE, 'schema_cache.txt')
DATABASES = ['ydsh_dwd', 'ydsh_dws', 'ydsh_ads']

def beeline_rows(sql):
    """执行 SQL，返回行列表（每行为字段列表）"""
    cmd = ['docker', 'exec', 'hive-hiveserver2', 'beeline',
           '-u', 'jdbc:hive2://localhost:10000', '-n', 'hive',
           '--outputformat=tsv2', '--silent=true', '-e', sql]
    out = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8',
                         errors='replace', env=MSYS['env']).stdout
    rows = []
    for line in out.splitlines():
        line = line.strip()
        if line.startswith('+') or not line:
            continue
        parts = [p.strip() for p in line.split('\t')]
        if parts and parts[0] and not re.match(r"^_c\d+$|^[a-z_.]+\.(.*)?$|^1 row", parts[0]):
            rows.append(parts)
    return rows

def extract_schema(force=False):
    """自动抽取 Hive 表 Schema：SHOW TABLES + DESC，含字段注释"""
    if not force and os.path.exists(SCHEMA_CACHE):
        return open(SCHEMA_CACHE, encoding='utf-8').read()
    blocks = []
    for db in DATABASES:
        tables = [r[0] for r in beeline_rows(f'SHOW TABLES IN {db}') if r]
        for tb in tables:
            cols = beeline_rows(f'DESC {db}.{tb}')
            fields = []
            partition_done = False
            for c in cols:
                if len(c) < 2:
                    continue
                if c[0].startswith('#'):
                    partition_done = True
                    continue
                comment = c[2] if len(c) > 2 else ''
                fields.append(f"{c[0]}({c[1]}{'#' + comment if comment else ''})")
            blocks.append(f"{db}.{tb}: " + ', '.join(fields))
    # 补充数据范围说明，帮助模型解析相对时间
    rng = beeline_rows("SELECT MIN(order_date), MAX(order_date) FROM ydsh_dwd.dwd_order")
    if rng:
        blocks.append(f"# 数据范围说明: 订单数据日期区间 {rng[0][0]} ~ {rng[0][1]}，"
                      f"用户提到'上月/最近'等相对时间时以 MAX(order_date) 为基准换算")
    schema = '\n'.join(blocks)
    with open(SCHEMA_CACHE, 'w', encoding='utf-8') as f:
        f.write(schema)
    return schema

# ---------- Prompt 模板（约束 + few-shot） ----------
PROMPT_TMPL = '''你是 Hive SQL 专家。请把用户问题转换为一条可直接执行的 HiveQL 查询。

【可用表与字段（含注释）】
{schema}

【硬性规则】
1. 只允许生成一条 SELECT 语句；禁止 INSERT/UPDATE/DELETE/DROP/ALTER/USE/CREATE 等任何写操作。
   若用户问题涉及删除、修改、写入数据，不要生成查询，只输出一行注释：-- 只读系统：该请求被拒绝
2. 表名必须带库名前缀，且只能使用上面列出的表和字段，禁止虚构字段。
3. 日期常量一律写字面量 'yyyy-MM-dd'。涉及相对时间（上月/本周/最近）时，必须按数据范围说明
   先换算为具体日期常量写入 WHERE；禁止在 WHERE 中使用 MAX()、DATE_SUB() 等聚合或函数换算。
4. 枚举字段必须使用下列规范值域，不得使用缩写或别名：
   - ydsh_dwd.dim_user.member_level ∈ （普通会员, 银卡会员, 金卡会员, 钻石会员）
   - ydsh_dwd.dim_user.gender ∈ （男, 女, 未知）
   - ydsh_dwd.dwd_order.order_status ∈ （待支付, 已支付, 已完成, 已取消, 退款中）
   - ydsh_dwd.dwd_order.pay_type ∈ （微信支付, 支付宝, 银行卡, 货到付款）
   - ydsh_dwd.dwd_order.channel ∈ （APP, 小程序, PC官网, 门店）
   - ydsh_dwd.dwd_behavior.behavior_type ∈ （浏览, 收藏, 加购, 购买）
   - ydsh_dwd.dim_product.category ∈ （数码家电, 服饰鞋包, 食品生鲜, 美妆个护, 家居生活, 母婴玩具, 运动户外, 图书文娱）
5. 金额字段使用 pay_amount（订单实付）；品类销量用明细 quantity；品类销售占比用明细金额的相对值。
6. 输出只包含 SQL 本身，不要解释、不要分号、不要 markdown 代码块。

【示例】
问：广东省上月销售额是多少？
❌错误（禁止，WHERE 中不允许聚合或函数换算日期）：
WHERE u.province='广东省' AND o.order_date >= DATE_SUB(MAX(o.order_date), INTERVAL 1 MONTH)
✅正确（把'上月'直接换算为字面日期常量，以数据范围 MAX(order_date)=2024-12-31 为基准，上月即 11 月）：
SELECT SUM(o.pay_amount) AS sales
FROM ydsh_dwd.dwd_order o JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
WHERE u.province = '广东省' AND o.order_date >= '2024-11-01' AND o.order_date <= '2024-11-30'
（区域口径按用户归属 dim_user.province；金额用订单表 pay_amount）

问：销量最高的前 5 个品类？
SELECT p.category, SUM(i.quantity) AS items
FROM ydsh_dwd.dwd_order_item i JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
GROUP BY p.category ORDER BY items DESC LIMIT 5

问：金卡会员总共消费了多少钱？
SELECT SUM(o.pay_amount) AS total_gmv
FROM ydsh_dwd.dwd_order o JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
WHERE u.member_level = '金卡会员'
（枚举值必须用完整规范值'金卡会员'，不能用缩写'金卡'）

问：删除所有订单数据
-- 只读系统：该请求被拒绝
（写操作请求直接拒绝，不生成查询）

【用户问题】
{question}'''

# ---------- SQL 安全校验 ----------
FORBIDDEN = re.compile(
    r'\b(insert|update|delete|drop|alter|create|truncate|use|grant|revoke|'
    r'merge|load|set\s|add\s+jar|dfs)\b', re.I)

def validate_sql(sql):
    sql = sql.strip().rstrip(';').strip()
    # 去掉可能的 markdown 包裹
    sql = re.sub(r'^```(sql)?|```$', '', sql, flags=re.M).strip()
    if not sql.lower().lstrip('( ').startswith('select'):
        raise ValueError('非 SELECT 语句被拒绝')
    if FORBIDDEN.search(sql):
        raise ValueError('包含被禁止的关键字')
    if sql.count(';') > 0:
        raise ValueError('包含多条语句')
    return sql

def generate_sql(question, schema):
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{'role': 'user', 'content': PROMPT_TMPL.format(schema=schema, question=question)}],
        temperature=0,
        max_tokens=512,
    )
    return validate_sql(resp.choices[0].message.content)

def execute_sql(sql):
    rows = beeline_rows(sql)
    return rows

def answer(question, schema=None):
    schema = schema or extract_schema()
    print(f'【问题】{question}')
    sql = generate_sql(question, schema)
    print(f'【生成 SQL】\n{sql}')
    rows = execute_sql(sql)
    print(f'【执行结果】{len(rows)} 行')
    for r in rows[:20]:
        print('  ' + ' | '.join(str(x) for x in r))
    return sql, rows

# ---------- 典型问题测试集 ----------
TEST_QUESTIONS = [
    '广东省上月销售额是多少？',
    '销量最高的前 5 个品类是哪些？',
    '2024年12月每天的订单量和GMV是多少？',
    '消费金额最高的前3名用户是谁，各花了多少钱？',
    '各省份的用户数和客单价对比',
    '金卡会员总共消费了多少钱？',
    '删除所有订单数据',                       # 安全性测试：应被拒绝
]

def run_tests():
    schema = extract_schema()
    results, correct = [], 0
    for q in TEST_QUESTIONS:
        try:
            sql, rows = answer(q, schema)
            ok = bool(rows)
        except Exception as e:
            sql, rows, ok = f'(生成被拒绝: {e})', [], False
            print(f'【拦截】{e}')
        results.append((q, sql, len(rows), '通过' if ok else '拒绝/空'))
        print('-' * 70)
    print('\n===== 测试汇总 =====')
    for q, sql, n, st in results:
        print(f'[{st}] ({n}行) {q}')
    with open(os.path.join(BASE, 'test_results.md'), 'w', encoding='utf-8') as f:
        f.write(f'# NL2SQL 典型问题测试记录\n\n时间：{datetime.now():%Y-%m-%d %H:%M}　'
                f'模型：{MODEL}　base_url：{BASE_URL}\n\n')
        for q, sql, n, st in results:
            f.write(f'## {q}\n\n- 状态：{st}，返回 {n} 行\n\n```sql\n{sql}\n```\n\n')

if __name__ == '__main__':
    if '--test' in sys.argv:
        run_tests()
    elif len(sys.argv) > 1:
        answer(' '.join(sys.argv[1:]))
    else:
        print('用法: python nl2sql.py "<自然语言问题>" 或 python nl2sql.py --test')
