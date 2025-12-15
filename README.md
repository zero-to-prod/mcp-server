# MCP Server - Technical Specification

PHP 8.4 MCP (Model Context Protocol) server. Docker image. Mount controllers, expose as MCP tools.

## Quick Start

**One-line install** (recommended):
```shell
curl -fsSL https://raw.githubusercontent.com/zero-to-prod/mcp-server/main/install.sh | bash
```

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

**Option B: docker run**
```shell
docker run -d --name mcp1 -p 8093:80 \
  --env-file .env \
  -v $(pwd):/app/app/Http/Controllers \
  -v mcp1-sessions:/app/storage/mcp-sessions \
  davidsmith3/mcp-server:latest
```

### 4. Connect to Claude Desktop

```shell
claude mcp add --transport http mcp1 http://localhost:8093
```

## Docker Operations

### Restart after environment variable changes

When adding or modifying environment variables in `.env`:
```shell
# docker-compose
docker compose restart

# docker run
docker restart mcp1
```

Environment variables only load at container startup. Any changes require restart.

### Reconnect after tool changes

When adding, removing, or modifying tools (controller methods with `#[McpTool]`, `#[McpResource]`, etc.), the MCP client must reconnect to discover changes.

**Important:** There is no command line tool to trigger reconnection. The agent must prompt the user to manually reconnect using their MCP client (e.g., `/mcp` command in Claude Code CLI).

The MCP client caches tool definitions. Reconnection forces discovery of changes.

## Plugin Architecture

Each controller file is a self-contained plugin:
- No shared dependencies between files
- Include all required imports in each file
- Each file operates independently
- No cross-file references

**File structure:**
```php
<?php
declare(strict_types=1);

// Include ALL imports needed by THIS file
use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;
use Mcp\Exception\ToolCallException;

class PluginController {
    // All methods and dependencies in one file
}
```

## Redis Reference System

The Redis Reference system enables efficient token usage by storing large datasets in Redis and returning lightweight reference IDs instead of full data. This achieves **90%+ token reduction** while maintaining full observability through inspection tools.

### Why Use References?

**Problem:** Tools returning large responses (50KB logs, 1000 rows) consume massive tokens when passed between tools or presented to LLMs.

**Solution:** Store data in Redis, return reference ID + metadata + preview (~500 bytes). LLM inspects preview, makes decisions, passes refs between tools - only loads full data when needed.

**Benefits:**
- 🚀 **Token reduction** (ref + preview vs full data)
- 🧠 **Natural reasoning** (inspect → decide → act)
- 🛠️ **Error recovery** (see preview, adjust strategy)
- 🔍 **Full observability** (inspect any ref anytime)

### Setup Requirements

#### 1. Environment Configuration

Redis configuration is included in `.env`:
```bash
REDIS_HOST=redis          # Redis container name (Docker) or localhost
REDIS_PORT=6379           # Default Redis port
REDIS_PASSWORD=           # Optional password
```

#### 2. Docker Compose

Redis service is automatically included in `docker-compose.yml`:
```yaml
services:
  mcp:
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
```

Start with: `docker compose up -d`

### Using RedisConnection Trait

Add Redis support to any controller:

```php
<?php
declare(strict_types=1);
namespace App\Http\Controllers;

use Mcp\Capability\Attribute\{McpTool,Schema};

class MyController
{
    use RedisConnection;  // Add this trait

    #[McpTool(
        name: 'my_tool',
        description: 'Tool that returns reference instead of full data'
    )]
    public function myTool(
        #[Schema(type: 'string', description: 'Query parameter')]
        string $query,
        #[Schema(type: 'boolean', description: 'Return reference instead of full data. Default: false')]
        bool $useRef = false
    ): array {
        // Fetch large dataset
        $response = $this->fetchLargeData($query);

        // Return reference if requested
        if ($useRef) {
            $ref = $this->storeRef($response);  // Store in Redis, get ref ID
            return [
                'ref' => $ref,
                'type' => 'my_tool_response',
                'preview' => $this->getRefPreview($response, limit: 3),
                'metadata' => $this->getRefMetadata($response),
                'ttl' => 900  // 15 minutes
            ];
        }

        // Return full data
        return $response;
    }
}
```

