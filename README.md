# MCP Server - Technical Specification

PHP 8.4 MCP (Model Context Protocol) server. Docker image. Mount controllers, expose as MCP tools.

## Quick Start

**One-line install** (recommended):

```shell
curl -fsSL https://raw.githubusercontent.com/zero-to-prod/mcp-server/main/install.sh | bash
```

The installer will:

- Pull the latest Docker image with MongoDB support
- Create project files and configuration
- Start Redis and MongoDB services
- Configure the MCP server

Or manually:

### 1. Initialize project directory

Create template files (README.md, Example.php, .env.example):

```shell
docker run --rm -v $(pwd):/init davidsmith3/mcp-server:latest init
```

### 2. Configure environment

Edit .env with your settings (MCP_SERVER_NAME, ports, etc.)

```shell
cp .env.example .env
```

### 3. Start server

**Option A: docker-compose** (recommended)

```shell
docker compose up -d
```

### 4. Connect to Claude Desktop

```shell
claude mcp add --transport http mcp1 http://localhost:8093
```

## Docker Operations

### When environment variables change

When adding or modifying environment variables in `.env`:

**1. Restart Docker containers:**

```shell
docker compose down && docker compose up -d
```

**2. Reconnect MCP client:**

- Prompt the user to manually reconnect using their MCP client
- For Claude Code CLI users: Use the `/mcp` command

Environment variables only load at container startup. Changes require full restart.

### When MCP tools change

When adding, removing, or modifying MCP tools (controller methods with `#[McpTool]`, `#[McpResource]`, etc.):

**No Docker restart needed.** Just reconnect MCP client:

- Prompt the user to manually reconnect using their MCP client
- For Claude Code CLI users: Use the `/mcp` command

The MCP client caches tool definitions. Reconnection forces discovery without restarting containers.

## Plugin Architecture

Each controller file is a self-contained plugin:

- No shared dependencies between files
- Include all required imports in each file
- Each file operates independently
- No cross-file references

**CRITICAL: Where to create controller files**

Create controller files **in the root of your project directory** (same directory as `.env` and `docker-compose.yml`), NOT in a `controllers/` subdirectory.

Your project directory gets mounted as `/app/controllers` inside the Docker container.

**Example project structure:**

```
your-project/
.env
docker-compose.yml
MyController.php    <- Create controllers here (root)
Redis.php           <- Create controllers here (root)
```

**File structure:**

```php
<?php
declare(strict_types=1);

// Include ALL imports needed by THIS file
use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;
use Mcp\Exception\ToolCallException;
use Mcp\Schema\ToolAnnotations;

class PluginController {
// All methods and dependencies in one file
}
```

## Tool Naming Convention

**All MCP tool names MUST follow: `service.noun.action`**

- **service**: System being accessed (lowercase)
- **noun**: Resource type, singular (lowercase)
- **action**: Operation verb (lowercase)
- **Separator**: Dots only (`.`)
- **Multi-word parts**: Underscores within parts only (`by_id`, `awaiting_shipment`)

**Pattern:** `service.noun.action`

**Examples:**

```
✓ service.user.get
✓ service.users.list
✓ service.order.create
✓ service.item.search_by_id
✓ api.logs.aggregate

✗ getUser              (missing service.noun)
✗ service_user_get     (underscores not dots)
✗ Service.User.Get     (not lowercase)
✗ service.users.get    (plural noun for singular action)
```

**Action verbs:** `get` `list` `create` `update` `delete` `search` `calculate` `transform` `aggregate`

## Redis Integration

Access Redis directly via `Redis.php` controller. Provides 4 tools for key inspection and raw command execution.

### Setup

**Environment (.env):**

```bash
REDIS_HOST=redis          # Container name or IP
REDIS_PORT=6379
REDIS_PASSWORD=           # Optional
```

**Docker Compose (included by default):**

