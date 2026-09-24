ARG REDIS_SERVER_VERSION=8.2.9

FROM redis:${REDIS_SERVER_VERSION}-bookworm

COPY runtime/redis-entrypoint.sh /usr/local/bin/secure-app-redis

RUN chmod 755 /usr/local/bin/secure-app-redis

ENTRYPOINT ["/usr/local/bin/secure-app-redis"]
