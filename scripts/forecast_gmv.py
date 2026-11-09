# -*- coding: utf-8 -*-
"""
第 3 周 · 子任务 2：时间序列分析与预测建模
数据源：data/dws_trade_day.tsv（Hive ydsh_dws.dws_trade_day 导出，366 天）
模型：LinearRegression（滞后特征）与 XGBoost 对比，预留未来 7 天 GMV 预测
评估：MAE / MAPE（时间序切分，杜绝未来信息泄漏）
输出：docs/预测建模分析报告.md 所需的全部数字 + 趋势图
"""
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error
from xgboost import XGBRegressor

BASE = os.path.join(os.path.dirname(__file__), '..')
matplotlib.rcParams['font.sans-serif'] = ['Microsoft YaHei']
matplotlib.rcParams['axes.unicode_minus'] = False

# ---------- 1. 读取数据 ----------
cols = ['order_date', 'orders', 'active_users', 'gmv', 'aov', 'completed_orders']
df = pd.read_csv(os.path.join(BASE, 'data', 'dws_trade_day.tsv'), sep='\t',
                 header=None, names=cols, parse_dates=['order_date'])
df = df.sort_values('order_date').reset_index(drop=True)
print(f'样本区间: {df.order_date.min().date()} ~ {df.order_date.max().date()}，共 {len(df)} 天')
print(f'日 GMV: 均值 {df.gmv.mean():,.0f} 元，标准差 {df.gmv.std():,.0f}，'
      f'最小 {df.gmv.min():,.0f}，最大 {df.gmv.max():,.0f}')
cv = df.gmv.std() / df.gmv.mean()
print(f'变异系数 CV = {cv:.3f}')

# ---------- 2. 趋势与季节结构 ----------
df['ma7'] = df.gmv.rolling(7).mean()
df['ma30'] = df.gmv.rolling(30).mean()
df['dow'] = df.order_date.dt.dayofweek
# 线性趋势斜率（对时间索引回归）
t = np.arange(len(df))
slope = np.polyfit(t, df.gmv, 1)[0]
print(f'全年线性趋势斜率: {slope:,.2f} 元/天（年化 {slope*365/1e4:,.1f} 万元）')
dow_mean = df.groupby('dow').gmv.mean()
print('星期效应（各 weekday 平均 GMV，元）:')
print(dow_mean.round(0).to_string())
month_gmv = df.set_index('order_date').gmv.resample('MS').sum()
mom = month_gmv.pct_change() * 100
print('月度 GMV 与环比(%):')
for m, v in month_gmv.items():
    print(f'  {m.strftime("%Y-%m")}: {v:,.0f}  mom={mom[m]:+.2f}%' if not np.isnan(mom[m])
          else f'  {m.strftime("%Y-%m")}: {v:,.0f}')

# ---------- 3. 特征工程（只用过去信息，防泄漏） ----------
for lag in [1, 2, 7, 14]:
    df[f'lag{lag}'] = df.gmv.shift(lag)
df['ma7_f'] = df.gmv.shift(1).rolling(7).mean()   # 截至昨日的 7 日均值
df['ma30_f'] = df.gmv.shift(1).rolling(30).mean()
feat_cols = ['lag1', 'lag2', 'lag7', 'lag14', 'ma7_f', 'ma30_f', 'dow']
model_df = df.dropna(subset=feat_cols).reset_index(drop=True)
print(f'\n特征样本: {len(model_df)} 行（丢弃滚动窗口预热期）')

# 时间序切分：前 80% 训练，后 20% 测试（按日期，不打乱）
split = int(len(model_df) * 0.8)
tr, te = model_df.iloc[:split], model_df.iloc[split:]
print(f'训练集 {tr.order_date.min().date()} ~ {tr.order_date.max().date()}（{len(tr)} 天）')
print(f'测试集 {te.order_date.min().date()} ~ {te.order_date.max().date()}（{len(te)} 天）')
X_tr, y_tr = tr[feat_cols], tr.gmv
X_te, y_te = te[feat_cols], te.gmv

