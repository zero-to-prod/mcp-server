# Base stage with MongoDB extension (compiled once, reused by all stages)
FROM dunglas/frankenphp:1-php8.4-bookworm AS base

# Install MongoDB extension (expensive operation - do it once)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    $PHPIZE_DEPS \
    libssl-dev \
    libsasl2-dev \
 && pecl install mongodb \
 && docker-php-ext-enable mongodb \
 && apt-get purge -y --auto-remove $PHPIZE_DEPS \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Build stage (depends on base with MongoDB already installed)
FROM base AS build

# Install build tools
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    git \
    unzip \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY composer.json composer.lock /app/

RUN composer install --no-dev --optimize-autoloader

# Production stage (depends on base with MongoDB already installed)
FROM base AS production

ARG VERSION=1.0.0
ENV APP_VERSION=$VERSION
ENV MCP_SERVER_NAME="MCP Server"
ENV MCP_SESSIONS_DIR="/app/storage/mcp-sessions"
ENV APP_DEBUG="false"

# Install runtime dependencies (MongoDB already installed in base stage)
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    jq \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /app/storage/mcp-sessions \
             /app/storage/cache \
             /app/src \
 && chown -R www-data:www-data /app/storage \
 && chown -R www-data:www-data /app/src

# Copy vendor dependencies from build stage (changes when composer.lock changes)
COPY --from=build /app/vendor /app/vendor

# Copy configuration files (changes occasionally)
COPY Caddyfile /etc/frankenphp/Caddyfile
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY composer.json composer.lock /app/

# Copy application code last (changes frequently)
COPY --chown=www-data:www-data public /app/public
COPY --chown=www-data:www-data src /app/src
COPY --chown=www-data:www-data .env.example /app/
COPY --chown=www-data:www-data docker-compose.template.yml /app/
COPY --chown=www-data:www-data README.md /app/
COPY --chown=www-data:www-data CLAUDE.md /app/

EXPOSE 80

WORKDIR /app

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]