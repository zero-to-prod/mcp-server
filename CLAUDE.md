# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

An extensible MCP (Model Context Protocol) server implementation in PHP using the official `mcp/sdk` package. The project enables running multiple independent MCP server instances from a single Docker image by mounting different controller directories.

## Core Architecture

### MCP Server Entry Points

- **HTTP Server**: `public/index.php` - Main entry point for HTTP/Docker deployments
  - Uses `StreamableHttpTransport` for HTTP communication
  - Configured via environment variables
  - Discovers controllers from paths specified in `MCP_CONTROLLER_PATHS`
  - Session storage in `MCP_SESSIONS_DIR` (default: `/app/storage/mcp-sessions`)

- **CLI Interface**: `bin/mcp-server` - Command-line tool
  - Simple CLI with `help`, `version`, and `list` commands
  - No STDIO transport implementation (HTTP-only server)

### Controller Discovery System

The server uses the MCP SDK's attribute-based discovery system:

```php
$controller_paths = !empty($_ENV['MCP_CONTROLLER_PATHS'])
    ? explode(':', $_ENV['MCP_CONTROLLER_PATHS'])
    : ['controllers', 'app/Http/Controllers'];

Server::builder()
    ->setServerInfo($_ENV['MCP_SERVER_NAME'] ?? 'MCP Server', $_ENV['APP_VERSION'] ?? '0.0.0')
    ->setDiscovery($base_dir, $controller_paths)
    ->setSession(new FileSessionStore($mcp_sessions_dir))
    ->setLogger($logger)
    ->build()
```

- **Discovery paths**: Colon-separated list in `MCP_CONTROLLER_PATHS` environment variable (default: `controllers`)
- **Base path**: Project root directory
- **Controllers namespace**: **Optional** - Can use `Controllers\`, `App\Http\Controllers`, or no namespace
- **File session storage**: `FileSessionStore` with configurable directory
- **Controller loading**: All PHP files in controller paths are automatically loaded with `require_once`

### MCP Controller Pattern

Controllers use PHP 8 attributes to define MCP capabilities. **Namespaces are optional** for maximum flexibility.

#### Without Namespace (Recommended for Simplicity)

```php
<?php

declare(strict_types=1);

use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;

class ExampleController
{
    #[McpTool(
        name: 'tool_name',
        description: 'Tool description'
    )]
    public function toolMethod(
        #[Schema(type: 'string', description: 'Parameter description')]
        string $param
    ): array {
        return ['result' => 'value'];
    }
}
```

#### With Namespace (Optional)

```php
<?php

declare(strict_types=1);

namespace Controllers;

use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;

class ExampleController
{
    #[McpTool(
        name: 'tool_name',
        description: 'Tool description'
    )]
    public function toolMethod(
        #[Schema(type: 'string', description: 'Parameter description')]
        string $param
    ): array {
        return ['result' => 'value'];
    }
}
```

**Available MCP Attributes**:
- `#[McpTool]` - Callable functions that perform actions
- `#[McpResource]` - Static data sources with fixed URIs
- `#[McpResourceTemplate]` - Dynamic resources with URI templates (RFC 6570)
- `#[McpPrompt]` - Template generators for AI prompts
- `#[Schema]` - Parameter validation and JSON schema generation
- `#[CompletionProvider]` - Auto-completion for dynamic parameters

**Key Pattern Details**:
- Controllers should use `Controllers\` namespace (or `App\Http\Controllers` for legacy support)
- Place controller files in `/controllers` directory (or `/app/Http/Controllers` for legacy)
- Use `#[Schema]` attribute for parameter descriptions and validation
- Tool return values are automatically wrapped in appropriate MCP content types
- Throw `ToolCallException` for user-facing errors (other exceptions show generic messages)
- Resource URIs must comply with RFC 3986 (standard schemes: `https://`, `file://`, `git://`, or custom: `config://`, `data://`, etc.)

### Multi-Instance Architecture

The Docker image supports running multiple independent servers:

- **Single image, multiple instances**: Mount different controller directories
- **Isolated sessions**: Each instance has separate session storage
- **Dynamic controllers**: No rebuild required for controller changes
- **Independent configuration**: Different ports, names, and environment variables per instance