**RedisConnection methods:**
- `storeRef(mixed $data, int $ttl = 900): string` - Store data, get reference ID
- `getFromRef(string $ref): mixed` - Retrieve full data from reference
- `getRefMetadata(mixed $data): array` - Get metadata (type, size, count)
- `getRefPreview(mixed $data, int $limit = 3): array` - Get preview (first N items)
- `refExists(string $ref): bool` - Check if reference exists

### Reference Tools

The `Reference.php` controller provides 7 tools for working with references:

#### 1. `ref.inspect` - Preview Without Loading
```php
ref.inspect("ref:6758f3a2b1c42")
// Returns: {ref, metadata: {type, size, count}, preview: [...], ttl: 843}
```
Use when: Need to see what's in a reference before loading full data.

#### 2. `ref.get` - Load Full Data
```php
ref.get("ref:6758f3a2b1c42")
// Returns: Complete dataset
```
Use when: Need complete data for final analysis or presentation.

#### 3. `ref.sample` - Random Sample
```php
ref.sample("ref:6758f3a2b1c42", count: 20)
// Returns: {sample: [...], total_count: 234, sampled_count: 20}
```
Use when: Preview isn't enough, need representative sample without full dataset.

#### 4. `ref.filter` - Filter Dataset
```php
ref.filter("ref:6758f3a2b1c42", ".service == 'api'")
// Returns: {ref: "ref:new", original_count: 234, filtered_count: 45, preview: [...]}
```
Use when: Need subset matching condition. Returns new reference with filtered data.

**Filter conditions:**
- `.field == "value"` - Exact match
- `.field != "value"` - Not equal
- `.field > 100` - Numeric comparison (>, <, >=, <=)
- `.field contains "text"` - String contains

#### 5. `ref.transform` - Transform Data
```php
ref.transform("ref:6758f3a2b1c42", ".[].error.message")
// Returns: {ref: "ref:new", preview: [...], metadata: {...}}
```
Use when: Need to extract specific fields. Returns new reference with transformed data.

**Transform expressions:**
- `.` - Identity (no change)
- `.field` - Extract field
- `.[]` - Flatten array
- `.[].field` - Extract field from each item
- `.data` - Extract data field

#### 6. `ref.exists` - Check Existence
```php
ref.exists("ref:6758f3a2b1c42")
// Returns: {ref, exists: true, ttl: 843}
```
Use when: Need to verify reference is still valid before using.

#### 7. `ref.delete` - Remove Reference
```php
ref.delete("ref:6758f3a2b1c42")
// Returns: {ref, deleted: true}
```
Use when: Done with data, want to free memory early (optional - auto-expires after TTL).

### Example Workflow

**Scenario:** Investigate production errors using DataDog logs

```php
// 1. Search logs with reference (90% token reduction)
$result = datadog.logs.search(
    "service:api status:error",
    "now-1h",
    "now",
    useRef: true
);
// Returns: {ref: "ref:abc123", preview: [log1, log2, log3], metadata: {count: 234}}

// 2. Inspect preview to understand structure
$inspect = ref.inspect("ref:abc123");
// Returns: {metadata: {size: 45678, count: 234}, preview: [...], ttl: 900}

// 3. Filter to specific error type
$filtered = ref.filter("ref:abc123", ".error.message contains 'timeout'");
// Returns: {ref: "ref:def456", filtered_count: 45, preview: [...]}

// 4. Get sample for analysis
$sample = ref.sample("ref:def456", count: 10);
// Returns: {sample: [10 random logs], total_count: 45}

// 5. Only load full data when needed
$full = ref.get("ref:def456");
// Returns: All 45 timeout errors
```

**Token usage comparison:**
- Without refs: 234 logs × ~200 bytes each = 46KB per tool call
- With refs: ref + preview = ~500 bytes per tool call
- **Savings: 99% token reduction** until final `ref.get`

### Reference ID Format

References use format: `ref:{uniqid}`

Examples:
- `ref:6758f3a2b1c42`
- `ref:6758f3a2b1c42.5d3e9f`

**Properties:**
- Unique across processes
- Time-based (sortable)
- Short (13-23 chars)
- No collisions in practice

