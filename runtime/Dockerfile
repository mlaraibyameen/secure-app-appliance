# syntax=docker/dockerfile:1

ARG PHP_VERSION=8.4.25
ARG CADDY_VERSION=2.11.4

FROM caddy:${CADDY_VERSION} AS caddy-bin

FROM php:${PHP_VERSION}-fpm-bookworm AS php-builder

ARG OCI8_VERSION=3.4.1
ARG ORACLE_INSTANTCLIENT_SHORT=19_32
ARG ORACLE_BASIC_FILENAME
ARG ORACLE_BASIC_SHA256
ARG ORACLE_SDK_FILENAME
ARG ORACLE_SDK_SHA256

ARG ORACLE_DOWNLOAD_BASE=https://download.oracle.com/otn_software/linux/instantclient/1932000

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        libaio1 \
        libnsl2 \
        $PHPIZE_DEPS; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fL --retry 3 \
        -o "/tmp/${ORACLE_BASIC_FILENAME}" \
        "${ORACLE_DOWNLOAD_BASE}/${ORACLE_BASIC_FILENAME}"; \
    curl -fL --retry 3 \
        -o "/tmp/${ORACLE_SDK_FILENAME}" \
        "${ORACLE_DOWNLOAD_BASE}/${ORACLE_SDK_FILENAME}"; \
    echo "${ORACLE_BASIC_SHA256}  /tmp/${ORACLE_BASIC_FILENAME}" | sha256sum -c -; \
    echo "${ORACLE_SDK_SHA256}  /tmp/${ORACLE_SDK_FILENAME}" | sha256sum -c -; \
    mkdir -p /opt/oracle; \
    unzip -oq "/tmp/${ORACLE_BASIC_FILENAME}" -d /opt/oracle; \
    unzip -oq "/tmp/${ORACLE_SDK_FILENAME}" -d /opt/oracle; \
    printf '%s\n' "/opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT}" \
        > /etc/ld.so.conf.d/oracle-instantclient.conf; \
    ldconfig; \
    rm -f \
        "/tmp/${ORACLE_BASIC_FILENAME}" \
        "/tmp/${ORACLE_SDK_FILENAME}"; \
    printf 'instantclient,/opt/oracle/instantclient_%s\n' \
        "${ORACLE_INSTANTCLIENT_SHORT}" \
        | pecl install "oci8-${OCI8_VERSION}"; \
    docker-php-ext-enable oci8; \
    echo "=== OCI8 LINK CHECK ==="; \
    ldd "$(php-config --extension-dir)/oci8.so"; \
    echo "=== ORACLE CLIENT LINK CHECK ==="; \
    ldd "/opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT}/libclntsh.so.19.1"; \
    echo "=== PHP OCI8 LOAD CHECK ==="; \
    php --ri oci8

FROM php:${PHP_VERSION}-fpm-bookworm AS runtime

ARG APP_RUNTIME_USER=app
ARG APP_RUNTIME_UID=10001
ARG APP_RUNTIME_GID=10001
ARG APP_HTTP_PORT=8080
ARG ORACLE_INSTANTCLIENT_SHORT=19_32

ENV APP_ROOT=/opt/app \
    APP_DATA=/data \
    APP_HTTP_PORT=${APP_HTTP_PORT} \
    ORACLE_HOME=/opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT} \
    LD_LIBRARY_PATH=/opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT}

COPY --from=caddy-bin /usr/bin/caddy /usr/local/bin/caddy

COPY --from=php-builder \
    /opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT} \
    /opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT}

COPY --from=php-builder \
    /usr/local/lib/php/extensions/ \
    /usr/local/lib/php/extensions/

COPY --from=php-builder \
    /usr/local/etc/php/conf.d/docker-php-ext-oci8.ini \
    /usr/local/etc/php/conf.d/docker-php-ext-oci8.ini

RUN set -eux; \
    rm -rf "/opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT}/sdk"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libaio1 \
        libnsl2 \
        tini; \
    rm -rf /var/lib/apt/lists/*; \
    printf '%s\n' \
        "/opt/oracle/instantclient_${ORACLE_INSTANTCLIENT_SHORT}" \
        > /etc/ld.so.conf.d/oracle-instantclient.conf; \
    ldconfig; \
    groupadd --gid "${APP_RUNTIME_GID}" "${APP_RUNTIME_USER}"; \
    useradd \
        --uid "${APP_RUNTIME_UID}" \
        --gid "${APP_RUNTIME_GID}" \
        --home-dir "${APP_ROOT}" \
        --shell /usr/sbin/nologin \
        "${APP_RUNTIME_USER}"; \
    mkdir -p \
        "${APP_ROOT}" \
        "${APP_DATA}/uploads" \
        "${APP_DATA}/storage" \
        "${APP_DATA}/logs"; \
    chown -R \
        "${APP_RUNTIME_UID}:${APP_RUNTIME_GID}" \
        "${APP_ROOT}" \
        "${APP_DATA}"; \
    php --ri oci8 >/dev/null

WORKDIR ${APP_ROOT}

EXPOSE ${APP_HTTP_PORT}

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["php-fpm", "-F"]