Example multi-instance setup:
```bash
# Instance 1
docker run -d -p 8081:80 \
  -v ~/controllers1:/app/controllers:ro \
  -e MCP_SERVER_NAME=server1 \
  davidsmith3/mcp-server:latest

# Instance 2
docker run -d -p 8082:80 \
  -v ~/controllers2:/app/controllers:ro \
  -e MCP_SERVER_NAME=server2 \
  davidsmith3/mcp-server:latest
```

Note: `MCP_CONTROLLER_PATHS` defaults to `controllers`, so it's optional when using the default location.

## Common Development Commands

### Testing
```bash
# Run all tests
vendor/bin/phpunit

# Run specific test
vendor/bin/phpunit tests/Unit/IssuesControllerTest.php

# Run with coverage (if configured)
vendor/bin/phpunit --coverage-html coverage
```

### Docker Development

```bash
# Build Docker image
docker build -t mcp-server:latest .

# Build with specific version
docker build --build-arg VERSION=1.0.0 -t mcp-server:1.0.0 .

# Run development server (mounts local files)
docker compose up dev

# Run production server
docker compose --profile prod up prod

# View logs
docker compose logs -f dev
docker logs -f mcp-server  # for standalone containers
```

### Local Development (docker-compose)

```bash
# Start dev server (port 8080, live code mounting)
docker compose up dev

# Start prod server (port 8081, optimized build)
docker compose --profile prod up prod

# Run composer commands
docker compose --profile composer run --rm composer install
docker compose --profile composer run --rm composer update

# Stop services
docker compose down
```

### CLI Commands

```bash
# List available commands
vendor/bin/mcp-server list
php bin/mcp-server list

# Show help
vendor/bin/mcp-server help

# Show version
vendor/bin/mcp-server version
```

### Composer Operations

```bash
# Install dependencies
composer install

# Update dependencies
composer update

# Show installed packages
composer show

# Check for security vulnerabilities
composer audit
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_SERVER_NAME` | `MCP Server` | Display name in Claude Desktop |
| `MCP_CONTROLLER_PATHS` | `controllers` | Colon-separated controller discovery paths |
| `MCP_SESSIONS_DIR` | `/app/storage/mcp-sessions` | Session storage directory |
| `APP_VERSION` | `0.0.0` | Application version |
| `APP_DEBUG` | `false` | Enable debug logging (`true`/`false`) |
| `API_KEY` | - | API key for external services (controller-specific) |

## Project Structure

```
mcp-server/
├── app/
│   └── Http/
│       └── Controllers/     # Legacy MCP controllers location
├── bin/
│   └── mcp-server          # CLI entry point
├── controllers/            # MCP controllers (recommended location)
│   └── ExampleController.php
├── public/
│   └── index.php           # HTTP entry point
├── storage/
│   └── mcp-sessions/       # Session storage (runtime)
├── tests/
│   ├── TestCase.php
│   └── Unit/               # PHPUnit tests
├── vendor/                 # Composer dependencies
├── Caddyfile              # FrankenPHP/Caddy configuration
├── composer.json          # PHP dependencies
├── docker-compose.yml     # Multi-environment Docker setup
├── Dockerfile             # Production image
└── phpunit.xml           # PHPUnit configuration
```

## Docker Configuration

### Dockerfile Stages

- **build**: Development stage with Composer and all dependencies
- **production**: Optimized production image (default)
  - FrankenPHP 1 with PHP 8.4 Alpine
  - Pre-installed vendor dependencies
  - Read-only controller mounts
  - Health check on port 80

### docker-compose.yml Services

- **dev**: Development with live code mounting (port 8080)
- **prod**: Production build (port 8081, profile: `prod`)
- **composer**: Run Composer commands (profile: `composer`)

### Caddyfile

Simple FrankenPHP configuration serving `public/` directory on port 80 with PHP support.

## Testing Guidelines

