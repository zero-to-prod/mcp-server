#!/bin/sh
# MCP Server Quick Install Script
# POSIX-compliant - works with any POSIX shell (sh, bash, dash, zsh, etc.)
# Usage: curl -fsSL https://raw.githubusercontent.com/zero-to-prod/mcp-server/main/install.sh | sh

# Defaults
DEFAULT_SERVER_NAME="mcp-server"
DEFAULT_PORT="8092"
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

    if [ -c /dev/tty ]; then
        printf '%s' "$prompt_text" > /dev/tty
        read -r input < /dev/tty
        case "$input" in
            [Yy]|[Yy][Ee][Ss]) eval "$var_name=yes" ;;
            *) eval "$var_name=no" ;;
        esac
    else
        eval "$var_name=no"
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
    plain "$ docker run --rm -v \$(pwd):/init ${DEFAULT_IMAGE} init"
    if docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" init >/dev/null 2>&1; then
        success "Created: README.md, Example.php, RedisConnection.php, Reference.php, .env.example"
    else
        error "Failed to initialize project"
        exit 1
    fi

    # Step 2: Create .env file
    plain "$ cp .env.example .env"
    if [ -f .env.example ]; then
        cp .env.example .env || {
            error "Failed to copy .env.example"
            exit 1
        }
         plain "$ sed 's/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${SERVER_NAME}/' .env"
        sed_inplace "s/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${SERVER_NAME}/" .env
    else
        plain "$ cat > .env"
        cat > .env <<EOF
MCP_SERVER_NAME=${SERVER_NAME}
APP_VERSION=0.0.0
APP_DEBUG=false
MCP_CONTROLLER_PATHS=controllers
MCP_SESSIONS_DIR=/app/storage/mcp-sessions
EOF
    fi
    success "Created: .env (MCP_SERVER_NAME=${SERVER_NAME})"

    # Step 3: Remove existing container if present
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${SERVER_NAME}$"; then
        plain "$ docker stop ${SERVER_NAME}"
        docker stop "${SERVER_NAME}" >/dev/null 2>&1 || true
        plain "$ docker rm ${SERVER_NAME}"
        docker rm "${SERVER_NAME}" >/dev/null 2>&1 || true
        info "Removed existing container: ${SERVER_NAME}"
    fi

    # Step 4: Start server
    plain "$ docker run -d --name ${SERVER_NAME} -p ${PORT}:80 --env-file .env \\"
    plain "    -v \$(pwd):/app/app/Http/Controllers \\"
    plain "    -v ${SERVER_NAME}-sessions:/app/storage/mcp-sessions \\"
    plain "    ${DEFAULT_IMAGE}"

    if docker run -d \
        --name "${SERVER_NAME}" \
        -p "${PORT}:80" \
        --env-file .env \
        -v "$(pwd):/app/app/Http/Controllers" \
        -v "${SERVER_NAME}-sessions:/app/storage/mcp-sessions" \
        "${DEFAULT_IMAGE}" >/dev/null 2>&1; then
        success "Started: ${SERVER_NAME} on http://localhost:${PORT}"
    else
        error "Failed to start container"
        exit 1
    fi

    # Step 5: Connect to Claude agents
    plain ""
    if [ "$CLAUDE_AVAILABLE" = "yes" ] && [ -c /dev/tty ]; then
        prompt_yn "Add to Claude agents? (y/N): " "ADD_TO_CLAUDE"

        if [ "$ADD_TO_CLAUDE" = "yes" ]; then
            plain "$ ${AGENT_CMD} ${SERVER_NAME} http://localhost:${PORT}"
            if ${AGENT_CMD} "${SERVER_NAME}" "http://localhost:${PORT}" 2>/dev/null; then
                success "Added to Claude: ${SERVER_NAME}"
            else
                error "Failed to add to Claude"
                plain "  Manually run: ${AGENT_CMD} ${SERVER_NAME} http://localhost:${PORT}"
            fi
        fi
    elif [ "$CLAUDE_AVAILABLE" = "yes" ]; then
        plain "To add to Claude agents, run:"
        plain "  ${AGENT_CMD} ${SERVER_NAME} http://localhost:${PORT}"
    else
        plain "To add to Claude agents, install Claude CLI and run:"
        plain "  ${AGENT_CMD} ${SERVER_NAME} http://localhost:${PORT}"
    fi

    plain ""
    plain "Get started by providing the README.md to your agent to build your own MCP tools!"
    plain ""
}

# Run main function
main