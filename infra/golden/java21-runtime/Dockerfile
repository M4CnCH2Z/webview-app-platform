FROM eclipse-temurin:21-jre

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV TZ=Asia/Seoul

RUN useradd -u 10001 -m -s /usr/sbin/nologin appuser
WORKDIR /app
USER 10001