```yaml
services:
mcp:
depends_on: [ redis ]
redis:
image: redis:7-alpine
command: redis-server --appendonly yes
```

### Redis Tools (Redis.php in your project root)

**redis.inspect** - Get metadata + preview + TTL

```php
redis.inspect("mykey")  // Returns: {key, metadata: {type, size, count}, preview: [...], ttl}
```

Use first to explore keys before loading full data. Shows structure without full load.

**redis.get** - Retrieve full data from key

```php
redis.get("mykey")  // Returns: complete dataset
```

Use after confirming data size via inspect. Loads all data into context.

**redis.exists** - Check if key exists

```php
redis.exists("mykey")  // Returns: {key, exists: bool, ttl: int|null}
```

Quick validation without loading data.

**redis.command** - Execute raw Redis commands

```php
redis.command("KEYS ref:*")     // Find keys by pattern
redis.command("SCAN 0 MATCH ref:* COUNT 100")  // Production-safe scanning
redis.command("TTL mykey")      // Get time to live
```

Direct pass-through to Redis server. Supports all Redis commands (GET, SET, KEYS, SCAN, HGET, LRANGE, etc.).

**WARNING:** Destructive commands (DEL, FLUSHDB) execute without confirmation.

### Pattern

Standard workflow: `redis.exists` → `redis.inspect` → `redis.get` (load full data last)

## MongoDB Integration

Access MongoDB directly via `Mongodb.php` controller. Provides 5 tools for document operations and aggregations.

### Setup

**Environment (.env):**

```bash
MONGODB_HOST=mongodb      # Container name or IP
MONGODB_PORT=27017
MONGODB_USERNAME=         # Optional
MONGODB_PASSWORD=         # Optional
```

**Docker Compose (included by default):**

```yaml
services:
mcp:
depends_on: [ redis, mongodb ]
mongodb:
image: mongo:8
volumes:
  - mongodb-data:/data/db
```

### MongoDB Tools (Mongodb.php in your project root)

**mongodb.document.find** - Query documents in collection

```php
mongodb.document.find(
"mydb",
"users",
"{\"status\": \"active\", \"_limit\": 10}"
)
```

Returns matching documents. Use `_limit` in query to limit results.

**mongodb.document.insert** - Insert documents

```php
// Insert one
mongodb.document.insert("mydb", "users", "{\"name\": \"John\", \"email\": \"john@example.com\"}")

// Insert many
mongodb.document.insert("mydb", "users", "[{\"name\": \"John\"}, {\"name\": \"Jane\"}]")
```

Supports single or bulk insert operations.

**mongodb.document.update** - Update documents

```php
mongodb.document.update(
"mydb",
"users",
"{\"_id\": \"...\"}",
"{\"$set\": {\"status\": \"active\"}}"
)
```

Update one or many documents with MongoDB update operators. Use `_multiple: true` in filter to update many.

**mongodb.document.delete** - Delete documents

```php
// Delete one
mongodb.document.delete("mydb", "users", "{\"_id\": \"...\"}")

// Delete many
mongodb.document.delete("mydb", "users", "{\"status\": \"archived\", \"_multiple\": true}")
```

Delete one or many documents matching filter criteria. Use `_multiple: true` for bulk deletion.

**WARNING:** Delete operations are permanent.

**mongodb.data.aggregate** - Run aggregation pipeline

```php
mongodb.data.aggregate(
"mydb",
"orders",
"[
{\"$match\": {\"status\": \"completed\"}},
{\"$group\": {\"_id\": \"$userId\", \"total\": {\"$sum\": \"$amount\"}}},
{\"$sort\": {\"total\": -1}},
{\"$limit\": 10}
]"
)
```

Execute complex data transformations and analytics using MongoDB's aggregation framework.

### Authentication

MongoDB authentication is optional. To enable:

1. Set environment variables:

```bash
MONGODB_USERNAME=admin
MONGODB_PASSWORD=secure_password
```

2. Restart services:

