# mcp-server

[![Repo](https://img.shields.io/badge/github-gray?logo=github)](https://github.com/zero-to-prod/mcp-server)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/zero-to-prod/mcp-server/test.yml?label=test)](https://github.com/zero-to-prod/mcp-server/actions)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/zero-to-prod/mcp-server/backwards_compatibility.yml?label=backwards_compatibility)](https://github.com/zero-to-prod/mcp-server/actions)
[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/zero-to-prod/mcp-server/build_docker_image.yml?label=build_docker_image)](https://github.com/zero-to-prod/mcp-server/actions)
[![GitHub License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](https://github.com/zero-to-prod/mcp-server/blob/main/LICENSE.md)
[![Hits-of-Code](https://hitsofcode.com/github/zero-to-prod/mcp-server?branch=main)](https://hitsofcode.com/github/zero-to-prod/mcp-server/view?branch=main)

## Contents

- [Introduction](#introduction)
- [Quick Start](#quick-start)
- [Multiple Instances](#multiple-instances)
- [Requirements](#requirements)
- [Creating Controllers](#creating-controllers)
- [Environment Variables](#environment-variables)
- [Contributing](#contributing)

## Introduction

An Extensible MCP Server

A lightweight PHP 8.4 MCP (Model Context Protocol) server packaged as a Docker image. Mount your PHP controllers and expose them as MCP tools to Claude Desktop.

## Quick Start

### Minimal Example (Recommended)

Start a server with your own controllers:

- Create your controller file locally
- Then mount it to the container

```shell
docker run -d --name mcp1 -p 8092:80 \
  -v $(pwd):/app/Http/Controllers \
  -v mcp1-sessions:/app/storage/mcp-sessions \
  -e MCP_SERVER_NAME=mcp1 \
  -e APP_DEBUG=false \
  davidsmith3/mcp-server:latest
```

Add to Claude Desktop:

```shell
claude mcp add --transport http mcp1 http://localhost:8092
```

### Kitchen Sink (Full Development)

For complete control, copy the entire app and mount it.

- Copy server files to local directory

```shell
docker run --rm -v ./mcp2:/copy davidsmith3/mcp-server:latest sh -c "cp -a /app/. /copy/"
```

Start with full app mount

```shell
docker run -d --name mcp2 -p 8093:80 \
  -v ./mcp2:/app \
  -v mcp2-sessions:/app/storage/mcp-sessions \
  -e MCP_SERVER_NAME=mcp2 \
  davidsmith3/mcp-server:latest
```

Add to Claude Desktop

```shell
claude mcp add --transport http mcp2 http://localhost:8093
```

## Multiple Instances

Run multiple independent MCP servers from a single Docker image by mounting different controller directories.

### Architecture Benefits

- **Single Image, Multiple Servers**: Build once, run many times with different configurations
- **Isolated Sessions**: Each instance maintains separate session storage
- **Dynamic Controllers**: Mount any PHP controllers at runtime without rebuilding
- **Easy Scaling**: Spin up new instances by changing port and mount path

### Running Multiple Instances

Instance 1: Monitoring

```shell
docker run -d --name mcp-monitoring -p 8081:80 \
  -v ~/mcp-servers/monitoring/controllers:/app/Http/Controllers \
  -e MCP_SERVER_NAME=monitoring \
  -e API_KEY=your_key \
  davidsmith3/mcp-server:latest
```

Instance 2: Weather tools

```shell
docker run -d --name mcp-weather -p 8082:80 \
  -v ~/mcp-servers/weather/controllers:/app/Http/Controllers \
  -e MCP_SERVER_NAME=weather \
  davidsmith3/mcp-server:latest
```

Instance 3: Database utilities

```shell
docker run -d --name mcp-database -p 8083:80 \
  -v ~/mcp-servers/database/controllers:/app/Http/Controllers \
  -e MCP_SERVER_NAME=database \
  davidsmith3/mcp-server:latest
```

Each instance runs independently with different ports, controllers, names, and sessions.

## Requirements

- PHP 8.4 or higher
- Docker (for containerized deployment)

## Creating Controllers

Controllers are PHP classes with MCP attributes. Place them in the directory you mount to `/app/Http/Controllers`.

### Controller Structure

**Namespace is optional** - controllers work with or without a namespace:

```php
<?php

declare(strict_types=1);

namespace App\Http\Controllers;  // Optional

use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;

class MyController
{
    #[McpTool(
        name: 'my_tool',
        description: 'What this tool does'
    )]
    public function myTool(
        #[Schema(type: 'string', description: 'Parameter description')]
        string $param
    ): array {
        return ['result' => 'value'];
    }
}
```

### Available Attributes

- `#[McpTool]` - Expose a method as an MCP tool
- `#[McpResource]` - Expose static data with a URI
- `#[McpResourceTemplate]` - Dynamic resources with URI templates
- `#[McpPrompt]` - Template generators for AI prompts
- `#[Schema]` - Parameter validation and descriptions

### Examples

**Simple Tool:**

```php
<?php

namespace App\Http\Controllers;

use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;

class Greet
{
    #[McpTool(description: 'Greet someone by name')]
    public function greet(
        #[Schema(description: 'Name to greet')]
        string $name = 'World'
    ): string {
        return "Hello, {$name}!";
    }
}
```

**Resource:**

```php
<?php

namespace App\Http\Controllers;

use Mcp\Capability\Attribute\McpResource;

class Config
{
    #[McpResource(
        uri: 'config://app/settings',
        description: 'Application configuration'
    )]
    public function getSettings(): array {
        return [
            'version' => '1.0.0',
            'environment' => 'production'
        ];
    }
}
```

**Multiple Tools:**

```php
<?php

namespace App\Http\Controllers;

use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;

class MathTools
{
    #[McpTool(description: 'Add two numbers')]
    public function add(
        #[Schema(description: 'First number')] float $a,
        #[Schema(description: 'Second number')] float $b
    ): float {
        return $a + $b;
    }

    #[McpTool(description: 'Multiply two numbers')]
    public function multiply(float $a, float $b): float {
        return $a * $b;
    }
}
```

## Environment Variables

Configure the MCP server using environment variables:

| Variable           | Default                     | Description                                  |
|--------------------|-----------------------------|----------------------------------------------|
| `MCP_SERVER_NAME`  | `MCP Server`                | Display name shown in Claude Desktop         |
| `MCP_SESSIONS_DIR` | `/app/storage/mcp-sessions` | Directory for session storage                |
| `APP_VERSION`      | `0.0.0`                     | Application version displayed in server info |
| `APP_DEBUG`        | `false`                     | Enable debug logging (`true` or `false`)     |
| `API_KEY`          | -                           | API keys (controller-specific)               |

### Example with Custom Configuration

```shell
docker run -d -p 8081:80 \
  -v ./controllers:/app/Http/Controllers \
  -e MCP_SERVER_NAME=my-mcp-server \
  -e API_KEY=your_api_key_here \
  -e APP_DEBUG=true \
  davidsmith3/mcp-server:latest
```

### Persistent Sessions

Mount a volume for session persistence:

```shell
docker run -d -p 8081:80 \
  -v ./controllers:/app/Http/Controllers \
  -v mcp-sessions:/app/storage/mcp-sessions \
  davidsmith3/mcp-server:latest
```

## Key Technical Details

### Controller Discovery

- **Path**: `/app/Http/Controllers` (hardcoded)
- **Mount**: Use `-v $(pwd):/app/Http/Controllers` to mount local controllers
- **Namespace**: Optional - `App\Http\Controllers` or no namespace both work
- **Auto-loading**: All `.php` files in the controller path are automatically loaded

### README Publishing

When you mount controllers to `/app/Http/Controllers`, the container automatically publishes this README.md to your mounted directory on first run (if it doesn't already exist). This provides local documentation.

### Container Behavior

On startup, the entrypoint:
1. Validates controller path exists (creates if missing)
2. Counts controllers and tools found
3. Publishes README.md to mounted directory (if not present)
4. Creates session directory (if not exists)
5. Starts FrankenPHP server on port 80

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on contributing to this project.
