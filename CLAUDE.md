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
    : ['src'];

Server::builder()
    ->setServerInfo($_ENV['MCP_SERVER_NAME'] ?? 'MCP Server', $_ENV['APP_VERSION'] ?? '0.0.0')
    ->setDiscovery($base_dir, $controller_paths)
    ->setSession(new FileSessionStore($mcp_sessions_dir))
    ->setLogger($logger)
    ->build()
```

- **Discovery paths**: Colon-separated list in `MCP_CONTROLLER_PATHS` environment variable (default: `src`)
  - Can be relative (e.g., `src`, `custom`) or absolute (e.g., `/app/controllers`)
  - Multiple paths supported: `src:custom:/absolute/path`
- **Base path**: Project root directory (`/app` in container)
- **Controllers namespace**: **Optional** - Can use `Controllers\` or no namespace
- **File session storage**: `FileSessionStore` with configurable directory
- **Controller loading**: All PHP files in controller paths are automatically loaded with `require_once`
- **Default location**: Controllers are stored in `src/` directory (mounted from host)

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
- Controllers should use `Controllers\` namespace (or no namespace)
- Place controller files in `src/` directory (or custom path via `MCP_CONTROLLER_PATHS`)
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
# Instance 1 - Mount local src1/ directory
docker run -d -p 8081:80 \
  -v ~/project1/src:/app/src:ro \
  -e MCP_SERVER_NAME=server1 \
  davidsmith3/mcp-server:latest

# Instance 2 - Mount local src2/ directory
docker run -d -p 8082:80 \
  -v ~/project2/src:/app/src:ro \
  -e MCP_SERVER_NAME=server2 \
  davidsmith3/mcp-server:latest

# Instance 3 - Use multiple controller paths
docker run -d -p 8083:80 \
  -v ~/project3/src:/app/src:ro \
  -v ~/shared:/app/shared:ro \
  -e MCP_SERVER_NAME=server3 \
  -e MCP_CONTROLLER_PATHS=src:shared \
  davidsmith3/mcp-server:latest
```

Note: `MCP_CONTROLLER_PATHS` defaults to `src`, so it's optional when using the default location.

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
| `MCP_CONTROLLER_PATHS` | `src` | Colon-separated controller discovery paths |
| `MCP_SESSIONS_DIR` | `/app/storage/mcp-sessions` | Session storage directory |
| `APP_VERSION` | `0.0.0` | Application version |
| `APP_DEBUG` | `false` | Enable debug logging (`true`/`false`) |
| `API_KEY` | - | API key for external services (controller-specific) |

## Project Structure

```
mcp-server/
├── app/
│   └── Http/
│       └── Controllers/     # Legacy location (not used)
├── bin/
│   └── mcp-server          # CLI entry point
├── src/                    # MCP controllers (default location)
│   ├── Redis.php
│   └── Mongodb.php
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

1. **Namespace**: **Optional** - Controllers can use `Controllers\` namespace or no namespace at all
2. **File location**: Place controllers in `/src` directory (or custom path via `MCP_CONTROLLER_PATHS`)
3. **Attribute discovery**: Use `#[McpTool]`, `#[McpResource]`, etc. for automatic registration
4. **Parameter documentation**: Use `#[Schema]` for descriptions and validation
5. **Error handling**: Throw specific exceptions (`ToolCallException`, `ResourceReadException`, `PromptGetException`) for user-facing errors
6. **Return types**: Tool/resource methods can return primitives, arrays, or explicit content types - SDK handles conversion
7. **Auto-loading**: All PHP files in controller paths are automatically loaded with `require_once`

### Error Handling

The MCP server implements comprehensive error handling using specialized exceptions that preserve error messages for clients, allowing LLMs to see errors and self-correct.

#### Specialized Exception Types

**1. ToolCallException** - For tool execution errors

Use when tool methods encounter validation errors, business logic failures, or any user-facing errors:

```php
use Mcp\Exception\ToolCallException;

#[McpTool(name: 'divide', description: 'Divides two numbers')]
public function divide(float $a, float $b): float {
    if ($b === 0.0) {
        throw new ToolCallException('Division by zero is not allowed');
    }
    return $a / $b;
}
```

**2. ResourceReadException** - For resource access errors

Use when resource methods fail to read or access data:

```php
use Mcp\Exception\ResourceReadException;

#[McpResource(uri: 'config://app/settings')]
public function getAppSettings(): array {
    if (!file_exists($config_file)) {
        throw new ResourceReadException("Configuration file not found: {$config_file}");
    }

    $content = file_get_contents($config_file);
    if ($content === false) {
        throw new ResourceReadException("Failed to read configuration file");
    }

    return json_decode($content, true);
}
```

