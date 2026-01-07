FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app

COPY gradlew gradlew
COPY gradle gradle
COPY build.gradle settings.gradle ./
COPY src src

RUN chmod +x gradlew
ENV GRADLE_OPTS="-Dorg.gradle.daemon=false -Dorg.gradle.vfs.watch=false"
RUN ./gradlew --no-daemon clean build -x test

ARG ECR_REGISTRY=763479270202.dkr.ecr.ap-northeast-2.amazonaws.com
ARG GOLDEN_TAG=1.0.0
FROM ${ECR_REGISTRY}/golden-java21-runtime:${GOLDEN_TAG}
WORKDIR /app
COPY --chown=10001:10001 --from=builder /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