```bash
docker compose restart
```

### Pattern

Standard workflow:

1. Find documents: `mongodb.document.find` with query filters
2. Modify data: `mongodb.document.insert`, `mongodb.document.update`, or `mongodb.document.delete`
3. Analytics: `mongodb.data.aggregate` for complex queries and reporting

### Container Log Access

Access container logs using Docker commands. Logs contain PHP errors, MCP server output, and application errors.

#### Essential Commands

**Find container name:**

```bash
docker ps                                 # Running containers
docker compose ps                         # Compose services
```

**View logs:**

```bash
docker logs mcp-server --tail 200         # Last 200 lines
docker logs -f mcp-server                 # Follow (real-time)
docker logs mcp-server --since 1h         # Last hour
docker compose logs mcp                   # Compose service
```

**Search and filter (pipe to grep, same as datadog):**

```bash
docker logs mcp-server 2>&1 | grep -i error
docker logs mcp-server 2>&1 | grep "tool_name"
```

**Check environment:**

```bash
docker exec mcp-server env | grep MCP     # MCP config
docker exec mcp-server env | grep REDIS   # Redis config
```

## Testing Tools

After creating or modifying tools, verify functionality:

### 1. Reconnect MCP client

**Manual reconnection required.** There is no command line tool to reconnect. The agent must prompt the user to manually reconnect using their MCP client.

For Claude Code CLI users: Use the `/mcp` command to reconnect.

### 2. Test tool execution

Test your tools directly in your MCP client (Claude Desktop or Claude Code CLI) after reconnecting.

**Validation checklist:**

- Tool executes without errors
- Return value matches expected format
- Error cases throw appropriate exceptions
- Parameter validation works correctly

### 3. Debug failures

**Check container logs:**

```shell
docker logs mcp1
```

**Check syntax errors:**

```shell
# Path inside Docker container (your root files are mounted to /app/controllers)
docker exec mcp1 php -l /app/controllers/YourController.php
```

**Verify environment:**

```shell
docker exec mcp1 env | grep MCP
```

## Environment Variables

Variables read by the server (public/index.php):

| Variable         | Default    | Description                         | Used In         |
|------------------|------------|-------------------------------------|-----------------|
| MCP_SERVER_NAME  | MCP Server | Server display name                 | index.php:92    |
| APP_VERSION      | 0.0.0      | Version string                      | index.php:92    |
| APP_DEBUG        | false      | Enable debug logs (true/false)      | index.php:29,55 |
| REDIS_HOST       | redis      | Redis host (container name or IP)   | Redis.php:18    |
| REDIS_PORT       | 6379       | Redis port                          | Redis.php:19    |
| REDIS_PASSWORD   | -          | Redis password (optional)           | Redis.php:20    |
| MONGODB_HOST     | mongodb    | MongoDB host (container name or IP) | Mongodb.php:18  |
| MONGODB_PORT     | 27017      | MongoDB port                        | Mongodb.php:19  |
| MONGODB_USERNAME | -          | MongoDB username (optional)         | Mongodb.php:20  |
| MONGODB_PASSWORD | -          | MongoDB password (optional)         | Mongodb.php:21  |

Additional variables in .env.example (not used in code):

| Variable             | Note                                               |
|----------------------|----------------------------------------------------|
| MCP_CONTROLLER_PATHS | Hardcoded to `controllers` in index.php:81         |
| MCP_SESSIONS_DIR     | Hardcoded to `storage/mcp-sessions` in index.php:8 |
| API_KEY              | Available for controller use, not used by core     |
| PORT                 | Docker-specific, used in docker-compose.yml        |
| DOCKER_IMAGE         | Docker-specific, used in docker-compose.yml        |

## SDK Documentation

**Official source:** https://github.com/modelcontextprotocol/php-sdk

Reference the official PHP SDK repository for:

- Latest API changes
- Complete method signatures
- Advanced configuration options
- Implementation examples
- Version-specific features

