#!/bin/sh
# MCP Server Quick Install Script
# POSIX-compliant - works with any POSIX shell (sh, bash, dash, zsh, etc.)
# Usage: curl -fsSL https://raw.githubusercontent.com/zero-to-prod/mcp-server/main/install.sh | sh

# Defaults
DEFAULT_SERVER_NAME="mcp-server"
DEFAULT_PORT="8080"
DEFAULT_REDIS_PORT="6379"
DEFAULT_MONGODB_PORT="27017"
DEFAULT_MEMGRAPH_PORT="7687"
DEFAULT_MEMGRAPH_LAB_PORT="3000"
DEFAULT_IMAGE="davidsmith3/mcp-server:latest"

# Output functions using printf for portability
info() { printf '\033[0;34m%s\033[0m\n' "$1"; }
success() { printf '\033[0;32m%s\033[0m\n' "$1"; }
error() { printf '\033[0;31m%s\033[0m\n' "$1"; }
plain() { printf '%s\n' "$1"; }

# Colorize output in blue
blue() {
    while IFS= read -r line; do
        printf '\033[0;34m%s\033[0m\n' "$line"
    done
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prompt with default value (POSIX-compliant)
prompt() {
    prompt_text="$1"
    default_value="$2"
    var_name="$3"

    # Try interactive prompt via /dev/tty
    if [ -c /dev/tty ]; then
        printf '%s' "$prompt_text" > /dev/tty
        read -r input < /dev/tty
        if [ -z "$input" ]; then
            eval "$var_name=\$default_value"
        else
            eval "$var_name=\$input"
        fi
    else
        # Non-interactive: use default
        eval "$var_name=\$default_value"
    fi
}

# Prompt yes/no (POSIX-compliant)
prompt_yn() {
    prompt_text="$1"
    var_name="$2"
    default_value="${3:-no}"

    if [ -c /dev/tty ]; then
        printf '%s' "$prompt_text" > /dev/tty
        read -r input < /dev/tty
        if [ -z "$input" ]; then
            eval "$var_name=\$default_value"
        else
            case "$input" in
                [Yy]|[Yy][Ee][Ss]) eval "$var_name=yes" ;;
                *) eval "$var_name=no" ;;
            esac
        fi
    else
        eval "$var_name=\$default_value"
    fi
}

# Platform-independent sed in-place edit
sed_inplace() {
    pattern="$1"
    file="$2"

    # Detect platform
    case "$(uname -s)" in
        Darwin*) sed -i '' "$pattern" "$file" ;;
        *) sed -i "$pattern" "$file" ;;
    esac
}

# Sanitize server name: allow alphanumeric, hyphens, underscores only
sanitize_server_name() {
    input="$1"
    # Remove any characters that aren't alphanumeric, hyphens, or underscores
    sanitized=$(printf '%s' "$input" | sed 's/[^a-zA-Z0-9_-]//g')
    printf '%s' "$sanitized"
}

# Validate port number: must be 1-65535
validate_port() {
    port="$1"
    # Check if numeric
    case "$port" in
        ''|*[!0-9]*) return 1 ;;
    esac
    # Check range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# Sanitize directory path: prevent path traversal
sanitize_path() {
    path="$1"
    # If empty, return empty
    if [ -z "$path" ]; then
        printf ''
        return 0
    fi
    # Remove any .. sequences and clean up
    sanitized=$(printf '%s' "$path" | sed 's/\.\.//g' | sed 's|///*|/|g')
    printf '%s' "$sanitized"
}

# Check if port is in use
is_port_in_use() {
    port="$1"
    # Try to connect to the port using different methods based on available tools
    if command_exists nc; then
        # Use netcat (most reliable)
        nc -z localhost "$port" >/dev/null 2>&1
        return $?
    elif command_exists lsof; then
        # Use lsof
        lsof -i:"$port" >/dev/null 2>&1
        return $?
    elif command_exists ss; then
        # Use ss (modern netstat)
        ss -ln | grep -q ":${port} " >/dev/null 2>&1
        return $?
    elif command_exists netstat; then
        # Use netstat (fallback)
        netstat -an | grep -q "[:.]${port} " >/dev/null 2>&1
        return $?
    else
        # No port checking tool available, assume port is free
        return 1
    fi
}

# Find next available port starting from given port
find_available_port() {
    start_port="$1"
    port="$start_port"

    while [ "$port" -le 65535 ]; do
        if ! is_port_in_use "$port"; then
            printf '%s' "$port"
            return 0
        fi
        port=$((port + 1))
    done

    # Fallback to default if no port found
    printf '%s' "$start_port"
    return 1
}

