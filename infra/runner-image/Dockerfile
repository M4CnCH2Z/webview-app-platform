FROM ghcr.io/actions/actions-runner:2.316.0

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip jq \
    openjdk-17-jre-headless \
  && rm -rf /var/lib/apt/lists/*

ARG SONAR_SCANNER_VERSION=6.2.1.4610
RUN curl -fsSL -o /tmp/sonar-scanner.zip \
    "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
 && unzip -q /tmp/sonar-scanner.zip -d /opt \
 && ln -s "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner" /usr/local/bin/sonar-scanner \
 && rm -f /tmp/sonar-scanner.zip

# sanity check (build time)
RUN java -version && sonar-scanner --version

# ARC는 runner 유저로 실행하는 게 정석
USER runner

# ✅ 이게 핵심: 러너 프로세스를 시작해야 컨테이너가 안 죽음
ENTRYPOINT ["/home/runner/run.sh"]
