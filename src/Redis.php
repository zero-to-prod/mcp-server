<?php declare(strict_types=1);

namespace App\Http\Controllers;

use Exception;
use Mcp\Capability\Attribute\{McpTool, Schema};
use Mcp\Exception\ToolCallException;
use Mcp\Schema\ToolAnnotations;
use Predis\Client;

/**
 * @link https://github.com/zero-to-prod/mcp-server
 */
final class Redis
{
    private static ?Client $redis = null;

    private function redis(): Client
    {
        if (self::$redis === null) {
            $host = getenv('REDIS_HOST') ?: 'localhost';
            $port = (int)(getenv('REDIS_PORT') ?: 6379);
            $password = getenv('REDIS_PASSWORD') ?: null;

            try {
                $config = [
                    'scheme' => 'tcp',
                    'host' => $host,
                    'port' => $port,
                    'timeout' => 2.0
                ];

                if ($password) {
                    $config['password'] = $password;
                }

                self::$redis = new Client($config);
                self::$redis->connect();
            } catch (Exception $e) {
                throw new ToolCallException("Redis connection failed: {$host}:{$port} - " . $e->getMessage());
            }
        }

        return self::$redis;
    }

    private function getFromRefRedis(string $ref): mixed
    {
        $clean_ref = str_replace('redis:', '', $ref);
        $data = $this->redis()->get($clean_ref);

        if ($data === false) {
            throw new ToolCallException("Reference not found or expired: {$ref}");
        }

        return json_decode($data, true);
    }

    private function refExistsRedis(string $ref): bool
    {
        $clean_ref = str_replace('redis:', '', $ref);
        return $this->redis()->exists($clean_ref) > 0;
    }

    private function getRefTTLRedis(string $ref): ?int
    {
        $clean_ref = str_replace('redis:', '', $ref);
        $ttl = $this->redis()->ttl($clean_ref);

        return $ttl > 0 ? $ttl : null;
    }

    private function getRefMetadata(mixed $data): array
    {
        if (!is_array($data)) {
            return [
                'type' => gettype($data),
                'size' => strlen(json_encode($data))
            ];
        }

        $metadata = [
            'type' => 'array',
            'size' => strlen(json_encode($data)),
            'count' => count($data)
        ];

        // Extract meaningful metadata from data structure
        if (isset($data['data']) && is_array($data['data'])) {
            $metadata['data_count'] = count($data['data']);
        }

        return $metadata;
    }

    private function getRefPreview(mixed $data, int $limit = 3): array
    {
        if (!is_array($data)) {
            return [$data];
        }

        // If data has a 'data' key with array, preview that
        if (isset($data['data']) && is_array($data['data'])) {
            return array_slice($data['data'], 0, $limit);
        }

        // Otherwise preview top-level array
        return array_slice($data, 0, $limit);
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'redis.get',
        description: <<<TEXT
        Redis GET command - retrieve full data from key.

        WARNING: This loads full data into LLM context. Use sparingly.
        Prefer redis.inspect for exploration.

        Use this to:
        - Final step before presenting to user
        - When you need complete dataset for analysis
        - After reducing dataset to small result set

        Maps directly to: Redis GET command
        TEXT,
        annotations: new ToolAnnotations(
            title: 'redis.get',
            readOnlyHint: true
        )
    )]
    public function get(
        #[Schema(type: 'string', description: 'Redis key. Example: "redis:ref:6758f3a2b1c42"')]
        string $key
    ): mixed {
        return $this->getFromRefRedis($key);
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'redis.inspect',
        description: <<<TEXT
        Get metadata + preview + TTL for key (composite operation).

        USE: Exploration before full load, check size/structure/expiration, verify key exists
        DO NOT USE: When you need full data (use redis.get instead)

        RETURNS: Metadata (type/size/count), preview (first 3 items), TTL (seconds)

        Maps to: Redis GET + TTL commands
        TEXT,
        annotations: new ToolAnnotations(
            title: 'redis.inspect',
            readOnlyHint: true
        )
    )]
    public function inspect(
        #[Schema(type: 'string', description: 'Redis key. Example: "redis:ref:6758f3a2b1c42"')]
        string $key
    ): array {
        $data = $this->getFromRefRedis($key);

        return [
            'key' => $key,
            'metadata' => $this->getRefMetadata($data),
            'preview' => $this->getRefPreview($data, limit: 3),
            'ttl' => $this->getRefTTLRedis($key)
        ];
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'redis.exists',
        description: <<<TEXT
        Check if key exists and get TTL.

        RETURNS: exists (boolean), ttl (seconds or null if key doesn't exist)

        Maps to: Redis EXISTS + TTL commands
        TEXT,
        annotations: new ToolAnnotations(
            title: 'redis.exists'
        )
    )]
    public function exists(
        #[Schema(type: 'string', description: 'Redis key. Example: "redis:ref:6758f3a2b1c42"')]
        string $key
    ): array {
        $exists = $this->refExistsRedis($key);

        return [
            'key' => $key,
            'exists' => $exists,
            'ttl' => $exists ? $this->getRefTTLRedis($key) : null
        ];
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'redis.command',
        description: <<<TEXT
        Execute raw Redis command and return result.

        Supports any Redis command (GET, SET, KEYS, SCAN, HGET, LRANGE, etc.)

        Examples:
        - "GET mykey" - Get value of key
        - "KEYS ref:*" - Find all keys matching pattern
        - "TTL mykey" - Get time to live
        - "HGETALL myhash" - Get all hash fields
        - "LRANGE mylist 0 10" - Get list range
        - "SCAN 0 MATCH ref:* COUNT 100" - Scan keys with pattern

        WARNING: Destructive commands (DEL, FLUSHDB, etc.) will execute.
        Use with caution.

        Direct pass-through to Redis server.
        TEXT,
        annotations: new ToolAnnotations(
            title: 'redis.command'
        )
    )]
    public function command(
        #[Schema(type: 'string', description: 'Redis command string. Format: "COMMAND arg1 arg2 ...". Example: "GET mykey"')]
        string $command
    ): array {
        if (empty(trim($command))) {
            throw new ToolCallException('command cannot be empty');
        }

        // Parse command into parts
        $parts = preg_split('/\s+/', trim($command));
        $cmd = strtolower(array_shift($parts));
        $args = $parts;

        try {
            // Execute command via Predis client (supports dynamic method calls)
            $result = $this->redis()->$cmd(...$args);

            return [
                'command' => $command,
                'result' => $result
            ];
        } catch (Exception $e) {
            throw new ToolCallException("Redis command failed: {$e->getMessage()}");
        }
    }
}
