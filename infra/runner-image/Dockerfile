# 1. Kaniko 이미지에서 필요한 바이너리들을 가져오기 위한 스테이지
FROM gcr.io/kaniko-project/executor:v1.24.0 AS kaniko

# 2. 실제 사용할 ARC 러너 베이스
FROM summerwind/actions-runner:latest

USER root

# 필수 패키지 및 AWS CLI 설치
RUN apt-get update && apt-get install -y \
    curl wget git jq unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip && ./aws/install && rm -rf awscliv2.zip aws

# --- [핵심] Kaniko 및 ECR 로그인 헬퍼 복사 ---
# Kaniko 실행 파일 복사
COPY --from=kaniko /kaniko/executor /usr/local/bin/kaniko
# ECR 로그인에 필수적인 credential helper 복사 (중요!)
COPY --from=kaniko /kaniko/docker-credential-ecr-login /usr/local/bin/

# Kaniko가 작업할 디렉토리 및 설정 경로 미리 생성 (권한 문제 방지)
RUN mkdir -p /kaniko/.docker
ENV HOME=/root
ENV USER=root

# 검증
RUN aws --version && kaniko version && git --version

# ARC 러너는 기본적으로 'runner' 유저로 실행되지만,
# Kaniko 빌드 시에는 root 권한이 필요할 수 있습니다.
# 일단 runner 유저로 돌려놓되, Workflow에서 필요시 권한 조정
USER runner

WORKDIR /home/runner
