# -*- coding: utf-8 -*-
"""
云购生活 · 数据大屏后端
提供 ADS 层 JSON 数据接口 + 静态大屏页面
启动: python server.py  (默认 http://localhost:5000)
"""
import json
import os
from flask import Flask, jsonify, send_from_directory

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
API_DIR = os.path.join(BASE_DIR, '..', 'api_data')
SCREEN_DIR = os.path.join(BASE_DIR, '..', 'bigscreen')

app = Flask(__name__, static_folder=None)

# 允许的接口名白名单，避免路径穿越
ALLOWED = {
    'kpi_overview', 'sales_daily', 'category_top10', 'region',
    'store_top10', 'user_value', 'pay_type', 'heatmap',
}


@app.get('/api/<name>')
def api(name):
    if name not in ALLOWED:
        return jsonify({'error': 'unknown api'}), 404
    path = os.path.join(API_DIR, name + '.json')
    if not os.path.exists(path):
        return jsonify({'error': 'data not found'}), 404
    with open(path, encoding='utf-8') as f:
        return jsonify(json.load(f))


@app.get('/')
def index():
    return send_from_directory(SCREEN_DIR, 'index.html')


@app.get('/<path:sub>')
def static_files(sub):
    return send_from_directory(SCREEN_DIR, sub)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
