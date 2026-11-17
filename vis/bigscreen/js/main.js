/* 云购生活 · 数据大屏主逻辑
   数据来源: 后端 /api/* (由 Hive ADS 层导出) */
const API = n => fetch('/api/' + n).then(r => r.json());
const AXIS = { axisLine: { lineStyle: { color: 'rgba(64,156,255,.4)' } }, axisLabel: { color: '#7fa3cc', fontSize: 12 } };
const SPLIT = { lineStyle: { color: 'rgba(64,156,255,.12)' } };

/* ---------- scale 自适应 ---------- */
function resize() {
  const s = Math.min(innerWidth / 1920, innerHeight / 1080);
  document.getElementById('screen').style.transform = 'scale(' + s + ')';
}
addEventListener('resize', resize); resize();

/* ---------- 时钟 ---------- */
setInterval(() => {
  document.getElementById('clock').textContent = new Date().toLocaleString('zh-CN', { hour12: false });
}, 1000);

/* ---------- 地图注册（标准行政区划 GeoJSON，含南海诸岛） ---------- */
const mapReady = fetch('/js/china.json').then(r => r.json()).then(gj => echarts.registerMap('china', gj));

const charts = {};

function init(id) {
  const el = document.getElementById(id);
  charts[id] = echarts.init(el);
  return charts[id];
}

function fmtWan(v) { // 万元
  return (v / 10000).toFixed(1);
}

/* ---------- KPI 卡片 ---------- */
API('kpi_overview').then(k => {
  const items = [
    ['GMV', fmtWan(k.gmv), '万元'],
    ['订单量', k.orders.toLocaleString(), '单'],
    ['客单价', k.aov.toFixed(2), '元'],
    ['活跃用户', k.active_users.toLocaleString(), '人'],
    ['ARPU', k.arpu.toFixed(2), '元'],
    ['履约率', (k.fulfillment_rate * 100).toFixed(2), '%'],
  ];
  document.getElementById('kpi-grid').innerHTML = items.map(([k2, v, u]) =>
    `<div class="kpi"><div class="kpi-v">${v}<small>${u}</small></div><div class="kpi-k">${k2}</div></div>`
  ).join('');
});

/* ---------- 品类 Top10 柱状 ---------- */
API('category_top10').then(d => {
  init('chart-category').setOption({
    grid: { left: 90, right: 50, top: 10, bottom: 6 },
    xAxis: { type: 'value', splitLine: SPLIT, axisLabel: { ...AXIS.axisLabel, formatter: v => fmtWan(v) } },
    yAxis: {
      type: 'category', data: d.categories.reverse(), ...AXIS,
      axisLabel: { color: '#d6e9ff', fontSize: 12 },
    },
    tooltip: { trigger: 'axis', valueFormatter: v => fmtWan(v) + ' 万元' },
    series: [{
      type: 'bar', data: d.item_sales.reverse(), barWidth: 12,
      itemStyle: {
        borderRadius: 6,
        color: new echarts.graphic.LinearGradient(0, 0, 1, 0, [
          { offset: 0, color: '#1f6fd6' }, { offset: 1, color: '#34d2ff' }]),
      },
      label: { show: true, position: 'right', color: '#7fa3cc', fontSize: 11, formatter: p => fmtWan(p.value) + '万' },
    }],
  });
});

/* ---------- 支付方式饼图 ---------- */
API('pay_type').then(d => {
  init('chart-pay').setOption({
    tooltip: { trigger: 'item', formatter: p => `${p.name}<br/>GMV ${fmtWan(p.value)} 万元 (${p.percent}%)` },
    legend: { bottom: 0, textStyle: { color: '#7fa3cc' }, itemWidth: 14, itemHeight: 9 },
    series: [{
      type: 'pie', radius: ['42%', '68%'], center: ['50%', '44%'],
      label: { color: '#d6e9ff', fontSize: 12, formatter: '{b}\n{d}%' },
      labelLine: { lineStyle: { color: 'rgba(64,156,255,.4)' } },
      itemStyle: { borderColor: '#0a1c3c', borderWidth: 2 },
      data: d.pay_types.map((n, i) => ({ name: n, value: d.gmv[i] })),
      color: ['#34d2ff', '#409cff', '#ffcf5c', '#8f7bff'],
    }],
  });
});

/* ---------- 销售趋势折线 ---------- */
API('sales_daily').then(d => {
  init('chart-trend').setOption({
    grid: { left: 60, right: 60, top: 34, bottom: 30 },
    legend: { top: 2, right: 10, textStyle: { color: '#7fa3cc' }, data: ['GMV', '环比增速'] },
    tooltip: {
      trigger: 'axis',
      formatter: ps => ps[0].axisValue + '<br/>' + ps.map(p =>
        p.marker + p.seriesName + '：' + (p.seriesName === 'GMV' ? fmtWan(p.value) + ' 万元' : p.value + '%')).join('<br/>'),
    },
    xAxis: { type: 'category', data: d.dates, ...AXIS },
    yAxis: [
      { type: 'value', name: 'GMV(万)', nameTextStyle: { color: '#7fa3cc' }, splitLine: SPLIT, axisLabel: { ...AXIS.axisLabel, formatter: v => fmtWan(v) } },
      { type: 'value', name: '环比(%)', nameTextStyle: { color: '#7fa3cc' }, splitLine: { show: false }, axisLabel: AXIS.axisLabel },
    ],
    dataZoom: [{ type: 'slider', height: 14, bottom: 4, borderColor: 'rgba(64,156,255,.3)', textStyle: { color: '#7fa3cc' } }],
    series: [
      {
        name: 'GMV', type: 'line', data: d.gmv, smooth: true, showSymbol: false, yAxisIndex: 0,
        lineStyle: { width: 2, color: '#34d2ff' },
        areaStyle: { color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
          { offset: 0, color: 'rgba(52,210,255,.35)' }, { offset: 1, color: 'rgba(52,210,255,0)' }]) },
      },
      {
        name: '环比增速', type: 'line', data: d.gmv_mom_pct, yAxisIndex: 1, showSymbol: false,
        lineStyle: { width: 1.4, type: 'dashed', color: '#ffcf5c' },
      },
    ],
  });
});