## MCP SDK Reference

### File Structure

```php
<?php
declare(strict_types=1);
namespace App\Http\Controllers;  // optional

class ControllerName {
// methods with attributes
}
```

### 1. Tool (action/function)

**Syntax:**

```php
#[McpTool(
name: 'tool_name',
description: 'Concise tool description (1-2 sentences). Key behavior if needed.',
annotations: new ToolAnnotations(
    title: 'tool_name'  // MUST match name exactly
)
)]
public function method(
#[Schema(
    type: 'TYPE',
    description: 'Purpose. Valid values/format. Example: "value"',
    pattern: '/regex/',      // optional validation
    enum: ['val1', 'val2']   // optional enum constraint
)]
TYPE $param
): RETURN_TYPE {
if (/* error */) {throw new ToolCallException('error: details');}
return $result;
}
```

**ToolAnnotations title:** MUST match the tool name exactly. Pattern: `title: 'service.noun.action'` matches `name: 'service.noun.action'`

**CRITICAL: annotations placement**

✅ **CORRECT:** Place `annotations` ONLY in `#[McpTool(...)]` at method level

```php
#[McpTool(
name: 'tool.name',
description: 'Description...',
annotations: new ToolAnnotations(title: 'tool.name')  // <- HERE
)]
public function method(
#[Schema(type: 'string', description: 'Description...')]  // <- NO annotations
string $param
)
```

❌ **WRONG:** Never place `annotations` inside `#[Schema(...)]` for parameters

```php
#[Schema(
type: 'string',
description: 'Description...',
annotations: new ToolAnnotations(...)  // <- NEVER DO THIS
)]
```

**Return types:** primitives, arrays, or explicit content objects (TextContent, ImageContent, AudioContent, EmbeddedResource)

**Schema types:** `string` `number` `integer` `boolean` `array` `object` `null`

**Example:**

```php
#[McpTool(
name: 'divide',
description: 'Divides two numbers. Returns float result. Throws exception if divisor is zero.',
annotations: new ToolAnnotations(
    title: 'divide'
)
)]
public function divide(
#[Schema(
    type: 'number',
    description: 'Dividend (number to be divided). Example: 10.5, -20, 100'
)]
float $a,
#[Schema(
    type: 'number',
    description: 'Divisor (cannot be zero). Example: 2.5, -4, 0.1'
)]
float $b
): float {
if ($b === 0.0) {throw new ToolCallException('cannot divide by zero');}
return $a / $b;
}
```

### 2. Resource (static data, fixed URI)

**Syntax:**

```php
#[McpResource(
uri: 'scheme://path',                    // required, RFC 3986
name: 'Name',                            // optional
description: 'Concise resource description (what data it provides).',
mimeType: 'application/json',            // optional
size: 1024                               // optional, bytes
)]
public function method(): mixed {
if (/* error */) {throw new ResourceReadException('error: details');}
return $data;
}
```

**URI schemes:** `file://` `https://` `git://` `config://` `data://` `db://` `api://` (custom)

**Return types:** primitives, arrays, Stream, SplFileInfo, TextResourceContents, BlobResourceContents, `['text' => '...']`, `['blob' => 'base64...']`

**Example:**

```php
#[McpResource(
uri: 'config://app/settings',
name: 'Application Settings',
description: 'Returns application configuration as JSON (runtime settings, feature flags, environment values).',
mimeType: 'application/json'
)]
public function getSettings(): array {
$file = '/path/to/settings.json';
if (!file_exists($file)) {throw new ResourceReadException("not found: {$file}");}
return json_decode(file_get_contents($file), true);
}
```

### 3. Resource Template (dynamic data, variable URI)

**Syntax:**