### TTL (Time To Live)

**Default:** 900 seconds (15 minutes)

**Rationale:**
- Long enough for multi-step workflows
- Short enough to prevent memory bloat
- Automatically cleaned up by Redis

**Behavior:**
- References expire after TTL
- Expired refs return `ToolCallException: Reference not found or expired`
- Check with `ref.exists` before using old refs

### Controllers with Reference Support

These controllers support `useRef` parameter:

- **DataDog.php** - `datadog.logs.aggregate`, `datadog.logs.search`, `datadog.logs.compare_windows`
- Future controllers can add support by using `RedisConnection` trait

### Best Practices

1. **Use refs by default** for tools returning large datasets (>10KB)
2. **Inspect before loading** - always check preview/metadata first
3. **Filter early** - reduce dataset size before loading full data
4. **Pass refs between tools** - avoid loading intermediate results
5. **Load only when needed** - use `ref.get` as final step before presentation
6. **Check TTL** - verify ref exists if using after several minutes

### Troubleshooting

**Redis connection failed:**
```bash
# Check Redis is running
docker ps | grep redis

# Check Redis logs
docker logs mcp-redis

# Verify environment variables
docker exec mcp-server env | grep REDIS
```

**Reference not found:**
- Reference may have expired (TTL: 900 seconds)
- Use `ref.exists` to check validity
- Refetch data if needed

**Predis not installed:**
```bash
# Rebuild container to install predis
docker compose down
docker compose up -d --build
```

## Testing Tools

After creating or modifying tools, verify functionality:

### 1. Reconnect MCP client

**Manual reconnection required.** There is no command line tool to reconnect. The agent must prompt the user to manually reconnect using their MCP client.

For Claude Code CLI users: Use the `/mcp` command to reconnect.

### 2. List available tools
```shell
claude mcp inspect mcp1
```

Verify new tool appears in output with correct name and description.

### 3. Test tool execution
```shell
claude mcp call mcp1 tool_name '{"param": "value"}'
```

**Validation checklist:**
- Tool executes without errors
- Return value matches expected format
- Error cases throw appropriate exceptions
- Parameter validation works correctly

### 4. Common test patterns

**Test valid input:**
```shell
claude mcp call mcp1 divide '{"a": 10, "b": 2}'
# Expected: {"result": 5}
```

**Test validation:**
```shell
claude mcp call mcp1 divide '{"a": 10, "b": 0}'
# Expected: ToolCallException: "cannot divide by zero"
```

**Test missing parameters:**
```shell
claude mcp call mcp1 divide '{"a": 10}'
# Expected: Parameter validation error
```

### 5. Debug failures

**Check container logs:**
```shell
docker logs mcp1
```

**Check syntax errors:**
```shell
docker exec mcp1 php -l /app/app/Http/Controllers/YourController.php
```

**Verify environment:**
```shell
docker exec mcp1 env | grep MCP
```

## Advanced Usage

### Multiple instances

Each instance needs unique port and directory:
```shell
# Instance 1
mkdir -p ~/mcp-servers/monitoring && cd ~/mcp-servers/monitoring
docker run --rm -v $(pwd):/init davidsmith3/mcp-server:latest init
cp .env.example .env
# Edit .env: MCP_SERVER_NAME=monitoring, PORT=8081
docker compose up -d

# Instance 2
mkdir -p ~/mcp-servers/weather && cd ~/mcp-servers/weather
docker run --rm -v $(pwd):/init davidsmith3/mcp-server:latest init
cp .env.example .env
# Edit .env: MCP_SERVER_NAME=weather, PORT=8082
docker compose up -d
```

### Manual configuration (without .env)

```shell
docker run -d --name mcp1 -p 8093:80 \
  -v $(pwd):/app/app/Http/Controllers \
  -v mcp1-sessions:/app/storage/mcp-sessions \
  -e MCP_SERVER_NAME=mcp1 \
  -e APP_DEBUG=false \
  davidsmith3/mcp-server:latest
```

## Environment Variables

