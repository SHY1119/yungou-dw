# -*- coding: utf-8 -*-
"""
第 4 周 · 子任务 3：Streamlit 对话式问答界面
链路：用户提问 → NL2SQL 生成 SQL → 安全校验 → beeline 执行 → 结果展示 + ECharts 图表渲染

启动：
    cd streamlit_app
    python -m streamlit run app.py   # 默认 http://localhost:8501

依赖：复用第 3 周 scripts/nl2sql/nl2sql.py（API Key 经 scripts/nl2sql/.env 注入，不入 Git）
"""
import os
import sys
import time

import pandas as pd
import streamlit as st
from pyecharts.charts import Bar, Line, Pie
from pyecharts import options as opts
import streamlit.components.v1 as components

# ---- 接入第 3 周 NL2SQL 后端 ----
# 宿主机默认 ../scripts/nl2sql；容器内经环境变量 NL2SQL_DIR 指向 /app/nl2sql_backend
NL2SQL_DIR = os.environ.get(
    'NL2SQL_DIR',
    os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'scripts', 'nl2sql')))
sys.path.insert(0, NL2SQL_DIR)
import nl2sql  # noqa: E402  (复用 generate_sql / execute_sql / extract_schema / FORBIDDEN)

st.set_page_config(page_title='云购生活 · 智能经营问答', page_icon='🛒', layout='wide')

# ---------- 会话状态：历史对话 ----------
if 'history' not in st.session_state:
    st.session_state.history = []   # [{'q','sql','rows','error','secs','rejected'}]


# ---------- 工具函数 ----------
def to_dataframe(rows):
    """beeline tsv2 结果首行为表头"""
    if not rows or len(rows) < 1:
        return None
    header = [c.split('.')[-1] for c in rows[0]]
    return pd.DataFrame(rows[1:], columns=header)


def try_render_chart(df, key):
    """按结果形态自动选择 ECharts 图表：时间列→折线；少类目单数值→饼图；其余→柱状"""
    if df is None or len(df) < 2 or len(df.columns) < 2:
        return None
    cols = list(df.columns)
    val_cols = [c for c in cols[1:] if pd.to_numeric(df[c], errors='coerce').notna().all()]
    if not val_cols:
        return None
    x = df[cols[0]].astype(str).tolist()
    vals = {c: pd.to_numeric(df[c], errors='coerce').fillna(0).round(2).tolist() for c in val_cols}
    is_time = bool(pd.to_datetime(df[cols[0]], errors='coerce', format='mixed').notna().all())

    if is_time:
        chart = Line(init_opts=opts.InitOpts(width='740px', height='380px'))
        chart.add_xaxis(x)
        for c, v in vals.items():
            chart.add_yaxis(c, v, is_smooth=True, symbol_size=4)
        chart.set_global_opts(title_opts=opts.TitleOpts(title='📈 趋势图'),
                              tooltip_opts=opts.TooltipOpts(trigger='axis'))
    elif len(val_cols) == 1 and len(df) <= 8:
        chart = Pie(init_opts=opts.InitOpts(width='740px', height='380px'))
        chart.add('', [list(z) for z in zip(x, vals[val_cols[0]])])
        chart.set_global_opts(title_opts=opts.TitleOpts(title=f'{val_cols[0]} 占比'),
                              legend_opts=opts.LegendOpts(orient='vertical', pos_right='0%'))
    else:
        chart = Bar(init_opts=opts.InitOpts(width='740px', height='380px'))
        chart.add_xaxis(x)
        for c, v in vals.items():
            chart.add_yaxis(c, v)
        chart.set_global_opts(title_opts=opts.TitleOpts(title='📊 对比图'),
                              tooltip_opts=opts.TooltipOpts(trigger='axis'))
    return chart.render_embed('c_' + key)


def run_query(q):
    t0 = time.time()
    rec = {'q': q, 'sql': '', 'rows': None, 'error': '', 'secs': 0, 'rejected': False}
    try:
        schema = nl2sql.extract_schema()
        rec['sql'] = nl2sql.generate_sql(q, schema)
        if nl2sql.FORBIDDEN.search(rec['sql']):
            # 复用后端只读防线：DELETE/UPDATE/INSERT/DROP 等写操作直接拦截
            rec['rejected'] = True
            rec['error'] = '🛡️ 该请求涉及写操作或非查询语句，已被安全防线拦截（本系统仅支持只读查询）。'
        else:
            with st.spinner('⏳ 正在执行 Hive 查询 ...'):
                rec['rows'] = nl2sql.execute_sql(rec['sql'])
            if not rec['rows'] or len(rec['rows']) <= 1:
                rec['error'] = '查询执行成功，但没有返回数据。请尝试换一种问法。'
    except Exception as e:
        rec['error'] = f'⚠️ 生成或执行失败：{e}'
    rec['secs'] = round(time.time() - t0, 1)
    st.session_state.history.append(rec)


def render_answer(rec, key):
    st.markdown(f'**Q：{rec["q"]}**')
    if rec['sql']:
        st.code(rec['sql'], language='sql')
    if rec['error']:
        st.error(rec['error'])
        return
    df = to_dataframe(rec['rows'])
    if df is None:
        return
    st.caption(f'共 {len(df)} 行 · 耗时 {rec["secs"]}s')
    st.dataframe(df, use_container_width=True, height=240)
    html = try_render_chart(df, key)
    if html:
        components.html(html, height=420)


# ---------- 侧栏 ----------
with st.sidebar:
    st.title('⚙️ 系统信息')
    st.caption('云购生活新零售 · 企业级数仓')
    st.markdown(
        f"""
        - **大模型**：`{nl2sql.MODEL}`
        - **数据源**：HiveServer2（ODS/DWD/DWS/ADS 四层）
        - **数据范围**：2023-01-01 ~ 2024-12-31
        - **安全防线**：只读校验（写操作拦截）+ 单语句限制
        - **密钥管理**：API Key 经 `.env` 注入，不入 Git
        """
    )
    st.divider()
    st.markdown('**💡 示例问题**')
    examples = [
        '广东省上月销售额是多少？',
        '销量最高的前 5 个品类是哪些？',
        '2024年12月每天的订单量和GMV是多少？',
        '消费金额最高的前3名用户是谁，各花了多少钱？',
        '各支付方式的订单量占比',
    ]
    for e in examples:
        if st.button(e, use_container_width=True):
            st.session_state.pending_question = e
    if st.session_state.history and st.button('🗑️ 清空历史对话'):
        st.session_state.history = []
        st.rerun()

# ---------- 主界面 ----------
st.title('🛒 云购生活 · 智能经营问答')
st.caption('自然语言提问 → 大模型生成 SQL → Hive 执行 → 结果与图表自动渲染')

question = st.chat_input('请输入你的问题，例如：广东省上月销售额是多少？')
if 'pending_question' in st.session_state:
    question = st.session_state.pop('pending_question')

if question:
    with st.spinner('🤔 正在理解问题并生成 SQL ...'):
        run_query(question)

# ---------- 渲染历史对话（最新在前） ----------
if st.session_state.history:
    for i, rec in enumerate(reversed(st.session_state.history), 1):
        with st.container(border=True):
            render_answer(rec, f'{len(st.session_state.history) - i}_{i}')
else:
    st.info('👆 在下方输入框提问，或点击左侧示例问题开始体验。查询结果将自动渲染为图表。')