```php
#[McpResourceTemplate(
uriTemplate: 'scheme://path/{var}',      // required, RFC 6570
name: 'Name',                            // optional
description: 'Concise resource template description (what data it provides by variable).',
mimeType: 'application/json'             // optional
)]
public function method(
#[Schema(
    type: 'string',
    description: 'Variable description (format, constraints). Example: "value"',
    pattern: '/^[a-z0-9]+$/'             // optional validation
)]
string $var
): mixed {
if (/* error */) {throw new ResourceReadException('error: details');}
return $data;
}
```

**Rules:**

- URI format: RFC 6570 with `{variable}` placeholders
- Variable names must match method parameter names exactly
- Parameter order matters: variables passed in URI template order
- All variables required (no optional parameters)
- Return types: same as Resource (primitives, arrays, Stream, SplFileInfo, TextResourceContents, BlobResourceContents)

**Example:**

```php
#[McpResourceTemplate(
uriTemplate: 'data://user/{userId}',
name: 'User Data',
description: 'Returns user data by ID from data store. Throws exception if not found.',
mimeType: 'application/json'
)]
public function getUser(
#[Schema(
    type: 'string',
    description: 'User ID (alphanumeric lowercase). Example: "user123", "abc456"',
    pattern: '/^[a-z0-9]+$/'
)]
string $userId
): array {
if (!ctype_alnum($userId)) {throw new ResourceReadException('userId must be alphanumeric');}
if (!$user = $this->find($userId)) {throw new ResourceReadException("not found: {$userId}");}
return $user;
}
```

### 4. Prompt (AI template generation)

**Syntax:**

```php
#[McpPrompt(
name: 'name',                          // required
description: 'Concise prompt description (what it generates and purpose).'
)]
public function method(
#[Schema(
    type: 'TYPE',
    description: 'Parameter description. Valid values. Example: "value"',
    enum: ['opt1', 'opt2']             // optional
)]
TYPE $param
): array {
if (/* error */) {throw new PromptGetException('error: details');}
return [['role' => 'user', 'content' => ['type' => 'text', 'text' => 'prompt']]];
}
```

**Return formats:**

1. Array with role+content: `[['role' => 'user', 'content' => ['type' => 'text', 'text' => '...']]]`
2. Associative: `['user' => 'message', 'assistant' => 'response']`
3. PromptMessage objects with Role enums

**Valid roles:** `user` (input/questions), `assistant` (responses/instructions)

**Example:**

```php
#[McpPrompt(
name: 'review',
description: 'Generates code review prompt with configurable style and rigor level.'
)]
public function review(
#[Schema(
    type: 'string',
    description: 'Review style. Valid: strict, balanced (default), lenient. Example: "balanced"',
    enum: ['strict', 'balanced', 'lenient']
)]
string $style = 'balanced'
): array {
$valid = ['strict', 'balanced', 'lenient'];
if (!in_array($style, $valid, true)) {throw new PromptGetException("invalid '{$style}': " . implode('|', $valid));}
return [['role' => 'user', 'content' => ['type' => 'text', 'text' => "Review with {$style} style"]]];
}
```

### 5. Schema Attributes

```php
#[Schema(
type: 'TYPE',                // required: string|number|integer|boolean|array|object|null
description: 'Concise parameter description. Valid values/format. Example: "value"',
definition: [...],           // optional: complete JSON schema (highest priority)

// string constraints
minLength: 1,
maxLength: 100,
pattern: '/regex/',
format: 'email',             // email|uri|date-time

// number constraints
minimum: 0,
maximum: 100,
exclusiveMinimum: 0,
exclusiveMaximum: 100,

// array constraints
minItems: 1,
maxItems: 10,
uniqueItems: true,

// object constraints
properties: [...],           // property schemas
required: ['field1'],
patternProperties: [...],    // regex-based properties

// enum constraint (any type)
enum: ['opt1', 'opt2']
)]
```

**Schema generation priority (highest to lowest):**

1. `#[Schema(definition: [...])]` - complete JSON schema
2. Parameter-level `#[Schema(...)]` attributes
3. Method-level `#[Schema(...)]` attributes
4. PHP type hints + docblocks

