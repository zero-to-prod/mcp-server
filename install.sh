#!/usr/bin/env bash

# MCP Server Quick Install Script
# Usage: curl -fsSL https://raw.githubusercontent.com/zero-to-prod/mcp-server/main/install.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_MCP_NAME="mcp-server"
DEFAULT_CONTAINER_NAME="mcp1"
DEFAULT_PORT="8092"
DEFAULT_IMAGE="davidsmith3/mcp-server:latest"

# Agent configuration
declare -A AGENTS=(
    [1]="Claude Desktop"
    [2]="Claude Code"
)
AGENT_CMD="claude mcp add --transport http"

# Print colored output
info() { echo -e "${BLUE}→${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
if ! command_exists docker; then
    error "Docker is not installed. Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    error "Docker daemon is not running. Please start Docker first."
    exit 1
fi

# Check for Claude CLI
CLAUDE_AVAILABLE=false
command_exists claude && CLAUDE_AVAILABLE=true

# Prompt for configuration
echo ""
read -p "MCP server name (default: ${DEFAULT_MCP_NAME}): " MCP_NAME
MCP_NAME=${MCP_NAME:-$DEFAULT_MCP_NAME}

read -p "Docker container name (default: ${DEFAULT_CONTAINER_NAME}): " CONTAINER_NAME
CONTAINER_NAME=${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}

read -p "Port (default: ${DEFAULT_PORT}): " PORT
PORT=${PORT:-$DEFAULT_PORT}

read -p "Install to a different directory? (leave empty for current directory): " INSTALL_DIR

# Use current directory if not specified
if [ -n "$INSTALL_DIR" ]; then
    mkdir -p "${INSTALL_DIR}"
    cd "${INSTALL_DIR}"
fi

INSTALL_DIR="$(pwd)"

echo ""
info "Installing to: ${INSTALL_DIR}"

# Step 1: Initialize project
echo "$ docker run --rm -v \$(pwd):/init ${DEFAULT_IMAGE} init"
docker run --rm -v "$(pwd):/init" "${DEFAULT_IMAGE}" init >/dev/null 2>&1
success "Created: README.md, ExampleController.php, .env.example"

# Step 2: Create .env file
echo "$ cp .env.example .env"
if [ -f .env.example ]; then
    cp .env.example .env
    echo "$ sed 's/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${MCP_NAME}/' .env"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${MCP_NAME}/" .env
    else
        sed -i "s/^MCP_SERVER_NAME=.*/MCP_SERVER_NAME=${MCP_NAME}/" .env
    fi
else
    echo "$ cat > .env"
    cat > .env <<EOF
MCP_SERVER_NAME=${MCP_NAME}
APP_VERSION=0.0.0
APP_DEBUG=false
MCP_CONTROLLER_PATHS=controllers
MCP_SESSIONS_DIR=/app/storage/mcp-sessions
EOF
fi
success "Created: .env (MCP_SERVER_NAME=${MCP_NAME})"

# Step 3: Start server
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "$ docker stop ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    echo "$ docker rm ${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    info "Removed existing container: ${CONTAINER_NAME}"
fi

echo "$ docker run -d --name ${CONTAINER_NAME} -p ${PORT}:80 --env-file .env -v \$(pwd):/app/app/Http/Controllers -v ${CONTAINER_NAME}-sessions:/app/storage/mcp-sessions ${DEFAULT_IMAGE}"
docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${PORT}:80" \
    --env-file .env \
    -v "$(pwd):/app/app/Http/Controllers" \
    -v "${CONTAINER_NAME}-sessions:/app/storage/mcp-sessions" \
    "${DEFAULT_IMAGE}" >/dev/null 2>&1

success "Started: ${CONTAINER_NAME} on http://localhost:${PORT}"

# Step 4: Connect to agents
if [ "$CLAUDE_AVAILABLE" = true ]; then
    echo ""
    echo "Select agents to install MCP server to (comma-separated numbers):"
    for key in $(echo "${!AGENTS[@]}" | tr ' ' '\n' | sort -n); do
        echo "  ${key}) ${AGENTS[$key]}"
    done
    echo ""
    read -p "Select agents (default: 1,2): " SELECTED_AGENTS
    SELECTED_AGENTS=${SELECTED_AGENTS:-"1,2"}

    # Parse selected agents
    IFS=',' read -ra AGENT_IDS <<< "$SELECTED_AGENTS"

    echo ""
    for agent_id in "${AGENT_IDS[@]}"; do
        # Trim whitespace
        agent_id=$(echo "$agent_id" | xargs)

        # Check if valid agent ID
        if [ -n "${AGENTS[$agent_id]}" ]; then
            agent_name="${AGENTS[$agent_id]}"
            echo "$ ${AGENT_CMD} ${MCP_NAME} http://localhost:${PORT}"

            if ${AGENT_CMD} "${MCP_NAME}" "http://localhost:${PORT}" 2>/dev/null; then
                success "Added to ${agent_name}: ${MCP_NAME}"
            else
                error "Failed to add to ${agent_name}"
                echo "  Manually run: ${AGENT_CMD} ${MCP_NAME} http://localhost:${PORT}"
            fi
        else
            error "Invalid agent ID: ${agent_id}"
        fi
    done
else
    echo ""
    echo "To add to Claude agents, install Claude CLI and run:"
    echo "  ${AGENT_CMD} ${MCP_NAME} http://localhost:${PORT}"
fi

echo ""
echo "Get started by providing the README.md to your agent to build your own MCP tools!"
echo ""