def evaluate(name, model):
    model.fit(X_tr, y_tr)
    pred_te = model.predict(X_te)
    pred_tr = model.predict(X_tr)
    mae = mean_absolute_error(y_te, pred_te)
    mape = np.mean(np.abs((y_te - pred_te) / y_te)) * 100
    mae_tr = mean_absolute_error(y_tr, pred_tr)
    mape_tr = np.mean(np.abs((y_tr - pred_tr) / y_tr)) * 100
    base_mae = mean_absolute_error(y_te, te.lag1)      # 基线：明天=昨天
    base_mape = np.mean(np.abs((y_te - te.lag1) / y_te)) * 100
    print(f'\n[{name}]')
    print(f'  测试集 MAE = {mae:,.0f} 元, MAPE = {mape:.2f}%')
    print(f'  训练集 MAE = {mae_tr:,.0f} 元, MAPE = {mape_tr:.2f}%')
    print(f'  基线(lag1) MAE = {base_mae:,.0f} 元, MAPE = {base_mape:.2f}%')
    return model, mae, mape, base_mae, base_mape

lr, lr_mae, lr_mape, b_mae, b_mape = evaluate('LinearRegression', LinearRegression())
xgb, xgb_mae, xgb_mape, _, _ = evaluate(
    'XGBoost', XGBRegressor(n_estimators=300, max_depth=3, learning_rate=0.05,
                            subsample=0.9, colsample_bytree=0.9, random_state=42))

# ---------- 4. 未来 7 天 GMV 预测（递归式，线性模型更稳） ----------
hist = df.copy()
future_preds = []
for step in range(7):
    nxt = hist.order_date.iloc[-1] + pd.Timedelta(days=1)
    row = {
        'lag1': hist.gmv.iloc[-1],
        'lag2': hist.gmv.iloc[-2],
        'lag7': hist.gmv.iloc[-7],
        'lag14': hist.gmv.iloc[-14],
        'ma7_f': hist.gmv.iloc[-7:].mean(),
        'ma30_f': hist.gmv.iloc[-30:].mean(),
        'dow': nxt.dayofweek,
    }
    X_next = pd.DataFrame([row])[feat_cols]
    p = float(lr.predict(X_next)[0])
    future_preds.append({'date': nxt, 'pred': p})
    hist = pd.concat([hist, pd.DataFrame([{
        'order_date': nxt, 'gmv': p, 'orders': np.nan, 'active_users': np.nan,
        'aov': np.nan, 'completed_orders': np.nan}])], ignore_index=True)

fp = pd.DataFrame(future_preds)
print('\n未来 7 天 GMV 预测（LinearRegression 递归）:')
for _, r in fp.iterrows():
    print(f'  {r.date.date()}: {r.pred:,.0f} 元')
print(f'未来 7 天合计预测: {fp.pred.sum():,.0f} 元（近 7 天实际合计 {df.gmv.iloc[-7:].sum():,.0f} 元）')

# ---------- 5. 趋势图 ----------
fig, ax = plt.subplots(figsize=(11, 4.5))
ax.plot(df.order_date, df.gmv, lw=0.7, alpha=0.45, label='日 GMV')
ax.plot(df.order_date, df.ma7, lw=1.6, label='7 日移动平均')
ax.plot(df.order_date, df.ma30, lw=1.6, label='30 日移动平均')
ax.plot(te.order_date, lr.predict(X_te), lw=1.2, ls='--', label='线性回归拟合（测试期）')
ax.plot(fp.date, fp.pred, lw=1.6, marker='o', ms=3, color='crimson', label='未来 7 天预测')
ax.set_title('每日 GMV：趋势、移动平均与预测（数据源 ydsh_dws.dws_trade_day）')
ax.set_ylabel('GMV（元）')
ax.legend(fontsize=8)
ax.grid(alpha=0.25)
fig.tight_layout()
out_png = os.path.join(BASE, 'docs', 'images', 'gmv_forecast.png')
fig.savefig(out_png, dpi=130)
print(f'\n图已保存: {out_png}')

# ---------- 6. 结果落盘（供报告引用） ----------
result = pd.DataFrame({
    'model': ['naive_lag1', 'linear_regression', 'xgboost'],
    'test_mae': [b_mae, lr_mae, xgb_mae],
    'test_mape': [b_mape, lr_mape, xgb_mape],
})
result.to_csv(os.path.join(BASE, 'data', 'forecast_eval.csv'), index=False)
print(result.round(2).to_string(index=False))