**Examples:**

```php
#[Schema(
type: 'string',
format: 'email',
description: 'User email address. Example: "user@example.com"'
)]
string $email

#[Schema(
type: 'integer',
minimum: 1,
maximum: 100,
description: 'Page number. Range: 1-100, Default: 1'
)]
int $page

#[Schema(
type: 'string',
enum: ['asc', 'desc'],
description: 'Sort order. Valid: asc (ascending), desc (descending)'
)]
string $order

#[Schema(
type: 'array',
minItems: 1,
maxItems: 10,
description: 'Array of tags. Range: 1-10 items. Example: ["tag1", "tag2", "tag3"]'
)]
array $tags

#[Schema(
type: 'string',
minLength: 5,
maxLength: 50,
description: 'Username (5-50 chars, alphanumeric and underscore). Example: "john_doe", "user123"'
)]
string $username
```

### 6. Completion Provider (auto-completion)

**Types:**

```php
// 1. Value lists (static strings)
#[CompletionProvider(['opt1', 'opt2', 'opt3'])]
string $param

// 2. Enum classes (backed or unit enums)
#[CompletionProvider(MyEnum::class)]
string $param

// 3. Custom classes (implementing ProviderInterface)
#[CompletionProvider(CustomProvider::class)]
string $param
```

**Example:**

```php
#[McpTool(
name: 'search',
description: 'Searches items with configurable sorting. Returns ordered results.',
annotations: new ToolAnnotations(
    title: 'search'
)
)]
public function search(
#[Schema(
    type: 'string',
    description: 'Sort order. Valid: asc, desc, relevance (default). Example: "relevance"'
)]
#[CompletionProvider(['asc', 'desc', 'relevance'])]
string $sort = 'relevance'
): array {
return ['results' => []];
}
```

### 7. Error Handling

**Exceptions:**

```php
use Mcp\Exception\ToolCallException;       // tools
use Mcp\Exception\ResourceReadException;   // resources
use Mcp\Exception\PromptGetException;      // prompts
```

**Message format:** `type error: details` (lowercase, concise)

**Patterns:**

```php
// empty
if (empty($val)) {throw new ToolCallException('param empty');}

// length
if (strlen($val) > 100) {throw new ToolCallException('param too long: max 100');}

// format
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {throw new ToolCallException("invalid email: {$email}");}

// enum
$valid = ['a', 'b', 'c'];
if (!in_array($val, $valid, true)) {throw new ToolCallException("invalid '{$val}': " . implode('|', $valid));}

// exists
if (!file_exists($path)) {throw new ToolCallException("not found: {$path}");}

// pattern
if (!preg_match('/pattern/', $val)) {throw new ToolCallException('invalid format: must match pattern');}
```

**Validation order:**

1. empty/null
2. length/range
3. format/pattern
4. enum/whitelist
5. existence
6. business logic

**Generic exceptions (internal errors only):**

```php
try {
$db->connect();
} catch (\PDOException $e) {
error_log("Internal: " . $e->getMessage());
throw new \RuntimeException('db failed');  // no details to client
}
```

### 8. Manual Registration (alternative to attributes)

```php
Server::builder()
->addTool(callable: $callable, name: 'tool_name', description: 'desc')
->addResource(callable: $callable, uri: 'scheme://path', name: 'name', description: 'desc')
->addResourceTemplate(callable: $callable, uriTemplate: 'scheme://{var}', name: 'name', description: 'desc')
->addPrompt(callable: $callable, name: 'prompt_name', description: 'desc')
->build();
```

**Callable formats:** closures, `[ClassName::class, 'method']`, `[$object, 'method']`, `InvokableClass::class`

**Rule:** Manual registrations override discovered elements with same identifier

### 9. Server Builder Methods

