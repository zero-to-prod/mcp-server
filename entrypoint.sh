#!/bin/sh
set -e

echo "Server Name: ${MCP_SERVER_NAME:-MCP Server}"
echo "Version: ${APP_VERSION:-0.0.0}"
echo "Debug Mode: ${APP_DEBUG:-false}"
echo ""

CONTROLLER_PATH="/app/app/Http/Controllers"

if [ ! -d "$CONTROLLER_PATH" ]; then
    echo "   Controller path does not exist: $CONTROLLER_PATH"
    echo "   Creating directory..."
    mkdir -p "$CONTROLLER_PATH"
fi

controller_count=$(find "$CONTROLLER_PATH" -maxdepth 1 -name "*.php" 2>/dev/null | wc -l)
tools_count=$(grep -r "#\[McpTool" "$CONTROLLER_PATH" 2>/dev/null | wc -l)
echo "Found $controller_count controller(s) with ~$tools_count tool(s) in: app/Http/Controllers"
echo ""


if [ ! -f "$CONTROLLER_PATH/README.md" ] && [ -f "/app/README.md" ]; then
    if cp /app/README.md "$CONTROLLER_PATH/README.md" 2>/dev/null; then
        echo "Published README.md to mounted directory"
        echo ""
    fi
fi

if [ ! -d "$MCP_SESSIONS_DIR" ]; then
    echo "Creating sessions directory: $MCP_SESSIONS_DIR"
    mkdir -p "$MCP_SESSIONS_DIR"
fi

exec "$@"
