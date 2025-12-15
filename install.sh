#!/bin/sh
# MCP Server Quick Install Script
# POSIX-compliant - works with any POSIX shell (sh, bash, dash, zsh, etc.)
# Usage: curl -fsSL https://raw.githubusercontent.com/zero-to-prod/mcp-server/main/install.sh | sh

# Defaults
DEFAULT_SERVER_NAME="mcp-server"
DEFAULT_PORT="8093"
DEFAULT_IMAGE="davidsmith3/mcp-server:latest"
AGENT_CMD="claude mcp add --transport http"

# Output functions using printf for portability
info() { printf '\033[0;34m→\033[0m %s\n' "$1"; }
success() { printf '\033[0;32m✓\033[0m %s\n' "$1"; }
error() { printf '\033[0;31m✗\033[0m %s\n' "$1"; }
plain() { printf '%s\n' "$1"; }

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

# Main installation
main() {
    plain ""
    info "MCP Server Installation"
    plain ""

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

    # Check Claude CLI
    CLAUDE_AVAILABLE="no"
    command_exists claude && CLAUDE_AVAILABLE="yes"

    # Interactive configuration
    if [ -c /dev/tty ]; then
        plain "Configuration (press Enter for defaults):"
        plain ""
    else
        info "Running in non-interactive mode, using defaults"
    fi

    prompt "Server name (${DEFAULT_SERVER_NAME}): " "$DEFAULT_SERVER_NAME" "SERVER_NAME"
    prompt "Port (${DEFAULT_PORT}): " "$DEFAULT_PORT" "PORT"
    prompt "Install directory (current: $(pwd)): " "" "CUSTOM_INSTALL_DIR"

    # Change directory if specified
    if [ -n "$CUSTOM_INSTALL_DIR" ]; then
        mkdir -p "$CUSTOM_INSTALL_DIR" || {
            error "Failed to create directory: $CUSTOM_INSTALL_DIR"
            exit 1
        }
        cd "$CUSTOM_INSTALL_DIR" || {
            error "Failed to change to directory: $CUSTOM_INSTALL_DIR"
            exit 1
        }
    fi

    INSTALL_DIR="$(pwd)"
    plain ""
    info "Installing to: ${INSTALL_DIR}"
    plain ""

    # Step 1: Initialize project
    if [ -f .env.example ] || [ -f "*.php" ]; then
        info "Found existing project files, skipping initialization"
    else
        plain "$ docker run --rm -v \$(pwd):/init ${DEFAULT_IMAGE} init"
        if docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" init; then
            success "Initialized project with controllers and configuration files"
        else
            error "Failed to initialize project"
            exit 1
        fi
    fi

    # Step 1.5: Ensure README.md is present
    if [ ! -f README.md ]; then
        plain "$ docker run --rm -v \$(pwd):/init ${DEFAULT_IMAGE} sh -c 'cp /app/README.md /init/README.md 2>/dev/null || true'"
        if docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" sh -c 'cp /app/README.md /init/README.md 2>/dev/null || true'; then
            if [ -f README.md ]; then
                success "Published: README.md"
            else
                info "README.md not available in image, skipping"
            fi
        fi
    else
        info "Found existing README.md, skipping"
    fi

    # Step 2: Create .env file
    if [ -f .env ]; then
        info "Found existing .env file, skipping creation"
        plain "  To use new settings, delete .env and run install again"
    else
        plain "$ cp .env.example .env"
        if [ -f .env.example ]; then
            cp .env.example .env || {
                error "Failed to copy .env.example"
                exit 1
            }
            plain "$ sed 's/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${SERVER_NAME}/' .env"
            sed_inplace "s/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${SERVER_NAME}/" .env
            plain "$ sed 's/^PORT=.*/PORT=${PORT}/' .env"
            sed_inplace "s/^PORT=.*/PORT=${PORT}/" .env
        else
            plain "$ cat > .env"
            cat > .env <<EOF
MCP_SERVER_NAME=${SERVER_NAME}
APP_VERSION=0.0.0
APP_DEBUG=false
MCP_CONTROLLER_PATHS=controllers
MCP_SESSIONS_DIR=/app/storage/mcp-sessions
PORT=${PORT}
DOCKER_IMAGE=${DEFAULT_IMAGE}
EOF
        fi
        success "Created: .env (MCP_SERVER_NAME=${SERVER_NAME}, PORT=${PORT})"
    fi

    # Step 3: Create docker-compose.yml
    if [ -f docker-compose.yml ]; then
        info "Found existing docker-compose.yml, skipping creation"
        plain "  To use new settings, delete docker-compose.yml and run install again"
    else
        plain "$ cat > docker-compose.yml"
        cat > docker-compose.yml <<EOF
services:
  mcp:
    image: \${DOCKER_IMAGE:-${DEFAULT_IMAGE}}
    container_name: \${MCP_SERVER_NAME:-${SERVER_NAME}}
    ports:
      - "\${PORT:-${PORT}}:80"
    volumes:
      - .:/app/controllers
      - mcp-sessions:/app/storage/mcp-sessions
    env_file:
      - .env
    restart: unless-stopped
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    container_name: \${MCP_SERVER_NAME:-${SERVER_NAME}}-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis-data:/data

volumes:
  mcp-sessions:
  redis-data:
EOF
        success "Created: docker-compose.yml"
    fi

    # Step 4: Stop any existing containers
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${SERVER_NAME}"; then
        plain "$ ${COMPOSE_CMD} down"
        ${COMPOSE_CMD} down >/dev/null 2>&1 || true
        info "Stopped existing containers"
    fi

    # Step 5: Prompt to start services
    plain ""
    if [ -c /dev/tty ]; then
        prompt_yn "Start services now? (Y/n): " "START_SERVICES" "yes"
    else
        # Non-interactive mode: default to yes
        START_SERVICES="yes"
        info "Starting services (default: yes in non-interactive mode)"
    fi

    if [ "$START_SERVICES" = "yes" ]; then
        plain "$ ${COMPOSE_CMD} up -d"
        if ${COMPOSE_CMD} up -d 2>&1; then
            success "Started: ${SERVER_NAME} on http://localhost:${PORT}"
            success "Started: ${SERVER_NAME}-redis"
        else
            error "Failed to start services"
            exit 1
        fi
    else
        plain ""
        info "To start services later, run:"
        plain "  cd ${INSTALL_DIR}"
        plain "  ${COMPOSE_CMD} up -d"
    fi

    # Step 6: Connect to Claude agents
    plain ""
    if [ "$CLAUDE_AVAILABLE" = "yes" ]; then
        if [ -c /dev/tty ]; then
            prompt_yn "Add to Claude agents? (Y/n): " "ADD_TO_CLAUDE" "yes"
        else
            # Non-interactive mode: default to yes
            ADD_TO_CLAUDE="yes"
            info "Adding to Claude agents (default: yes in non-interactive mode)"
        fi

        if [ "$ADD_TO_CLAUDE" = "yes" ]; then
            plain "$ ${AGENT_CMD} ${SERVER_NAME} http://localhost:${PORT}"
            if ${AGENT_CMD} "${SERVER_NAME}" "http://localhost:${PORT}" 2>/dev/null; then
                success "Added to Claude: ${SERVER_NAME}"
            else
                error "Failed to add to Claude"
                plain "  Manually run: ${AGENT_CMD} ${SERVER_NAME} http://localhost:${PORT}"
            fi
        fi
    else
        plain "To add to Claude agents, install Claude CLI and run:"
        plain "  ${AGENT_CMD} ${SERVER_NAME} http://localhost:${PORT}"
    fi

    plain ""
    plain "Get started by providing the README.md to your agent to build your own MCP tools!"
    plain ""
    if [ "$START_SERVICES" != "yes" ]; then
        plain "Start services:"
        plain "  cd ${INSTALL_DIR}"
        plain "  ${COMPOSE_CMD} up -d"
        plain ""
    fi
}

# Run main function
main