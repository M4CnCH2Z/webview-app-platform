ARG ECR_REGISTRY=763479270202.dkr.ecr.ap-northeast-2.amazonaws.com
ARG GOLDEN_TAG=1.0.0

FROM node:22-alpine AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
ARG REACT_APP_API_URL=/api
ENV REACT_APP_API_URL=${REACT_APP_API_URL}
RUN npm run build

FROM ${ECR_REGISTRY}/golden-nginx:${GOLDEN_TAG}
# 같은 폴더에 있는 nginx.conf를 복사
COPY --chown=10001:10001 nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=10001:10001 --from=builder /app/build /usr/share/nginx/html
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
