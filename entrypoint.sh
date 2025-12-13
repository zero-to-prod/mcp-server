#!/bin/sh
set -e

# Init mode: copy template files and exit
if [ "$1" = "init" ]; then
    INIT_DIR="/init"

    if [ ! -d "$INIT_DIR" ]; then
        echo "Error: /init directory not mounted"
        echo "Usage: docker run --rm -v \$(pwd):/init davidsmith3/mcp-server:latest init"
        exit 1
    fi

    echo "Initializing MCP Server template files..."
    echo ""

    if [ -f "/app/README.md" ]; then
        cp /app/README.md "$INIT_DIR/README.md" 2>/dev/null || true
        echo "✓ Created README.md"
    fi

    if [ -f "/app/Example.php" ]; then
        cp /app/Example.php "$INIT_DIR/Example.php" 2>/dev/null || true
        echo "✓ Created Example.php"
    fi

    if [ -f "/app/.env.example" ]; then
        cp /app/.env.example "$INIT_DIR/.env.example" 2>/dev/null || true
        echo "✓ Created .env.example"
    fi

    if [ -f "/app/docker-compose.template.yml" ]; then
        cp /app/docker-compose.template.yml "$INIT_DIR/docker-compose.yml" 2>/dev/null || true
        echo "✓ Created docker-compose.yml"
    fi

    echo ""
    echo "Template files created successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Copy .env.example to .env and configure"
    echo "  2. Start server with docker-compose up or docker run"
    echo ""
    exit 0
fi

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

if [ ! -f "$CONTROLLER_PATH/Example.php" ] && [ -f "/app/Example.php" ]; then
    if cp /app/Example.php "$CONTROLLER_PATH/Example.php" 2>/dev/null; then
        echo "Published Example.php to mounted directory"
        echo ""
    fi
fi

if [ ! -f "$CONTROLLER_PATH/.env.example" ] && [ -f "/app/.env.example" ]; then
    if cp /app/.env.example "$CONTROLLER_PATH/.env.example" 2>/dev/null; then
        echo "Published .env.example to mounted directory"
        echo ""
    fi
fi

if [ ! -d "$MCP_SESSIONS_DIR" ]; then
    echo "Creating sessions directory: $MCP_SESSIONS_DIR"
    mkdir -p "$MCP_SESSIONS_DIR"
fi

exec "$@"
