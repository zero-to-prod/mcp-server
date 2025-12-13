# MCP Server - Technical Specification

PHP 8.4 MCP (Model Context Protocol) server. Docker image. Mount controllers, expose as MCP tools.

## Setup

### Start server with controllers
```shell
docker run -d --name mcp1 -p 8092:80 \
  -v $(pwd):/app/app/Http/Controllers \
  -v mcp1-sessions:/app/storage/mcp-sessions \
  -e MCP_SERVER_NAME=mcp1 \
  davidsmith3/mcp-server:latest
```

### Add to Claude Desktop
```shell
claude mcp add --transport http mcp1 http://localhost:8092
```

### Multiple instances
Change port and mount path:
```shell
# Instance 1
docker run -d --name mcp-monitoring -p 8081:80 \
  -v ~/mcp-servers/monitoring:/app/app/Http/Controllers \
  -e MCP_SERVER_NAME=monitoring \
  davidsmith3/mcp-server:latest

# Instance 2
docker run -d --name mcp-weather -p 8082:80 \
  -v ~/mcp-servers/weather:/app/app/Http/Controllers \
  -e MCP_SERVER_NAME=weather \
  davidsmith3/mcp-server:latest
```

### Using environment files

Create `.env` from template:
```shell
cp .env.example .env
# edit .env with your values
```

**docker-compose** (reads `.env` automatically):
```shell
docker compose up
```

**docker run** (use `--env-file` flag):
```shell
docker run -d --name mcp1 -p 8092:80 \
  --env-file .env \
  -v $(pwd):/app/app/Http/Controllers \
  -v mcp1-sessions:/app/storage/mcp-sessions \
  davidsmith3/mcp-server:latest
```

## Environment Variables

| Variable         | Default                   | Description                    |
|------------------|---------------------------|--------------------------------|
| MCP_SERVER_NAME  | MCP Server                | server display name            |
| MCP_SESSIONS_DIR | /app/storage/mcp-sessions | session storage path           |
| APP_VERSION      | 0.0.0                     | version string                 |
| APP_DEBUG        | false                     | enable debug logs (true/false) |
| API_KEY          | -                         | api key for controllers        |

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
    description: 'desc',
    annotations: new ToolAnnotations(title: 'T', readOnlyHint: true, category: 'cat'),  // optional
    icons: [...],  // optional
    meta: [...]    // optional
)]
public function method(
    #[Schema(type: 'TYPE', description: 'desc')]
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
#[McpTool(name: 'divide', description: 'divide numbers')]
public function divide(
    #[Schema(type: 'number', description: 'dividend')]
    float $a,
    #[Schema(type: 'number', description: 'divisor')]
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
    uri: 'scheme://path',           // required, RFC 3986
    name: 'Name',                   // optional
    description: 'desc',            // optional
    mimeType: 'mime',               // optional
    size: 1024,                     // optional, bytes
    annotations: [...],             // optional
    icons: [...],                   // optional
    meta: [...]                     // optional
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
#[McpResource(uri: 'config://app/settings', name: 'Settings', description: 'app config', mimeType: 'application/json')]
public function getSettings(): array {
    if (!file_exists($file)) throw new ResourceReadException("not found: {$file}");
    return json_decode(file_get_contents($file), true);
}
```

### 3. Resource Template (dynamic data, variable URI)

**Syntax:**
```php
#[McpResourceTemplate(
    uriTemplate: 'scheme://path/{var}',  // required, RFC 6570
    name: 'Name',                        // optional
    description: 'desc',                 // optional
    mimeType: 'mime',                    // optional
    annotations: [...],                  // optional
    icons: [...],                        // optional
    meta: [...]                          // optional
)]
public function method(
    #[Schema(type: 'string', description: 'var desc')]
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
#[McpResourceTemplate(uriTemplate: 'data://user/{userId}', name: 'User', description: 'user by id', mimeType: 'application/json')]
public function getUser(
    #[Schema(type: 'string', description: 'user id')]
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
    name: 'name',         // required
    description: 'desc',  // optional
    icons: [...],         // optional
    meta: [...]           // optional
)]
public function method(
    #[Schema(type: 'TYPE', description: 'desc')]
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
#[McpPrompt(name: 'review', description: 'code review prompt')]
public function review(
    #[Schema(type: 'string', description: 'style')]
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
    description: 'DESC',         // required
    definition: [...],           // optional: complete JSON schema (highest priority)

    // string
    minLength: 1,
    maxLength: 100,
    pattern: '/regex/',
    format: 'email',             // email|uri|date-time

    // number
    minimum: 0,
    maximum: 100,
    exclusiveMinimum: 0,
    exclusiveMaximum: 100,

    // array
    minItems: 1,
    maxItems: 10,
    uniqueItems: true,

    // object
    properties: [...],           // property schemas
    required: ['field1'],
    patternProperties: [...],    // regex-based properties

    // any
    enum: ['opt1', 'opt2'],
    default: 'value'
)]
```

**Schema generation priority (highest to lowest):**
1. `#[Schema(definition: [...])]` - complete JSON schema
2. Parameter-level `#[Schema(...)]` attributes
3. Method-level `#[Schema(...)]` attributes
4. PHP type hints + docblocks

**Examples:**
```php
#[Schema(type: 'string', format: 'email', description: 'email')]
string $email

#[Schema(type: 'integer', minimum: 1, maximum: 100, description: 'page')]
int $page

#[Schema(type: 'string', enum: ['asc', 'desc'], description: 'order')]
string $order

#[Schema(type: 'array', minItems: 1, maxItems: 10, description: 'tags')]
array $tags

#[Schema(type: 'string', minLength: 5, maxLength: 50, description: 'username')]
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
#[McpTool(name: 'search', description: 'search with filters')]
public function search(
    #[Schema(type: 'string', description: 'sort order')]
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

use Mcp\Capability\Attribute\{McpTool, McpResource, McpResourceTemplate, McpPrompt, Schema, CompletionProvider};
use Mcp\Exception\{ToolCallException, ResourceReadException, PromptGetException};

class Example {
    #[McpTool(name: 'process', description: 'process data')]
    public function process(
        #[Schema(type: 'string', minLength: 1, maxLength: 1000, description: 'data')]
        string $data,
        #[Schema(type: 'string', enum: ['json', 'xml'], description: 'format')]
        string $format = 'json'
    ): array {
        if (empty($data)) throw new ToolCallException('data empty');
        $valid = ['json', 'xml'];
        if (!in_array($format, $valid, true)) throw new ToolCallException("invalid format '{$format}': " . implode('|', $valid));
        return ['result' => $this->processData($data, $format)];
    }

    #[McpResource(uri: 'config://app/meta', name: 'Meta', description: 'metadata', mimeType: 'application/json')]
    public function getMeta(): array {
        return ['version' => '1.0.0'];
    }

    #[McpResourceTemplate(uriTemplate: 'data://item/{id}', name: 'Item', description: 'item by id', mimeType: 'application/json')]
    public function getItem(
        #[Schema(type: 'string', pattern: '/^[a-z0-9]+$/', description: 'id')]
        string $id
    ): array {
        if (empty($id)) throw new ResourceReadException('id empty');
        if (!preg_match('/^[a-z0-9]+$/', $id)) throw new ResourceReadException('id must be alphanumeric lowercase');
        if (!$item = $this->find($id)) throw new ResourceReadException("not found: {$id}");
        return $item;
    }

    #[McpPrompt(name: 'analyze', description: 'analysis prompt')]
    public function analyze(
        #[Schema(type: 'string', enum: ['quick', 'deep'], description: 'depth')]
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