```php
Server::builder()
->setServerInfo(name: 'Name', version: '1.0', description: 'desc', icons: [...], website: 'url')
->setPaginationLimit(50)                                    // max items per page (default: 50)
->setInstructions('AI guidance text')                       // usage instructions for AI models
->setDiscovery(basePath: __DIR__, scanDirs: ['src'], excludeDirs: ['vendor'], cache: $psr16)
->setSession(store: $sessionStore, ttl: 3600)              // or just ttl for InMemorySessionStore
->setLogger($psr3Logger)                                    // PSR-3 logger
->setContainer($psr11Container)                             // PSR-11 DI container
->setEventDispatcher($psr14Dispatcher)                      // PSR-14 event dispatcher
->addRequestHandler('method_name', callable)                // custom JSON-RPC handler
->addNotificationHandler('notification_name', callable)     // custom notification handler
->build()
->run($transport);
```

### 10. Session Stores

```php
// 1. InMemorySessionStore (default, volatile)
new InMemorySessionStore(ttl: 3600, prefix: 'session_')

// 2. FileSessionStore (persistent)
new FileSessionStore(path: '/path/to/sessions')

// 3. Psr16StoreSession (Redis, Memcached, etc.)
new Psr16StoreSession(cache: $psr16Cache, ttl: 3600, prefix: 'mcp_')

// Custom: implement SessionStoreInterface
interface SessionStoreInterface {
public function exists(string $id): bool;
public function read(string $id): ?array;
public function write(string $id, array $data): void;
public function destroy(string $id): void;
public function gc(int $maxlifetime): void;
}
```

### 11. Complete Example

```php
<?php
declare(strict_types=1);
namespace App\Http\Controllers;

use Mcp\Capability\Attribute\{McpTool, McpResource, McpResourceTemplate, McpPrompt, Schema};
use Mcp\Exception\{ToolCallException, ResourceReadException, PromptGetException};
use Mcp\Schema\ToolAnnotations;

class Example {
#[McpTool(
    name: 'process',
    description: 'Processes data in specified format. Returns processed result.',
    annotations: new ToolAnnotations(
        title: 'process'
    )
)]
public function process(
    #[Schema(
        type: 'string',
        minLength: 1,
        maxLength: 1000,
        description: 'Input data (max 1000 chars). Example: "sample data to process"'
    )]
    string $data,
    #[Schema(
        type: 'string',
        enum: ['json', 'xml'],
        description: 'Output format. Valid: json (default), xml'
    )]
    string $format = 'json'
): array {
    if (empty($data)) {throw new ToolCallException('data empty');}
    $valid = ['json', 'xml'];
    if (!in_array($format, $valid, true)) {throw new ToolCallException("invalid format '{$format}': " . implode('|', $valid));}
    return ['result' => $this->processData($data, $format)];
}

#[McpResource(
    uri: 'config://app/meta',
    name: 'Application Metadata',
    description: 'Returns application metadata (version, build info).',
    mimeType: 'application/json'
)]
public function getMeta(): array {
    return ['version' => '1.0.0'];
}

#[McpResourceTemplate(
    uriTemplate: 'data://item/{id}',
    name: 'Item by ID',
    description: 'Retrieves item data by ID from data store. Throws exception if not found.',
    mimeType: 'application/json'
)]
public function getItem(
    #[Schema(
        type: 'string',
        pattern: '/^[a-z0-9]+$/',
        description: 'Item ID (alphanumeric lowercase). Example: "item123", "abc456"'
    )]
    string $id
): array {
    if (empty($id)) {throw new ResourceReadException('id empty');}
    if (!preg_match('/^[a-z0-9]+$/', $id)) {throw new ResourceReadException('id must be alphanumeric lowercase');}
    if (!$item = $this->find($id)) {throw new ResourceReadException("not found: {$id}");}
    return $item;
}

#[McpPrompt(
    name: 'analyze',
    description: 'Generates analysis prompt with configurable depth level.'
)]
public function analyze(
    #[Schema(
        type: 'string',
        enum: ['quick', 'deep'],
        description: 'Analysis depth. Valid: quick (default), deep. Example: "quick"'
    )]
    string $depth = 'quick'
): array {
    $valid = ['quick', 'deep'];
    if (!in_array($depth, $valid, true)) {throw new PromptGetException("invalid '{$depth}': " . implode('|', $valid));}
    return [['role' => 'user', 'content' => ['type' => 'text', 'text' => "Analyze with {$depth} depth"]]];
}

private function processData(string $data, string $format): mixed { return null; }
private function find(string $id): ?array { return null; }
}
```