# Prompt for port with availability check
prompt_port() {
    prompt_text="$1"
    default_value="$2"
    var_name="$3"

    # Check if we're in interactive mode
    is_interactive="no"
    if [ -c /dev/tty ]; then
        is_interactive="yes"
    fi

    # Initialize port value
    port_value="$default_value"

    # In non-interactive mode, just use default without calling prompt
    if [ "$is_interactive" = "no" ]; then
        eval "$var_name=\$default_value"
    fi

    while true; do
        # In interactive mode, prompt the user
        if [ "$is_interactive" = "yes" ]; then
            prompt "$prompt_text" "$default_value" "$var_name"
            eval "port_value=\$$var_name"
        fi

        # Validate port
        if ! validate_port "$port_value"; then
            if [ "$is_interactive" = "yes" ]; then
                error "Invalid port number. Must be between 1-65535."
                continue
            else
                error "Invalid port number. Using default: ${default_value}"
                port_value="$default_value"
                eval "$var_name=\$default_value"
            fi
        fi

        # Check if port is in use
        if is_port_in_use "$port_value"; then
            if [ "$is_interactive" = "yes" ]; then
                error "Port ${port_value} is already in use. Please choose a different port."
                # Continue loop to prompt again
            else
                # Non-interactive mode: auto-increment to find available port
                info "Port ${port_value} is in use. Finding available port..."
                port_value=$((port_value + 1))
                while [ "$port_value" -le 65535 ] && is_port_in_use "$port_value"; do
                    port_value=$((port_value + 1))
                done
                if [ "$port_value" -le 65535 ]; then
                    eval "$var_name=$port_value"
                    info "Using available port: ${port_value}"
                    break
                else
                    error "Could not find an available port"
                    exit 1
                fi
            fi
        else
            # Port is available
            break
        fi
    done
}

