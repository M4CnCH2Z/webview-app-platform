FROM nginx:1.25-alpine

RUN apk add --no-cache ca-certificates tzdata \
    && addgroup -g 10001 appgroup \
    && adduser -D -H -u 10001 -G appgroup appuser \
    && rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p /var/cache/nginx /var/run /usr/share/nginx/html /etc/nginx/conf.d \
    && chown -R 10001:10001 /var/cache/nginx /var/run /usr/share/nginx/html /etc/nginx/conf.d

ENV TZ=Asia/Seoul
USER 10001
