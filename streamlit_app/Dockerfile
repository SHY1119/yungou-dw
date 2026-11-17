# Streamlit NL2SQL 问答应用镜像（构建上下文：仓库根目录）
FROM python:3.11-slim

ENV TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

WORKDIR /app

COPY streamlit_app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 仅复制代码，.env 经 .dockerignore 排除（密钥由容器环境变量注入）
COPY scripts/nl2sql/ ./nl2sql_backend/
COPY streamlit_app/app.py .

ENV NL2SQL_DIR=/app/nl2sql_backend
EXPOSE 8501
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