# Main installation
main() {
    echo "Installing server..."
    
    # Check Docker
    if ! command_exists docker; then
        error "Docker is not installed. Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi

    # Check Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        error "Docker Compose is not installed. Visit: https://docs.docker.com/compose/install/"
        exit 1
    fi

    # Use docker compose (v2) if available, otherwise docker-compose (v1)
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi

    # Check for Docker image updates (only on existing installations)
    if [ -f docker-compose.yml ]; then
        # Existing installation - check for updates
        LOCAL_IMAGE_ID=$(docker images -q "${DEFAULT_IMAGE}" 2>/dev/null)

        if [ -n "$LOCAL_IMAGE_ID" ]; then
            if [ -c /dev/tty ]; then
                # Interactive mode: ask before checking for updates
                prompt_yn "Check for Docker image updates? (Y/n): " "CHECK_UPDATES" "yes"
                if [ "$CHECK_UPDATES" = "yes" ]; then
                    PULL_OUTPUT=$(docker pull "${DEFAULT_IMAGE}" 2>&1)
                    if echo "$PULL_OUTPUT" | grep -q "Downloaded newer image"; then
                        success "Updated to latest image"
                    elif echo "$PULL_OUTPUT" | grep -q "Image is up to date"; then
                        : # Silent - already up to date
                    else
                        error "Failed to check for updates. Continuing with current version..."
                    fi
                fi
            else
                # Non-interactive: check and auto-update silently
                PULL_OUTPUT=$(docker pull "${DEFAULT_IMAGE}" 2>&1)
                if echo "$PULL_OUTPUT" | grep -q "Downloaded newer image"; then
                    success "Updated to latest image"
                fi
            fi
        fi
    else
        # Fresh installation - pull latest image
        info "Pulling Docker image..."
        if ! docker pull "${DEFAULT_IMAGE}" 2>&1 | blue; then
            error "Failed to pull image"
            exit 1
        fi
    fi

    # Auto-configuration (silent)
    # Server name from current directory
    SERVER_NAME=$(basename "$(pwd)")
    SERVER_NAME=$(sanitize_server_name "$SERVER_NAME")
    if [ -z "$SERVER_NAME" ]; then
        SERVER_NAME="$DEFAULT_SERVER_NAME"
    fi

    # Auto-resolve ports (or use existing from .env if present)
    if [ -f .env ]; then
        # Read existing ports from .env
        PORT=$(grep "^PORT=" .env 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_PORT")
        REDIS_PORT=$(grep "^REDIS_PORT=" .env 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_REDIS_PORT")
        MONGODB_PORT=$(grep "^MONGODB_PORT=" .env 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_MONGODB_PORT")
        MEMGRAPH_PORT=$(grep "^MEMGRAPH_PORT=" .env 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_MEMGRAPH_PORT")
        MEMGRAPH_LAB_PORT=$(grep "^MEMGRAPH_LAB_PORT=" .env 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_MEMGRAPH_LAB_PORT")
    else
        # Find available ports for new installation
        PORT=$(find_available_port "$DEFAULT_PORT")
        REDIS_PORT=$(find_available_port "$DEFAULT_REDIS_PORT")
        MONGODB_PORT=$(find_available_port "$DEFAULT_MONGODB_PORT")
        MEMGRAPH_PORT=$(find_available_port "$DEFAULT_MEMGRAPH_PORT")
        MEMGRAPH_LAB_PORT=$(find_available_port "$DEFAULT_MEMGRAPH_LAB_PORT")
    fi

    INSTALL_DIR="$(pwd)"

    # Step 1: Copy README.md from image
    if [ ! -f README.md ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/README.md /init/README.md 2>/dev/null || true' >/dev/null 2>&1
    fi

    # Step 1.1: Copy CLAUDE.md from image
    if [ ! -f CLAUDE.md ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/CLAUDE.md /init/CLAUDE.md 2>/dev/null || true' >/dev/null 2>&1
    fi

    # Step 1.5: Copy .env.example from image
    if [ ! -f .env.example ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/.env.example /init/.env.example 2>/dev/null || true' >/dev/null 2>&1
    fi

    # Step 1.6: Create src directory if it doesn't exist
    if [ ! -d src ]; then
        mkdir -p src
    fi

    # Step 1.7: Ensure Mongodb.php controller is present in src/
    # Try new location first (/app/src), fall back to old location (/app/controllers) for backward compatibility
    if [ ! -f src/Mongodb.php ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/src/Mongodb.php /init/src/Mongodb.php 2>/dev/null || cp /app/controllers/Mongodb.php /init/src/Mongodb.php 2>/dev/null || true' >/dev/null 2>&1

        # Patch Mongodb.php to use hardcoded internal port 27017
        # MONGODB_PORT env var is only for host port mapping, not internal connections
        if [ -f src/Mongodb.php ]; then
            sed_inplace 's/$port = (int)(getenv('\''MONGODB_PORT'\'') ?: 27017);/$port = 27017; \/\/ Internal Docker network always uses 27017/' src/Mongodb.php
        fi
    fi

    # Step 1.8: Ensure Redis.php controller is present in src/
    # Try new location first (/app/src), fall back to old location (/app/controllers) for backward compatibility
    if [ ! -f src/Redis.php ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/src/Redis.php /init/src/Redis.php 2>/dev/null || cp /app/controllers/Redis.php /init/src/Redis.php 2>/dev/null || true' >/dev/null 2>&1

        # Patch Redis.php to use hardcoded internal port 6379
        # REDIS_PORT env var is only for host port mapping, not internal connections
        if [ -f src/Redis.php ]; then
            sed_inplace 's/$port = (int)(getenv('\''REDIS_PORT'\'') ?: 6379);/$port = 6379; \/\/ Internal Docker network always uses 6379/' src/Redis.php
        fi
    fi

    # Step 1.9: Ensure Memgraph.php controller is present in src/
    if [ ! -f src/Memgraph.php ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/src/Memgraph.php /init/src/Memgraph.php 2>/dev/null || true' >/dev/null 2>&1

        # Patch Memgraph.php to use hardcoded internal port 7687
        # MEMGRAPH_PORT env var is only for host port mapping, not internal connections
        if [ -f src/Memgraph.php ]; then
            sed_inplace 's/$port = (int)(getenv('\''MEMGRAPH_PORT'\'') ?: 7687);/$port = 7687; \/\/ Internal Docker network always uses 7687/' src/Memgraph.php
        fi
    fi

    # Step 1.10: Copy composer.json if it doesn't exist
    if [ ! -f composer.json ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/composer.json /init/composer.json 2>/dev/null || true' >/dev/null 2>&1
    fi

    # Step 1.11: Copy composer.lock if it doesn't exist
    if [ ! -f composer.lock ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/composer.lock /init/composer.lock 2>/dev/null || true' >/dev/null 2>&1
    fi

    # Step 1.12: Copy vendor directory if it doesn't exist
    if [ ! -d vendor ]; then
        docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp -r /app/vendor /init/vendor 2>/dev/null || true' >/dev/null 2>&1
    fi

    # Step 2: Create .env file
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            cp .env.example .env || {
                error "Failed to copy .env.example"
                exit 1
            }
            sed_inplace "s/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${SERVER_NAME}/" .env
            sed_inplace "s/^PORT=.*/PORT=${PORT}/" .env
            sed_inplace "s/^REDIS_PORT=.*/REDIS_PORT=${REDIS_PORT}/" .env
            sed_inplace "s/^MONGODB_PORT=.*/MONGODB_PORT=${MONGODB_PORT}/" .env
            sed_inplace "s/^MEMGRAPH_PORT=.*/MEMGRAPH_PORT=${MEMGRAPH_PORT}/" .env
            sed_inplace "s/^MEMGRAPH_LAB_PORT=.*/MEMGRAPH_LAB_PORT=${MEMGRAPH_LAB_PORT}/" .env
            sed_inplace "s/^MCP_CONTROLLER_PATHS=.*/MCP_CONTROLLER_PATHS=src/" .env
        else
            cat > .env <<EOF
MCP_SERVER_NAME=${SERVER_NAME}
APP_VERSION=0.0.0
APP_DEBUG=false
MCP_CONTROLLER_PATHS=src
MCP_SESSIONS_DIR=/app/storage/mcp-sessions
PORT=${PORT}
REDIS_PORT=${REDIS_PORT}
MONGODB_PORT=${MONGODB_PORT}
MEMGRAPH_PORT=${MEMGRAPH_PORT}
MEMGRAPH_LAB_PORT=${MEMGRAPH_LAB_PORT}
DOCKER_IMAGE=${DEFAULT_IMAGE}
EOF
        fi
    fi

    # Step 3: Create docker-compose.yml
    if [ ! -f docker-compose.yml ]; then
        cat > docker-compose.yml <<EOF
services:
  mcp:
    image: \${DOCKER_IMAGE:-${DEFAULT_IMAGE}}
    container_name: \${MCP_SERVER_NAME:-${SERVER_NAME}}
    ports:
      - "\${PORT:-${PORT}}:80"
    volumes:
      - ./src:/app/src
      - ./composer.json:/app/composer.json
      - ./composer.lock:/app/composer.lock
      - ./vendor:/app/vendor
      - mcp-sessions:/app/storage/mcp-sessions
    env_file:
      - .env
    restart: unless-stopped
    depends_on:
      - redis
      - mongodb
      - memgraph

  redis:
    image: redis:7-alpine
    container_name: \${MCP_SERVER_NAME:-${SERVER_NAME}}-redis
    ports:
      - "\${REDIS_PORT}:6379"
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data

  mongodb:
    image: mongo:8
    container_name: \${MCP_SERVER_NAME:-${SERVER_NAME}}-mongodb
    ports:
      - "\${MONGODB_PORT}:27017"
    restart: unless-stopped
    volumes:
      - mongodb-data:/data/db
    environment:
      - MONGO_INITDB_ROOT_USERNAME=\${MONGODB_USERNAME:-}
      - MONGO_INITDB_ROOT_PASSWORD=\${MONGODB_PASSWORD:-}

  memgraph:
    image: memgraph/memgraph-platform:latest
    container_name: \${MCP_SERVER_NAME:-${SERVER_NAME}}-memgraph
    ports:
      - "\${MEMGRAPH_PORT:-7687}:7687"
      - "\${MEMGRAPH_LAB_PORT:-3000}:3000"
    volumes:
      - memgraph-data:/var/lib/memgraph
    restart: unless-stopped
    environment:
      - MEMGRAPH=--log-level=WARNING

volumes:
  mcp-sessions:
  redis-data:
  mongodb-data:
  memgraph-data:
EOF
    fi

    # Step 4 & 5: Manage services
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${SERVER_NAME}"; then
        # Existing containers: restart with down && up
        echo "Restarting services..."
        if ! (${COMPOSE_CMD} down 2>&1 | blue && ${COMPOSE_CMD} up -d 2>&1 | blue); then
            error "Failed to restart services"
            exit 1
        fi
    else
        # No existing containers: just start
        info "Starting services..."
        if ! ${COMPOSE_CMD} up -d 2>&1 | blue; then
            error "Failed to start services"
            exit 1
        fi
    fi

    # Output MCP connection string
    plain ""
    plain "MCP Connection String:"
    printf '\033[0;32m"%s": {\n' "${SERVER_NAME}"
    printf '  "type": "streamable-http",\n'
    printf '  "url": "http://localhost:%s/mcp"\n' "${PORT}"
    printf '}\033[0m\n'
    plain ""
    plain "Add to Claude Code:"
    printf '\033[0;32mclaude mcp add --transport http %s http://localhost:%s -s user\033[0m\n' "${SERVER_NAME}" "${PORT}"
}

# Run main function
main