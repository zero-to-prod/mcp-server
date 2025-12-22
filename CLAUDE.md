# CLAUDE.md

PHP 8.4 MCP server running in Docker. Controllers in `src/` expose MCP tools. Built-in: Redis (4 tools), MongoDB (5 tools).

## Commands

```bash
# Service control
docker compose up -d                              # Start
docker compose down                               # Stop
docker compose down && docker compose up -d       # Restart (for .env changes)

# Testing
docker exec mcp-demo php -l /app/src/File.php    # Check syntax
docker logs mcp-demo --tail 200                   # View logs
docker logs mcp-demo 2>&1 | grep -i error        # Search errors
```

**⚠️ After creating/modifying MCP tools, prompt user: "Run the /mcp command to reconnect"**

## Controller Structure

Self-contained plugins in `src/`. No cross-file dependencies.

```php
<?php declare(strict_types=1);

namespace App\Http\Controllers;

use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;
use Mcp\Exception\ToolCallException;
use Mcp\Schema\ToolAnnotations;

class Name {
    #[McpTool(
        name: 'service.noun.action',
        description: 'Purpose. USE/DO NOT USE. KEY/RETURNS.',
        annotations: new ToolAnnotations(title: 'service.noun.action')
    )]
    public function method(
        #[Schema(
            type: 'string',
            description: 'Purpose. Valid values. Example: "value"'
        )]
        string $param
    ): mixed {
        if (empty($param)) {throw new ToolCallException('param empty');}
        return $result;
    }
}
```

## Critical Rules

### Naming: `service.noun.action`
- Lowercase, dots only, singular noun
- Multi-word: underscores within parts (`by_id`)
- ✓ `redis.key.get` `mongodb.document.find` `api.user.search_by_id`
- ✗ `getUser` `service_user_get` `service.users.get`

### Attributes
- `annotations` ONLY in `#[McpTool()]`, NEVER in `#[Schema()]`
- `ToolAnnotations.title` MUST match tool `name` exactly

### Descriptions
- Tools: `Purpose. USE/DO NOT USE. KEY/RETURNS.`
- Params: `Purpose. Valid values/format. Example.`

### Errors
- `ToolCallException` for tools
- Format: `type error: details` (lowercase)
- `if (empty($val)) {throw new ToolCallException('param empty');}`
- `if (!in_array($val, $valid, true)) {throw new ToolCallException("invalid '{$val}': " . implode('|', $valid));}`

## Schema Reference

**Types:** `string` `number` `integer` `boolean` `array` `object` `null`

**Constraints:**
```php
minLength: 1, maxLength: 100, pattern: '/regex/', format: 'email'  // string
minimum: 0, maximum: 100                                            // number
minItems: 1, maxItems: 10                                           // array
enum: ['opt1', 'opt2']                                              // any type
```

## Environment (.env)

| Variable | Default | Purpose |
|----------|---------|---------|
| MCP_SERVER_NAME | mcp-server | Server/container name |
| MCP_CONTROLLER_PATHS | src | Controller paths (:separated) |
| REDIS_HOST | redis | Redis host |
| MONGODB_HOST | mongodb | MongoDB host |
| PORT | 8081 | Host port |

Changes require: `docker compose down && docker compose up -d`

## Docker

- Image: `davidsmith3/mcp-server:latest` (PHP 8.4+, FrankenPHP)
- Mount: `./src` → `/app/src`
- Sessions: `/app/storage/mcp-sessions`
- Startup: Creates dirs → Loads `.php` from controller path → Starts FrankenPHP:80

**Ref:** https://github.com/modelcontextprotocol/php-sdk
