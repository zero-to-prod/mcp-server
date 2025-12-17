FROM dunglas/frankenphp:1-php8.3-bookworm AS build

RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock /app/

RUN composer install --no-dev --optimize-autoloader --ignore-platform-req=ext-mongodb

FROM dunglas/frankenphp:1-php8.3-bookworm AS production

ARG VERSION=1.0.0
ENV APP_VERSION=$VERSION
ENV MCP_SERVER_NAME="MCP Server"
ENV MCP_SESSIONS_DIR="/app/storage/mcp-sessions"
ENV APP_DEBUG="false"

# Install system dependencies and PHP extensions first (expensive, rarely changes)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    jq \
    $PHPIZE_DEPS \
    libssl-dev \
    libsasl2-dev \
 && pecl install mongodb \
 && docker-php-ext-enable mongodb \
 && apt-get purge -y --auto-remove $PHPIZE_DEPS \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /app/storage/mcp-sessions \
             /app/storage/cache \
             /app/controllers \
 && chown -R www-data:www-data /app/storage \
 && chown -R www-data:www-data /app/controllers

# Copy vendor dependencies from build stage (changes when composer.lock changes)
COPY --from=build /app/vendor /app/vendor

# Copy configuration files (changes occasionally)
COPY Caddyfile /etc/frankenphp/Caddyfile
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY composer.json composer.lock /app/

# Copy application code last (changes frequently)
COPY --chown=www-data:www-data public /app/public
COPY --chown=www-data:www-data controllers /app/controllers
COPY --chown=www-data:www-data .env.example /app/
COPY --chown=www-data:www-data docker-compose.template.yml /app/
COPY --chown=www-data:www-data README.md /app/

EXPOSE 80

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]