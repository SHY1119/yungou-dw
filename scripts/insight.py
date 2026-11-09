# -*- coding: utf-8 -*-
"""
第 3 周 · 子任务 5：AI 智能洞察与自动报告生成
流程：从 Hive ADS/DWS 读取 KPI → 注入 Prompt → 大模型生成异常归因与经营摘要 → 人工核验后入库
说明：AI 产出仅为草稿，关键数字与归因结论需人工对照 SQL 结果验证（见 docs/AI应用反思.md）
"""
import os
import sys

BASE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(BASE, 'nl2sql'))

from nl2sql import load_env, beeline_rows, client  # 复用 .env 加载与 beeline 封装
import nl2sql as n

load_env()
MODEL = os.environ.get('LLM_MODEL', 'glm-4-flash')


def drop_header(rows):
    """beeline tsv2 输出的第一行是列头；值行才是数据"""
    if not rows:
        return rows
    header = rows[0]
    data = [r for r in rows[1:] if r != header]
    return data


def fetch_context():
    """从 Hive 抽取洞察所需的全部事实数据"""
    ctx = {}

    kpi = drop_header(beeline_rows(
        'SELECT gmv, orders, aov, active_users, arpu, discount_rate, '
        'fulfillment_rate, repurchase_rate FROM ydsh_ads.ads_kpi_overview'))
    ctx['kpi_header'] = ['gmv', 'orders', 'aov', 'active_users', 'arpu',
                         'discount_rate', 'fulfillment_rate', 'repurchase_rate']
    ctx['kpi'] = kpi[0] if kpi else []

    ctx['monthly'] = drop_header(beeline_rows(
        'SELECT month, orders, gmv, aov FROM ydsh_dws.dws_trade_month ORDER BY month'))

    ctx['category'] = drop_header(beeline_rows(
        'SELECT rk, category, item_sales, sales_pct FROM ydsh_ads.ads_category_top10 ORDER BY rk'))

    ctx['store_top5'] = drop_header(beeline_rows(
        'SELECT rk, store_name, orders, gmv, aov FROM ydsh_ads.ads_store_top10 WHERE rk <= 5'))

    # 月度环比最低的三个月（潜在异常点）
    ctx['low_months'] = drop_header(beeline_rows(
        'SELECT month, gmv FROM (SELECT month, gmv, '
        'ROW_NUMBER() OVER (ORDER BY gmv) AS rk FROM ydsh_dws.dws_trade_month) t '
        'WHERE rk <= 3 ORDER BY month'))

    # 订单状态结构
    ctx['status'] = drop_header(beeline_rows(
        'SELECT order_status, COUNT(*) AS cnt FROM ydsh_dwd.dwd_order '
        'GROUP BY order_status ORDER BY cnt DESC'))
    return ctx


def fmt_context(ctx):
    lines = []
    lines.append('核心KPI（表头:值）: '
                 + str(dict(zip(ctx['kpi_header'], ctx['kpi']))))
    lines.append('月度交易(month,orders,gmv,aov):')
    lines += ['  ' + str(r) for r in ctx['monthly']]
    lines.append('GMV最低的三个月: ' + str(ctx['low_months']))
    lines.append('品类排行(rk,category,item_sales,sales_pct):')
    lines += ['  ' + str(r) for r in ctx['category']]
    lines.append('门店TOP5(rk,store_name,orders,gmv,aov):')
    lines += ['  ' + str(r) for r in ctx['store_top5']]
    lines.append('订单状态分布(status,cnt):')
    lines += ['  ' + str(r) for r in ctx['status']]
    return '\n'.join(lines)


PROMPT = '''你是新零售企业的数据分析师。以下是经过清洗的数仓 ADS/DWS 层真实统计数据（2024 全年）：

{context}

请完成两项任务：
一、异常归因：2 月与 6 月 GMV 出现全年低谷（环比约 -8%）。请基于以上数据给出 3 条可能的原因假设，
并逐条说明"支持/反对该假设的数据证据"，明确指出哪些假设数据无法验证、需要补充什么数据。
二、经营分析摘要：写一份 250 字以内的月度经营分析摘要，要求：每个结论都必须直接引用上面数据中的数字；
不得编造数据中不存在的结论；结尾用一句话指出最大的经营风险。

注意：你的输出会被人工逐条核验，无法从数据支撑的表述会被剔除。'''


def main():
    ctx = fetch_context()
    context = fmt_context(ctx)
    print('===== 注入模型的事实数据 =====')
    print(context[:1500])
    print('\n===== 调用大模型 =====')
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[{'role': 'user', 'content': PROMPT.format(context=context)}],
        temperature=0.3, max_tokens=1500)
    out = resp.choices[0].message.content
    print(out)
    out_dir = os.path.join(BASE, '..', 'data')
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, 'ai_insight_raw.md'), 'w', encoding='utf-8') as f:
        f.write(f'# AI 洞察原始输出（{MODEL}，temperature=0.3）\n\n'
                f'## 输入事实数据\n\n```\n{context}\n```\n\n## 模型输出\n\n{out}\n')
    print('\n原始输出已存 data/ai_insight_raw.md（待人工核验）')


if __name__ == '__main__':
    main()
