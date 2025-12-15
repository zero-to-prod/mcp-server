<?php declare(strict_types=1);

namespace App\Http\Controllers;

use Mcp\Exception\ToolCallException;
use Predis\Client;

trait RedisConnection
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
            } catch (\Exception $e) {
                throw new ToolCallException("Redis connection failed: {$host}:{$port} - " . $e->getMessage());
            }
        }

        return self::$redis;
    }

    private function storeRef(mixed $data, int $ttl = 900): string
    {
        $ref = 'ref:' . uniqid(more_entropy: true);
        $encoded = json_encode($data);

        $this->redis()->setex($ref, $ttl, $encoded);

        return $ref;
    }

    private function getFromRef(string $ref): mixed
    {
        $data = $this->redis()->get($ref);

        if ($data === false) {
            throw new ToolCallException("Reference not found or expired: {$ref}");
        }

        return json_decode($data, true);
    }

    private function refExists(string $ref): bool
    {
        return $this->redis()->exists($ref) > 0;
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
}
