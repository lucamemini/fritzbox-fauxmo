FROM python:3.12-slim

RUN pip install --no-cache-dir fauxmo requests

WORKDIR /app

COPY fritz_plugin.py /app/fritz_plugin.py
COPY config.json /app/config.json

CMD ["fauxmo", "-c", "/app/config.json"]