FROM gcr.io/kaniko-project/executor:v1.24.0 AS kaniko

FROM ghcr.io/actions/actions-runner:latest

USER root

RUN apt-get update && apt-get install -y \
    curl wget git jq unzip ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
 && unzip awscliv2.zip && ./aws/install \
 && rm -rf awscliv2.zip aws

COPY --from=kaniko /kaniko/executor /usr/local/bin/kaniko
COPY --from=kaniko /kaniko/docker-credential-ecr-login /usr/local/bin/

# runner가 쓸 docker config 위치를 확정
RUN mkdir -p /home/runner/.docker \
 && chown -R runner:runner /home/runner/.docker

# 검증(선택: 빌드 타임에만 확인)
RUN aws --version && /usr/local/bin/kaniko version && git --version

USER runner
WORKDIR /home/runner
