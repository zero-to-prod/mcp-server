#!/bin/sh
set -e

# Init mode: copy template files and exit
if [ "$1" = "init" ]; then
    INIT_DIR="/init"
    SOURCE_CONTROLLERS="/app/controllers"

    if [ ! -d "$INIT_DIR" ]; then
        echo "Error: /init directory not mounted"
        echo "Usage: docker run --rm -v \$(pwd):/init davidsmith3/mcp-server:latest init"
        exit 1
    fi

    echo "Initializing MCP Server template files..."
    echo ""

    # Copy all controller files from image controllers directory
    if [ -d "$SOURCE_CONTROLLERS" ]; then
        controller_files=$(find "$SOURCE_CONTROLLERS" -maxdepth 1 -type f -name "*.php" 2>/dev/null | wc -l)
        copied_count=0
        skipped_count=0

        for file in "$SOURCE_CONTROLLERS"/*.php; do
            [ -f "$file" ] || continue
            filename=$(basename "$file")

            if [ ! -f "$INIT_DIR/$filename" ]; then
                if cp "$file" "$INIT_DIR/$filename" 2>/dev/null; then
                    echo "✓ Created $filename"
                    copied_count=$((copied_count + 1))
                fi
            else
                echo "⊘ Skipped $filename (already exists)"
                skipped_count=$((skipped_count + 1))
            fi
        done

        if [ $controller_files -gt 0 ]; then
            echo ""
            echo "Controllers: $copied_count created, $skipped_count skipped"
        fi
    fi

    if [ ! -f "$INIT_DIR/.env.example" ] && [ -f "/app/.env.example" ]; then
        cp /app/.env.example "$INIT_DIR/.env.example" 2>/dev/null || true
        echo "✓ Created .env.example"
    elif [ -f "$INIT_DIR/.env.example" ]; then
        echo "⊘ Skipped .env.example (already exists)"
    fi

    if [ ! -f "$INIT_DIR/docker-compose.yml" ] && [ -f "/app/docker-compose.template.yml" ]; then
        cp /app/docker-compose.template.yml "$INIT_DIR/docker-compose.yml" 2>/dev/null || true
        echo "✓ Created docker-compose.yml"
    elif [ -f "$INIT_DIR/docker-compose.yml" ]; then
        echo "⊘ Skipped docker-compose.yml (already exists)"
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

CONTROLLER_PATH="/app/controllers"

if [ ! -d "$CONTROLLER_PATH" ]; then
    echo "   Controller path does not exist: $CONTROLLER_PATH"
    echo "   Creating directory..."
    mkdir -p "$CONTROLLER_PATH"
fi

controller_count=$(find "$CONTROLLER_PATH" -maxdepth 1 -name "*.php" 2>/dev/null | wc -l)
tools_count=$(grep -r "#\[McpTool" "$CONTROLLER_PATH" 2>/dev/null | wc -l)
echo "Found $controller_count controller(s) with ~$tools_count tool(s) in: controllers"
echo ""

if [ ! -d "$MCP_SESSIONS_DIR" ]; then
    echo "Creating sessions directory: $MCP_SESSIONS_DIR"
    mkdir -p "$MCP_SESSIONS_DIR"
fi

exec "$@"
