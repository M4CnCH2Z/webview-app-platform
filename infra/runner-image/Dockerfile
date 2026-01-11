FROM ghcr.io/actions/actions-runner:2.316.0

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip jq \
    openjdk-17-jre-headless \
  && rm -rf /var/lib/apt/lists/*

# sonar-scanner 설치 (버전 고정 권장)
ARG SONAR_SCANNER_VERSION=6.2.1.4610
RUN curl -fsSL -o /tmp/sonar-scanner.zip \
    "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
 && unzip -q /tmp/sonar-scanner.zip -d /opt \
 && ln -s "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64/bin/sonar-scanner" /usr/local/bin/sonar-scanner \
 && rm -f /tmp/sonar-scanner.zip

# 러너가 계속 살아있게 엔트리포인트 고정
ENTRYPOINT ["/home/runner/run.sh"]