## Writing Effective Tool and Parameter Descriptions

### Tool Descriptions

**Purpose:** Guide tool selection. Include WHEN TO USE and WHEN NOT TO USE.

**Template:**

```
Purpose (1 line).

USE: scenario1, scenario2
DO NOT USE: scenario (use X instead)
KEY: critical behavior or constraint
```

**Patterns:**

```php
// Simple tool
'List orders with filtering. FILTERING: orderIds (max 50), limit (default 50, max 200)'

// Tool with alternatives
'Search logs by ID. USE: known trace_id/user_id. DO NOT USE: exploration (use aggregate instead)'

// Tool in workflow
'Drill into aggregate buckets. PREREQUISITE: Run aggregate first. AUTO: handles @ syntax'

// Decision guidance
'Get product media. DEFAULT: main image only. ALL IMAGES: views=null. WITH VIDEO: types=null'
```

**Remove from tools:** auth details, verbose use cases, response structure (unless critical for next action)

### Parameter Descriptions

**Formula:** `Purpose. Valid values/format. Example.`

**Patterns by type:**

```php
// Enum
'Sort order. Valid: asc|desc|-timestamp. Example: "-timestamp"'

// Format
'Time range. Format: number+unit (h/d/w/m/y). Example: "24h"'

// Range
'Page size. Range: 1-100, Default: 50'

// Required ID
'REQUIRED. Order ID. Format: XX-XXXXX-XXXXX. Example: "12-34567-89012"'

// Optional ID
'Product ID to narrow search. Example: "SM7B"'

// Boolean
'Include component details. Default: false'

// Array
'Field groups. Valid: TAX_BREAKDOWN. Example: ["TAX_BREAKDOWN"]'

// Complex filter
'Filter. Format: field:[start..end] or field:{VAL|VAL}. Example: ["creationdate:[2024-01-01T00:00:00Z..]"]'
```

**Remove from params:** use cases, auth, response details, verbose enum explanations

**Keep:** valid values, format, example, default, constraints

## Error Message Patterns

| Condition | Format                        | Example                       |
|-----------|-------------------------------|-------------------------------|
| Empty     | `param empty`                 | `email empty`                 |
| Too long  | `param too long: max N`       | `name too long: max 100`      |
| Format    | `invalid TYPE: VALUE`         | `invalid email: test@`        |
| Enum      | `invalid 'VALUE': OPT1\|OPT2` | `invalid 'foo': json\|xml`    |
| Not found | `TYPE not found: ID`          | `file not found: /path`       |
| Must be   | `PARAM must be REQUIREMENT`   | `userId must be alphanumeric` |

## Technical Details

- **Controller path:** `/app/controllers` (mount target)
- **Namespace:** optional (`Controllers` or none)
- **Auto-load:** all `.php` files in controller path
- **Transport:** StreamableHttpTransport (HTTP)
- **Session:** FileSessionStore
- **Server:** FrankenPHP (port 80)
- **PHP:** 8.4+

## Docker Behavior

On startup:

1. Create controller directory if missing
2. Load all `.php` files from controller path
3. Create session directory if missing
4. Start FrankenPHP on port 80

Mount requirements:

- `-v <local-path>:/app/controllers` - controllers (required)
- `-v <volume>:/app/storage/mcp-sessions` - sessions (optional, for persistence)