- **Test namespace**: `Tests\`
- **Base class**: `Tests\TestCase` (extends `PHPUnit\Framework\TestCase`)
- **Test location**: `tests/Unit/` for unit tests
- **PHPUnit version**: <12.0 (PHP 8.4 compatible)
- **Configuration**: `phpunit.xml` - strict mode enabled, covers `src/` directory

## MCP SDK Integration

This project uses the official **`mcp/sdk`** (v0.1.0) from `modelcontextprotocol/php-sdk`:

- **Namespace**: `Mcp\` (not `PhpMcp\`)
- **Server builder**: `Mcp\Server::builder()`
- **Transports**:
  - `Mcp\Server\Transport\StreamableHttpTransport` (used)
  - `Mcp\Server\Transport\StdioTransport` (not used in this project)
- **Session stores**:
  - `Mcp\Server\Session\FileSessionStore` (used)
  - `Mcp\Server\Session\InMemorySessionStore`
  - `Mcp\Server\Session\Psr16StoreSession`
- **Content types**:
  - `Mcp\Schema\Content\TextContent`
  - `Mcp\Schema\Content\ImageContent`
  - `Mcp\Schema\Content\AudioContent`
  - `Mcp\Schema\Content\EmbeddedResource`
  - `Mcp\Schema\Content\TextResourceContents`
  - `Mcp\Schema\Content\BlobResourceContents`
- **Exceptions**:
  - `Mcp\Exception\ToolCallException` (for tool errors)
  - `Mcp\Exception\ResourceReadException` (for resource errors)
  - `Mcp\Exception\PromptGetException` (for prompt errors)

## Important Development Notes

### Controller Development

1. **Namespace**: **Optional** - Controllers can use `Controllers\` namespace, `App\Http\Controllers`, or no namespace at all
2. **File location**: Place controllers in `/controllers` directory (or `/app/Http/Controllers` for legacy)
3. **Attribute discovery**: Use `#[McpTool]`, `#[McpResource]`, etc. for automatic registration
4. **Parameter documentation**: Use `#[Schema]` for descriptions and validation
5. **Error handling**: Throw specific exceptions (`ToolCallException`, `ResourceReadException`, `PromptGetException`) for user-facing errors
6. **Return types**: Tool/resource methods can return primitives, arrays, or explicit content types - SDK handles conversion
7. **Auto-loading**: All PHP files in controller paths are automatically loaded with `require_once`

### Docker Image Updates

When modifying controllers:
1. No rebuild needed if using volume mounts (development)
2. Restart container to reload: `docker restart mcp-server`
3. For production images, rebuild and redeploy

### Logging

- **Debug logging**: Controlled by `APP_DEBUG` environment variable
- **Log output**: `error_log()` with timestamp and level
- **Format**: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message {context}`

### Session Management

- **Default**: File-based sessions in `MCP_SESSIONS_DIR`
- **Persistent**: Mount volume for `MCP_SESSIONS_DIR` to persist across restarts
- **Isolated**: Each Docker instance maintains separate sessions

## CI/CD Workflows

- **test.yml**: Run PHPUnit tests on PHP 8.4
- **backwards_compatibility.yml**: Check API compatibility
- **composer_require_checker.yml**: Validate dependencies
- **build_docker_image.yml**: Build and publish Docker images
- **annotate.yml**: Add annotations to PRs
- **release.yml**: Create releases

## PHP Version Requirements

- **Minimum**: PHP 8.4
- **Extensions**: `json`, `curl`
- **Type system**: Uses `declare(strict_types=1)` throughout

## Key Patterns

### Server Initialization Pattern

```php
Server::builder()
    ->setServerInfo($name, $version)
    ->setDiscovery($basePath, $scanDirs)
    ->setSession($sessionStore)
    ->setLogger($logger)
    ->build()
    ->run($transport);
```

### Controller Parameter Pattern

Use `#[Schema]` for all parameters to provide descriptions:

```php
#[McpTool(name: 'example_tool', description: 'Tool description')]
public function exampleMethod(
    #[Schema(type: 'string', description: 'What this parameter does')]
    string $param1,

    #[Schema(type: 'integer', minimum: 1, description: 'Numeric parameter')]
    int $param2
): array {
    // Implementation
}
```

### Resource URI Pattern

Use descriptive, hierarchical URIs:
- `config://app/settings`
- `data://user/profile`
- `api://external/service`
- `file:///path/to/resource`

### Multi-Instance Environment Pattern

```bash
MCP_SERVER_NAME=unique-name
MCP_CONTROLLER_PATHS=path1:path2:path3
MCP_SESSIONS_DIR=/custom/path
```