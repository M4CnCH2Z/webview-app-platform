# Golden Images (ECR)

This repo uses two base (golden) images hosted in ECR:

- `golden-java21-runtime` (Spring Boot runtime)
- `golden-nginx` (static hosting for React)

## ECR repositories

Create repositories (once):

```bash
aws ecr create-repository --region ap-northeast-2 --repository-name golden-java21-runtime
aws ecr create-repository --region ap-northeast-2 --repository-name golden-nginx
aws ecr create-repository --region ap-northeast-2 --repository-name shoppingmall-api
aws ecr create-repository --region ap-northeast-2 --repository-name shoppingmall-web
```

## Login

```bash
aws ecr get-login-password --region ap-northeast-2 \
  | docker login --username AWS --password-stdin 763479270202.dkr.ecr.ap-northeast-2.amazonaws.com
```

## Build and push golden images

```bash
export GOLDEN_TAG=1.0.0
export REGISTRY=763479270202.dkr.ecr.ap-northeast-2.amazonaws.com

docker build -f infra/golden/java21-runtime/Dockerfile -t ${REGISTRY}/golden-java21-runtime:${GOLDEN_TAG} .
docker push ${REGISTRY}/golden-java21-runtime:${GOLDEN_TAG}

docker build -f infra/golden/nginx/Dockerfile -t ${REGISTRY}/golden-nginx:${GOLDEN_TAG} .
docker push ${REGISTRY}/golden-nginx:${GOLDEN_TAG}
```

## Build and push app images

```bash
export APP_TAG=1.0.0
export GOLDEN_TAG=1.0.0
export REGISTRY=763479270202.dkr.ecr.ap-northeast-2.amazonaws.com

docker build -f apps/api/Dockerfile \
  --build-arg ECR_REGISTRY=${REGISTRY} \
  --build-arg GOLDEN_TAG=${GOLDEN_TAG} \
  -t ${REGISTRY}/shoppingmall-api:${APP_TAG} \
  apps/api
docker push ${REGISTRY}/shoppingmall-api:${APP_TAG}

docker build -f apps/web/Dockerfile \
  --build-arg ECR_REGISTRY=${REGISTRY} \
  --build-arg GOLDEN_TAG=${GOLDEN_TAG} \
  -t ${REGISTRY}/shoppingmall-web:${APP_TAG} \
  apps/web
docker push ${REGISTRY}/shoppingmall-web:${APP_TAG}
```