/* ---------- 区域地图 ---------- */
mapReady.then(() => API('region')).then(d => {
  const pair = d.provinces.map((p, i) => [p, d.gmv[i]]);
  const max = Math.max(...d.gmv);
  init('chart-region').setOption({
    tooltip: {
      formatter: p => {
        const hit = pair.find(x => x[0] === p.name);
        return hit ? `${p.name}<br/>GMV：${fmtWan(hit[1])} 万元` : `${p.name}<br/>暂无销售数据`;
      },
    },
    visualMap: {
      min: 0, max: max, left: 14, bottom: 14, calculable: true,
      text: ['高', '低'], textStyle: { color: '#7fa3cc' },
      inRange: { color: ['#123a72', '#2f8fd6', '#ffd257'] },
    },
    series: [{
      type: 'map', map: 'china', roam: true,
      itemStyle: { borderColor: 'rgba(52,210,255,.5)', borderWidth: .6, areaColor: '#0f2c56' },
      emphasis: { label: { color: '#fff' }, itemStyle: { areaColor: '#409cff' } },
      select: { disabled: true },
      data: pair.map(([n, v]) => ({ name: n, value: v })),
    }],
  });
});

/* ---------- 散点：订单量 vs 客单价 ---------- */
API('sales_daily').then(d => {
  init('chart-scatter').setOption({
    grid: { left: 56, right: 24, top: 20, bottom: 32 },
    tooltip: {
      formatter: p => p.data[2] + '<br/>订单量：' + p.data[0] + ' 单<br/>客单价：' + p.data[1] + ' 元',
    },
    xAxis: { type: 'value', name: '订单量', nameTextStyle: { color: '#7fa3cc' }, splitLine: SPLIT, axisLabel: AXIS.axisLabel },
    yAxis: { type: 'value', name: '客单价(元)', nameTextStyle: { color: '#7fa3cc' }, splitLine: SPLIT, axisLabel: AXIS.axisLabel },
    series: [{
      type: 'scatter', symbolSize: 8,
      data: d.dates.map((t, i) => [d.orders[i], d.aov[i], t]),
      itemStyle: { color: 'rgba(52,210,255,.75)', borderColor: '#fff', borderWidth: .5 },
    }],
  });
});

/* ---------- 热力图：时段 × 品类 ---------- */
API('heatmap').then(d => {
  init('chart-heatmap').setOption({
    grid: { left: 80, right: 20, top: 12, bottom: 40 },
    tooltip: { formatter: p => p.value[1] + ' · ' + p.value[0] + ' 时<br/>销售额：' + fmtWan(p.value[2]) + ' 万元' },
    xAxis: { type: 'category', data: d.hours.map(h => h + '时'), ...AXIS, axisLabel: { color: '#7fa3cc', fontSize: 11 } },
    yAxis: { type: 'category', data: d.categories, ...AXIS, axisLabel: { color: '#d6e9ff', fontSize: 12 } },
    visualMap: {
      min: 0, max: Math.max(...d.data.map(x => x[2])), calculable: false, show: false,
      inRange: { color: ['#0e2a54', '#1f6fd6', '#34d2ff', '#ffcf5c'] },
    },
    series: [{
      type: 'heatmap', data: d.data,
      itemStyle: { borderColor: 'rgba(5,11,28,.6)', borderWidth: 1 },
      emphasis: { itemStyle: { shadowBlur: 8, shadowColor: 'rgba(52,210,255,.6)' } },
    }],
  });
});

/* ---------- 门店 Top10 排行 ---------- */
API('store_top10').then(d => {
  init('chart-store').setOption({
    grid: { left: 40, right: 90, top: 10, bottom: 6 },
    xAxis: { type: 'value', splitLine: SPLIT, axisLabel: { ...AXIS.axisLabel, formatter: v => fmtWan(v) } },
    yAxis: {
      type: 'category', ...AXIS,
      data: d.map(r => r.store_name).reverse(),
      axisLabel: { color: '#d6e9ff', fontSize: 12 },
    },
    tooltip: {
      formatter: p => {
        const r = d[d.length - 1 - p.dataIndex];
        return `${r.store_name}（${r.city}）<br/>GMV：${fmtWan(r.gmv)} 万元<br/>订单：${r.orders} 单`;
      },
    },
    series: [{
      type: 'bar', data: d.map(r => r.gmv).reverse(), barWidth: 10,
      itemStyle: {
        borderRadius: 5,
        color: new echarts.graphic.LinearGradient(0, 0, 1, 0, [
          { offset: 0, color: '#8f7bff' }, { offset: 1, color: '#34d2ff' }]),
      },
      label: { show: true, position: 'right', color: '#7fa3cc', fontSize: 11, formatter: p => fmtWan(p.value) + '万' },
    }],
  });
});

/* ---------- 窗口缩放时重算布局 ---------- */
addEventListener('resize', () => Object.values(charts).forEach(c => c.resize()));
