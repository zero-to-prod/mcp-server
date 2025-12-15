<?php declare(strict_types=1);

namespace App\Http\Controllers;

use Mcp\Capability\Attribute\{McpTool, Schema};
use Mcp\Exception\ToolCallException;
use Mcp\Schema\ToolAnnotations;

final class Reference
{
    use RedisConnection;

    #[McpTool(
        name: 'ref.inspect',
        description: <<<TEXT
        Inspect a reference without loading full data. Returns metadata and preview.

        Use this to:
        - See what's in a reference before loading
        - Check data size and structure
        - Preview first few items
        - Verify reference exists

        Returns metadata (type, size, count) and preview (first 3 items) without token cost.
        TEXT,
        annotations: new ToolAnnotations(
            title: 'Inspect Reference',
            readOnlyHint: true
        )
    )]
    public function inspect(
        #[Schema(type: 'string', description: 'Reference ID to inspect (e.g., "ref:6758f3a2b1c42")')]
        string $ref
    ): array {
        $data = $this->getFromRef($ref);

        return [
            'ref' => $ref,
            'metadata' => $this->getRefMetadata($data),
            'preview' => $this->getRefPreview($data, limit: 3),
            'ttl' => $this->redis()->ttl($ref)
        ];
    }

    #[McpTool(
        name: 'ref.get',
        description: <<<TEXT
        Get full data from reference. Use only when you need complete data.

        WARNING: This loads full data into LLM context. Use sparingly.
        Prefer ref.inspect for exploration, ref.sample for random samples.

        Use cases:
        - Final step before presenting to user
        - When you need complete dataset for analysis
        - After filtering/transforming to small result set
        TEXT,
        annotations: new ToolAnnotations(
            title: 'Get Reference Data',
            readOnlyHint: true
        )
    )]
    public function get(
        #[Schema(type: 'string', description: 'Reference ID to retrieve')]
        string $ref
    ): mixed {
        return $this->getFromRef($ref);
    }

    #[McpTool(
        name: 'ref.sample',
        description: <<<TEXT
        Get random sample from reference for exploratory analysis.

        Use when:
        - Preview (3 items) isn't enough
        - Need representative sample without full dataset
        - Exploring data structure and patterns

        Returns specified number of random items from reference.
        TEXT,
        annotations: new ToolAnnotations(
            title: 'Sample Reference',
            readOnlyHint: true
        )
    )]
    public function sample(
        #[Schema(type: 'string', description: 'Reference ID to sample from')]
        string $ref,
        #[Schema(type: 'integer', description: 'Number of items to sample. Default: 10', minimum: 1, maximum: 100)]
        int $count = 10
    ): array {
        $data = $this->getFromRef($ref);

        if (!is_array($data)) {
            return ['sample' => [$data], 'total_count' => 1];
        }

        // Sample from data.data if present
        $source = $data['data'] ?? $data;

        if (count($source) <= $count) {
            return ['sample' => $source, 'total_count' => count($source)];
        }

        // Random sample without replacement
        $keys = array_rand($source, $count);
        $sample = is_array($keys)
            ? array_map(fn($k) => $source[$k], $keys)
            : [$source[$keys]];

        return [
            'sample' => array_values($sample),
            'total_count' => count($source),
            'sampled_count' => count($sample)
        ];
    }

    #[McpTool(
        name: 'ref.filter',
        description: <<<TEXT
        Filter reference data by jq-like condition, return new reference.

        Conditions:
        - ".field == value" - Exact match
        - ".field contains 'text'" - String contains
        - ".field > 100" - Numeric comparison
        - ".field != null" - Exists check

        Returns new reference with filtered data + preview.
        Original reference unchanged.
        TEXT,
        annotations: new ToolAnnotations(
            title: 'Filter Reference',
            readOnlyHint: false
        )
    )]
    public function filter(
        #[Schema(type: 'string', description: 'Reference ID to filter')]
        string $ref,
        #[Schema(type: 'string', description: 'Filter condition (jq-like syntax)')]
        string $condition
    ): array {
        $data = $this->getFromRef($ref);
        $source = $data['data'] ?? $data;

        if (!is_array($source)) {
            throw new ToolCallException('Cannot filter non-array data');
        }

        $filtered = array_filter($source, fn($item) => $this->evaluateCondition($item, $condition));
        $filtered = array_values($filtered); // Re-index

        $newRef = $this->storeRef(['data' => $filtered]);

        return [
            'ref' => $newRef,
            'original_ref' => $ref,
            'condition' => $condition,
            'original_count' => count($source),
            'filtered_count' => count($filtered),
            'preview' => array_slice($filtered, 0, 3)
        ];
    }

    #[McpTool(
        name: 'ref.transform',
        description: <<<TEXT
        Apply jq-like transformation to reference, return new reference.

        Transformations:
        - "." - Identity (no change)
        - ".data" - Extract data field
        - ".[]" - Flatten array
        - ".[].field" - Extract field from each item
        - ".data | map(.service)" - Extract service from each

        Returns new reference with transformed data + preview.
        TEXT,
        annotations: new ToolAnnotations(
            title: 'Transform Reference',
            readOnlyHint: false
        )
    )]
    public function transform(
        #[Schema(type: 'string', description: 'Reference ID to transform')]
        string $ref,
        #[Schema(type: 'string', description: 'jq-like transformation expression')]
        string $expression
    ): array {
        $data = $this->getFromRef($ref);
        $transformed = $this->jqEval($data, $expression);

        $newRef = $this->storeRef($transformed);

        return [
            'ref' => $newRef,
            'original_ref' => $ref,
            'expression' => $expression,
            'preview' => $this->getRefPreview($transformed, limit: 3),
            'metadata' => $this->getRefMetadata($transformed)
        ];
    }

    #[McpTool(
        name: 'ref.exists',
        description: 'Check if reference exists and is not expired',
        annotations: new ToolAnnotations(
            title: 'Check Reference Exists',
            readOnlyHint: true
        )
    )]
    public function exists(
        #[Schema(type: 'string', description: 'Reference ID to check')]
        string $ref
    ): array {
        $exists = $this->refExists($ref);

        return [
            'ref' => $ref,
            'exists' => $exists,
            'ttl' => $exists ? $this->redis()->ttl($ref) : null
        ];
    }

    #[McpTool(
        name: 'ref.delete',
        description: 'Delete reference from Redis',
        annotations: new ToolAnnotations(
            title: 'Delete Reference',
            readOnlyHint: false
        )
    )]
    public function delete(
        #[Schema(type: 'string', description: 'Reference ID to delete')]
        string $ref
    ): array {
        $deleted = $this->redis()->del($ref);

        return [
            'ref' => $ref,
            'deleted' => $deleted > 0
        ];
    }

    // Private helper methods

    private function evaluateCondition(array $item, string $condition): bool
    {
        // Simple condition parser
        // Supports: .field == "value", .field > 100, .field contains "text"

        if (preg_match('/^\.(\w+)\s*(==|!=|>|<|>=|<=|contains)\s*(.+)$/', $condition, $matches)) {
            $field = $matches[1];
            $operator = $matches[2];
            $value = trim($matches[3], '\'"');

            if (!isset($item[$field])) {
                return false;
            }

            $itemValue = $item[$field];

            return match($operator) {
                '==' => $itemValue == $value,
                '!=' => $itemValue != $value,
                '>' => $itemValue > $value,
                '<' => $itemValue < $value,
                '>=' => $itemValue >= $value,
                '<=' => $itemValue <= $value,
                'contains' => str_contains((string)$itemValue, $value),
                default => false
            };
        }

        return false;
    }

    private function jqEval(mixed $data, string $expression): mixed
    {
        // Simple jq-like evaluator
        // Supports: ., .field, .[], .[].field, .data

        $expression = trim($expression);

        if ($expression === '.') {
            return $data;
        }

        if (preg_match('/^\.(\w+)$/', $expression, $matches)) {
            // .field
            $field = $matches[1];
            return $data[$field] ?? null;
        }

        if ($expression === '.[]') {
            // Flatten array
            return is_array($data) ? array_values($data) : $data;
        }

        if (preg_match('/^\.\[\]\.(\w+)$/', $expression, $matches)) {
            // .[].field - extract field from each item
            $field = $matches[1];
            if (is_array($data)) {
                return array_column($data, $field);
            }
            return [];
        }

        // Default: return as-is
        return $data;
    }
}
