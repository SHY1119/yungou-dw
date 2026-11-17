# -*- coding: utf-8 -*-
"""
第 4 周 · 子任务 5：系统压力测试
对核心 Hive 查询做并发压测，记录响应时间分布（min/avg/P95/max）

用法：
    python stress_test.py                     # 默认 4 并发 × 每并发 5 次
    python stress_test.py --concurrency 8 --rounds 5

输出：控制台结果表 + scripts/压测结果.csv（人工核验后另存报告）
"""
import argparse
import csv
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
MSYS_ENV = {**os.environ, 'MSYS_NO_PATHCONV': '1'}

# 核心查询：ADS 预聚合口径（带分区裁剪的明细聚合作为对照）
QUERIES = {
    'ads预聚合(ORC 366行)': 'SELECT SUM(orders), SUM(gmv) FROM ydsh_ads.ads_sales_daily',
    '明细聚合(分区裁剪)': "SELECT SUM(pay_amount) FROM ydsh_dwd.dwd_order WHERE order_date BETWEEN '2024-11-01' AND '2024-11-30'",
    '明细聚合(全表扫描)': "SELECT SUM(pay_amount) FROM ydsh_dwd.dwd_order WHERE SUBSTR(order_timestamp,1,7)='2024-11'",
}


def run_query(sql):
    t0 = time.time()
    cmd = ['docker', 'exec', 'hive-hiveserver2', 'beeline',
           '-u', 'jdbc:hive2://localhost:10000', '-n', 'hive',
           '--silent=true', '-e', sql]
    r = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8',
                       errors='replace', env=MSYS_ENV)
    secs = round(time.time() - t0, 2)
    ok = 'Error' not in (r.stderr or '') and 'FAILED' not in (r.stdout or '')
    return secs, ok


def percentile(sorted_vals, p):
    k = max(0, min(len(sorted_vals) - 1, int(round((p / 100) * (len(sorted_vals) - 1)))))
    return sorted_vals[k]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--concurrency', type=int, default=4)
    ap.add_argument('--rounds', type=int, default=5)
    args = ap.parse_args()

    results = []
    for name, sql in QUERIES.items():
        print(f'>>> 压测 [{name}]  并发={args.concurrency} × {args.rounds} 轮')
        with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
            futures = [pool.submit(run_query, sql) for _ in range(args.rounds)]
            for f in futures:
                secs, ok = f.result()
                results.append({'query': name, 'secs': secs, 'ok': ok})
                print(f'    {secs:>7.2f}s  {"OK" if ok else "FAIL"}')

    print('\n===== 汇总 =====')
    summary = []
    for name in QUERIES:
        vals = sorted(r['secs'] for r in results if r['query'] == name)
        fails = sum(1 for r in results if r['query'] == name and not r['ok'])
        row = {
            'query': name, 'n': len(vals),
            'min': vals[0], 'avg': round(sum(vals) / len(vals), 2),
            'p50': percentile(vals, 50), 'p95': percentile(vals, 95), 'max': vals[-1],
            'fail': fails,
        }
        summary.append(row)
        print(f"{row['query']:<20} n={row['n']} min={row['min']}s avg={row['avg']}s "
              f"P50={row['p50']}s P95={row['p95']}s max={row['max']}s fail={row['fail']}")

    out = os.path.join(BASE, '压测结果.csv')
    with open(out, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['query', 'n', 'min', 'avg', 'p50', 'p95', 'max', 'fail'])
        w.writeheader()
        w.writerows(summary)
        f.write('\n')
        w2 = csv.DictWriter(f, fieldnames=['query', 'secs', 'ok'])
        w2.writerows(results)
    print(f'\n明细已写入 {out}  测试时间 {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')


if __name__ == '__main__':
    main()