| Variable         | Default                   | Description                          |
|------------------|---------------------------|--------------------------------------|
| MCP_SERVER_NAME  | MCP Server                | server display name                  |
| MCP_SESSIONS_DIR | /app/storage/mcp-sessions | session storage path                 |
| APP_VERSION      | 0.0.0                     | version string                       |
| APP_DEBUG        | false                     | enable debug logs (true/false)       |
| API_KEY          | -                         | api key for controllers              |
| REDIS_HOST       | redis                     | Redis host (container name or IP)    |
| REDIS_PORT       | 6379                      | Redis port                           |
| REDIS_PASSWORD   | -                         | Redis password (optional)            |

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
    description: <<<TEXT
        Multi-line description using heredoc syntax.
        Explain what the tool does, its purpose, and any important behavior.
        Use clear, detailed explanations for LLM understanding.
        TEXT,
    annotations: new ToolAnnotations(title: 'T', readOnlyHint: true)  // optional
)]
public function method(
    #[Schema(
        type: 'TYPE',
        description: <<<TEXT
            Detailed parameter description using heredoc.
            Explain valid values, format requirements, constraints.
            Provide examples: "example1", "example2"
            TEXT,
        pattern: '/regex/',      // optional validation
        enum: ['val1', 'val2']   // optional enum constraint
    )]
    TYPE $param
): RETURN_TYPE {
    if (/* error */) throw new ToolCallException('error: details');
    return $result;
}
```

**Return types:** primitives, arrays, or explicit content objects (TextContent, ImageContent, AudioContent, EmbeddedResource)

**Schema types:** `string` `number` `integer` `boolean` `array` `object` `null`

**Example:**
```php
#[McpTool(
    name: 'divide',
    description: <<<TEXT
        Divides two numbers and returns the result.
        Throws exception if divisor is zero.
        Returns floating point result for all division operations.
        TEXT
)]
public function divide(
    #[Schema(
        type: 'number',
        description: <<<TEXT
            The dividend (number to be divided).
            Can be any numeric value including negative numbers and decimals.
            Example: 10.5, -20, 100
            TEXT
    )]
    float $a,
    #[Schema(
        type: 'number',
        description: <<<TEXT
            The divisor (number to divide by).
            Must not be zero - will throw ToolCallException if zero.
            Can be any non-zero numeric value including negative numbers and decimals.
            Example: 2.5, -4, 0.1
            TEXT
    )]
    float $b
): float {
    if ($b === 0.0) throw new ToolCallException('cannot divide by zero');
    return $a / $b;
}
```

### 2. Resource (static data, fixed URI)
**Syntax:**
```php
#[McpResource(
    uri: 'scheme://path',                    // required, RFC 3986
    name: 'Name',                            // optional
    description: <<<TEXT
        Resource description using heredoc.
        Explain what data this resource provides and when to use it.
        TEXT,
    mimeType: 'application/json',            // optional
    size: 1024                               // optional, bytes
)]
public function method(): mixed {
    if (/* error */) throw new ResourceReadException('error: details');
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
    description: <<<TEXT
        Returns application configuration as JSON.
        Contains runtime settings, feature flags, and environment-specific values.
        Throws ResourceReadException if configuration file is missing.
        TEXT,
    mimeType: 'application/json'
)]
public function getSettings(): array {
    $file = '/path/to/settings.json';
    if (!file_exists($file)) throw new ResourceReadException("not found: {$file}");
    return json_decode(file_get_contents($file), true);
}
```

### 3. Resource Template (dynamic data, variable URI)

**Syntax:**
```php
#[McpResourceTemplate(
    uriTemplate: 'scheme://path/{var}',      // required, RFC 6570
    name: 'Name',                            // optional
    description: <<<TEXT
        Resource template description using heredoc.
        Explain what data this provides and how the variable is used.
        TEXT,
    mimeType: 'application/json'             // optional
)]
public function method(
    #[Schema(
        type: 'string',
        description: <<<TEXT
            Variable parameter description.
            Explain format, constraints, and validation rules.
            TEXT,
        pattern: '/^[a-z0-9]+$/'             // optional validation
    )]
    string $var
): mixed {
    if (/* error */) throw new ResourceReadException('error: details');
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
    description: <<<TEXT
        Returns user data by ID from the data store.
        URI template uses {userId} variable which must be alphanumeric.
        Throws ResourceReadException if user is not found.
        TEXT,
    mimeType: 'application/json'
)]
public function getUser(
    #[Schema(
        type: 'string',
        description: <<<TEXT
            User identifier. Must be alphanumeric lowercase string.
            Example: "user123", "abc456"
            Validation: Only [a-z0-9] characters allowed.
            TEXT,
        pattern: '/^[a-z0-9]+$/'
    )]
    string $userId
): array {
    if (!ctype_alnum($userId)) throw new ResourceReadException('userId must be alphanumeric');
    if (!$user = $this->find($userId)) throw new ResourceReadException("not found: {$userId}");
    return $user;
}
```

### 4. Prompt (AI template generation)

**Syntax:**
```php
#[McpPrompt(
    name: 'name',                          // required
    description: <<<TEXT
        Prompt description using heredoc.
        Explain what this prompt template is for and when to use it.
        TEXT
)]
public function method(
    #[Schema(
        type: 'TYPE',
        description: <<<TEXT
            Parameter description for prompt.
            Explain valid values and how they affect the generated prompt.
            TEXT,
        enum: ['opt1', 'opt2']             // optional
    )]
    TYPE $param
): array {
    if (/* error */) throw new PromptGetException('error: details');
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
    description: <<<TEXT
        Generates code review prompt with configurable style.
        Returns structured prompt for AI to review code with specified rigor level.
        Style affects review depth, tone, and focus areas.
        TEXT
)]
public function review(
    #[Schema(
        type: 'string',
        description: <<<TEXT
            Review style that controls rigor and focus.
            Valid styles:
              - "strict": Comprehensive review with high standards, catches minor issues
              - "balanced": Standard review focusing on significant issues (default)
              - "lenient": Light review for quick feedback, major issues only
            Example: "balanced"
            TEXT,
        enum: ['strict', 'balanced', 'lenient']
    )]
    string $style = 'balanced'
): array {
    $valid = ['strict', 'balanced', 'lenient'];
    if (!in_array($style, $valid, true)) throw new PromptGetException("invalid '{$style}': " . implode('|', $valid));
    return [['role' => 'user', 'content' => ['type' => 'text', 'text' => "Review with {$style} style"]]];
}
```

### 5. Schema Attributes

```php
#[Schema(
    type: 'TYPE',                // required: string|number|integer|boolean|array|object|null
    description: <<<TEXT
        Parameter description using heredoc.
        Explain purpose, valid values, format, constraints.
        Provide examples and clarify edge cases.
        TEXT,
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
    description: <<<TEXT
        User email address. Must be valid email format.
        Example: "user@example.com"
        TEXT
)]
string $email