**3. PromptGetException** - For prompt generation errors

Use when prompt methods encounter validation or generation failures:

```php
use Mcp\Exception\PromptGetException;

#[McpPrompt(name: 'code_review_prompt')]
public function codeReviewPrompt(string $style): array {
    $valid_styles = ['strict', 'balanced', 'lenient'];

    if (!in_array($style, $valid_styles, true)) {
        throw new PromptGetException(
            "Invalid style: {$style}. Must be one of: " . implode(', ', $valid_styles)
        );
    }

    return [['role' => 'user', 'content' => $prompts[$style]]];
}
```

#### Exception Behavior

- **Specialized exceptions**: Error messages are **preserved** and sent to the client in the JSON-RPC response
  - `ToolCallException` → `CallToolResult` with `isError: true`
  - `ResourceReadException` → JSON-RPC error response with message
  - `PromptGetException` → JSON-RPC error response with message

- **Generic exceptions**: Error messages are **hidden** - client receives a generic error message
  - Use for internal errors that shouldn't expose implementation details
  - Actual error is logged on the server but not exposed to clients

#### Error Handling Best Practices

1. **Always validate input**: Check parameters before processing
```php
if (empty($path)) {
    throw new ToolCallException('File path cannot be empty');
}

if (strlen($name) > 100) {
    throw new ToolCallException('Name is too long. Maximum length is 100 characters.');
}
```

2. **Provide clear, actionable error messages**: Help the LLM understand what went wrong
```php
// Good: Specific and actionable
throw new ToolCallException('Invalid email format: must contain @ symbol');

// Bad: Vague and unhelpful
throw new ToolCallException('Invalid input');
```

3. **Use specialized exceptions for user-facing errors**: Always use the appropriate MCP exception type
```php
// Good: Uses specialized exception
if (!file_exists($path)) {
    throw new ResourceReadException("File not found: {$path}");
}

// Bad: Generic exception hides the error from client
if (!file_exists($path)) {
    throw new \RuntimeException("File not found: {$path}");
}
```

4. **Validate early, fail fast**: Check all preconditions before processing
```php
public function processFile(string $path): array {
    // Validate all inputs first
    if (empty($path)) {
        throw new ToolCallException('File path cannot be empty');
    }

    if (str_contains($path, '..')) {
        throw new ToolCallException('Path traversal is not allowed');
    }

    if (!file_exists($path)) {
        throw new ToolCallException("File not found: {$path}");
    }

    // Now process the file
    return $this->process($path);
}
```

5. **Use generic exceptions for internal errors**: Don't expose sensitive implementation details
```php
try {
    $connection = $this->connectToDatabase($credentials);
} catch (\PDOException $e) {
    // Log the detailed error internally
    error_log("Database connection failed: " . $e->getMessage());

    // Throw generic exception to hide credentials from client
    throw new \RuntimeException('Database connection failed');
}
```

#### Global Error Handling

The server includes a global exception handler in `public/index.php` that:
- Logs all uncaught exceptions with full stack traces
- Returns proper JSON-RPC error responses
- Exposes exception details only when `APP_DEBUG=true`
- Ensures graceful degradation for unexpected errors

#### Logging Configuration

The logger is configured to:
- Always log errors (error, critical, alert, emergency levels)
- Log all levels when `APP_DEBUG=true`
- Include timestamps, levels, and JSON context
- Output to PHP's `error_log()`

#### Example: Complete Error Handling Pattern

```php
#[McpTool(name: 'validate_email', description: 'Validates an email address')]
public function validateEmail(string $email): array {
    // Input validation
    if (empty($email)) {
        throw new ToolCallException('Email address cannot be empty');
    }

    if (strlen($email) > 254) {
        throw new ToolCallException('Email address is too long (max 254 characters)');
    }

    // Format validation
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        throw new ToolCallException("Invalid email format: {$email}");
    }

    // Success
    return ['valid' => true, 'email' => $email];
}
```

For comprehensive examples, see `controllers/` for reference implementations.

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

**Single controller directory (default):**
```bash
MCP_CONTROLLER_PATHS=src
```

**Multiple controller directories (colon-separated):**
```bash
MCP_CONTROLLER_PATHS=src:custom_controllers:shared_tools
```

**Full environment configuration:**
```bash
MCP_SERVER_NAME=unique-name
MCP_CONTROLLER_PATHS=path1:path2:path3
MCP_SESSIONS_DIR=/custom/path
```

**Docker example with custom controller path:**
```bash
docker run -d -p 8081:80 \
  -v ~/my-tools:/app/my-tools:ro \
  -e MCP_CONTROLLER_PATHS=my-tools \
  -e MCP_SERVER_NAME=my-server \
  davidsmith3/mcp-server:latest
```