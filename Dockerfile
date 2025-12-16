FROM dunglas/frankenphp:1-php8.4-alpine AS build

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock /app/

RUN composer install --no-dev --optimize-autoloader --ignore-platform-req=ext-mongodb

FROM dunglas/frankenphp:1-php8.4-alpine AS production

ARG VERSION=1.0.0
ENV APP_VERSION=$VERSION
ENV MCP_SERVER_NAME="MCP Server"
ENV MCP_SESSIONS_DIR="/app/storage/mcp-sessions"
ENV APP_DEBUG="false"

COPY Caddyfile /etc/frankenphp/Caddyfile
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

COPY --from=build /app/vendor /app/vendor

COPY composer.json composer.lock /app/

RUN apk add --no-cache \
    jq \
    grep \
    coreutils \
    sed \
    gawk \
    php84-pecl-redis \
    $PHPIZE_DEPS \
    openssl-dev \
    cyrus-sasl-dev \
    snappy-dev \
 && pecl install mongodb \
 && docker-php-ext-enable mongodb \
 && apk del $PHPIZE_DEPS \
 && mkdir -p /app/storage/mcp-sessions \
             /app/storage/cache \
             /app/controllers \
 && chown -R www-data:www-data /app/storage \
 && chown -R www-data:www-data /app/controllers

COPY --chown=www-data:www-data public /app/public
COPY --chown=www-data:www-data controllers /app/controllers
COPY --chown=www-data:www-data .env.example /app/
COPY --chown=www-data:www-data docker-compose.template.yml /app/
COPY --chown=www-data:www-data README.md /app/

EXPOSE 80

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]