#[Schema(
    type: 'integer',
    minimum: 1,
    maximum: 100,
    description: <<<TEXT
        Page number for pagination. Must be between 1 and 100.
        Default: 1
        TEXT
)]
int $page

#[Schema(
    type: 'string',
    enum: ['asc', 'desc'],
    description: <<<TEXT
        Sort order direction.
        Valid values: "asc" (ascending), "desc" (descending)
        TEXT
)]
string $order

#[Schema(
    type: 'array',
    minItems: 1,
    maxItems: 10,
    description: <<<TEXT
        Array of tags. Must contain 1-10 items.
        Example: ["tag1", "tag2", "tag3"]
        TEXT
)]
array $tags

#[Schema(
    type: 'string',
    minLength: 5,
    maxLength: 50,
    description: <<<TEXT
        Username. Must be 5-50 characters.
        Only alphanumeric and underscore allowed.
        Example: "john_doe", "user123"
        TEXT
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
    description: <<<TEXT
        Searches items with configurable sorting.
        Returns array of search results ordered by specified sort parameter.
        TEXT
)]
public function search(
    #[Schema(
        type: 'string',
        description: <<<TEXT
            Sort order for search results.
            Valid values: "asc" (ascending), "desc" (descending), "relevance" (by relevance score)
            Default: "relevance"
            TEXT
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
if (empty($val)) throw new ToolCallException('param empty');

// length
if (strlen($val) > 100) throw new ToolCallException('param too long: max 100');

// format
if (!filter_var($email, FILTER_VALIDATE_EMAIL)) throw new ToolCallException("invalid email: {$email}");

// enum
$valid = ['a', 'b', 'c'];
if (!in_array($val, $valid, true)) throw new ToolCallException("invalid '{$val}': " . implode('|', $valid));

// exists
if (!file_exists($path)) throw new ToolCallException("not found: {$path}");

// pattern
if (!preg_match('/pattern/', $val)) throw new ToolCallException('invalid format: must match pattern');
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

class Example {
    #[McpTool(
        name: 'process',
        description: <<<TEXT
            Processes data in the specified format.
            Validates input data and format parameter before processing.
            Returns processed result in requested format.
            TEXT
    )]
    public function process(
        #[Schema(
            type: 'string',
            minLength: 1,
            maxLength: 1000,
            description: <<<TEXT
                Input data to process. Must be non-empty string.
                Maximum length: 1000 characters.
                Example: "sample data to process"
                TEXT
        )]
        string $data,
        #[Schema(
            type: 'string',
            enum: ['json', 'xml'],
            description: <<<TEXT
                Output format for processed data.
                Valid formats: "json", "xml"
                Default: "json"
                TEXT
        )]
        string $format = 'json'
    ): array {
        if (empty($data)) throw new ToolCallException('data empty');
        $valid = ['json', 'xml'];
        if (!in_array($format, $valid, true)) throw new ToolCallException("invalid format '{$format}': " . implode('|', $valid));
        return ['result' => $this->processData($data, $format)];
    }

    #[McpResource(
        uri: 'config://app/meta',
        name: 'Application Metadata',
        description: <<<TEXT
            Returns application metadata including version and build information.
            Static resource with fixed URI. Always returns current version.
            TEXT,
        mimeType: 'application/json'
    )]
    public function getMeta(): array {
        return ['version' => '1.0.0'];
    }

    #[McpResourceTemplate(
        uriTemplate: 'data://item/{id}',
        name: 'Item by ID',
        description: <<<TEXT
            Retrieves item data by identifier from data store.
            URI template uses {id} variable for item lookup.
            Throws ResourceReadException if item not found.
            TEXT,
        mimeType: 'application/json'
    )]
    public function getItem(
        #[Schema(
            type: 'string',
            pattern: '/^[a-z0-9]+$/',
            description: <<<TEXT
                Item identifier. Must be alphanumeric lowercase.
                Only [a-z0-9] characters allowed, no spaces or special chars.
                Example: "item123", "abc456"
                TEXT
        )]
        string $id
    ): array {
        if (empty($id)) throw new ResourceReadException('id empty');
        if (!preg_match('/^[a-z0-9]+$/', $id)) throw new ResourceReadException('id must be alphanumeric lowercase');
        if (!$item = $this->find($id)) throw new ResourceReadException("not found: {$id}");
        return $item;
    }

    #[McpPrompt(
        name: 'analyze',
        description: <<<TEXT
            Generates analysis prompt with configurable depth.
            Returns structured prompt for AI analysis with specified thoroughness.
            Depth parameter controls analysis scope and detail level.
            TEXT
    )]
    public function analyze(
        #[Schema(
            type: 'string',
            enum: ['quick', 'deep'],
            description: <<<TEXT
                Analysis depth level.
                Valid values:
                  - "quick": Fast surface-level analysis (default)
                  - "deep": Comprehensive in-depth analysis
                Example: "quick"
                TEXT
        )]
        string $depth = 'quick'
    ): array {
        $valid = ['quick', 'deep'];
        if (!in_array($depth, $valid, true)) throw new PromptGetException("invalid '{$depth}': " . implode('|', $valid));
        return [['role' => 'user', 'content' => ['type' => 'text', 'text' => "Analyze with {$depth} depth"]]];
    }

    private function processData(string $data, string $format): mixed { return null; }
    private function find(string $id): ?array { return null; }
}
```

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

- **Controller path:** `/app/app/Http/Controllers` (mount target)
- **Namespace:** optional (`App\Http\Controllers` or none)
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
- `-v <local-path>:/app/app/Http/Controllers` - controllers (required)
- `-v <volume>:/app/storage/mcp-sessions` - sessions (optional, for persistence)
