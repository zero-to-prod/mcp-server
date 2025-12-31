<?php
declare(strict_types=1);

use Mcp\Capability\Attribute\{McpTool, Schema};
use Mcp\Exception\ToolCallException;
use Mcp\Schema\ToolAnnotations;
use Laudis\Neo4j\ClientBuilder;

/**
 * @link https://github.com/zero-to-prod/mcp-server
 */
final class Memgraph
{
    private static $client = null;

    private function client()
    {
        if (self::$client === null) {
            $host = getenv('MEMGRAPH_HOST') ?: 'localhost';
            $port = (int)(getenv('MEMGRAPH_PORT') ?: 7687);

            $uri = "bolt://{$host}:{$port}";

            try {
                self::$client = ClientBuilder::create()
                    ->withDriver('bolt', $uri)
                    ->withDefaultDriver('bolt')
                    ->build();

                // Test connection
                self::$client->run('RETURN 1 as test');
            } catch (Exception $e) {
                throw new ToolCallException("Memgraph connection failed: {$uri} - {$e->getMessage()}");
            }
        }

        return self::$client;
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'memgraph_query_run',
        description: 'Execute Cypher query. USE: write operations, mutations. RETURNS: query results. Maps to: Cypher query execution',
        annotations: new ToolAnnotations(
            title: 'memgraph_query_run',
            readOnlyHint: false
        )
    )]
    public function run(
        #[Schema(type: 'string', description: 'Cypher query. Example: "CREATE (n:Node {name: $name}) RETURN n"')]
        string $query,

        #[Schema(type: 'object', description: 'Query parameters as JSON object. Example: {"name": "test", "value": 123}')]
        array $parameters = []
    ): array {
        try {
            $result = $this->client()->run($query, $parameters);
            $records = [];

            foreach ($result as $record) {
                $records[] = $record->toArray();
            }

            return [
                'query' => $query,
                'count' => count($records),
                'records' => $records
            ];
        } catch (Exception $e) {
            throw new ToolCallException("Memgraph query failed: {$e->getMessage()}");
        }
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'memgraph_query_read',
        description: 'Execute read-only Cypher query. USE: search, retrieval, analysis. RETURNS: query results. Maps to: Cypher query execution',
        annotations: new ToolAnnotations(
            title: 'memgraph_query_read',
            readOnlyHint: true
        )
    )]
    public function read(
        #[Schema(type: 'string', description: 'Cypher query. Example: "MATCH (n:Node) RETURN n LIMIT 10"')]
        string $query,

        #[Schema(type: 'object', description: 'Query parameters as JSON object. Example: {"name": "test"}')]
        array $parameters = []
    ): array {
        return $this->run($query, $parameters);
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'memgraph_node_create',
        description: 'Create graph node. USE: storing entities. RETURNS: created node. Maps to: CREATE Cypher statement',
        annotations: new ToolAnnotations(
            title: 'memgraph_node_create',
            readOnlyHint: false
        )
    )]
    public function createNode(
        #[Schema(type: 'string', description: 'Node label. Example: "User", "Service", "Error"')]
        string $label,

        #[Schema(type: 'object', description: 'Node properties as JSON object. Example: {"name": "api", "status": "active"}')]
        array $properties
    ): array {
        if (empty($properties)) {
            throw new ToolCallException('properties cannot be empty');
        }

        try {
            $result = $this->run(
                "CREATE (n:{$label}) SET n = \$props RETURN n",
                ['props' => $properties]
            );

            return [
                'label' => $label,
                'properties' => $result['records'][0]['n']['properties'] ?? $properties
            ];
        } catch (Exception $e) {
            throw new ToolCallException("Node creation failed: {$e->getMessage()}");
        }
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'memgraph_relationship_create',
        description: 'Create relationship between nodes. USE: linking entities. RETURNS: created relationship. Maps to: CREATE relationship Cypher',
        annotations: new ToolAnnotations(
            title: 'memgraph_relationship_create',
            readOnlyHint: false
        )
    )]
    public function createRelationship(
        #[Schema(type: 'string', description: 'Source node match condition. Example: "a.name = \'web\'" or "a:Service {name: \'api\'}"')]
        string $from,

        #[Schema(type: 'string', description: 'Target node match condition. Example: "b.name = \'database\'" or "b:Service {name: \'db\'}"')]
        string $to,

        #[Schema(type: 'string', description: 'Relationship type. Example: "DEPENDS_ON", "CAUSED_BY"')]
        string $type,

        #[Schema(type: 'object', description: 'Relationship properties as JSON object. Optional.')]
        array $properties = []
    ): array {
        try {
            if (empty($properties)) {
                $query = "MATCH (a), (b) WHERE {$from} AND {$to} CREATE (a)-[r:{$type}]->(b) RETURN r";
                $params = [];
            } else {
                $query = "MATCH (a), (b) WHERE {$from} AND {$to} CREATE (a)-[r:{$type}]->(b) SET r = \$props RETURN r";
                $params = ['props' => $properties];
            }

            $result = $this->run($query, $params);

            if ($result['count'] === 0) {
                throw new ToolCallException('no matching nodes found for relationship');
            }

            return [
                'type' => $type,
                'properties' => $result['records'][0]['r']['properties'] ?? $properties
            ];
        } catch (Exception $e) {
            throw new ToolCallException("Relationship creation failed: {$e->getMessage()}");
        }
    }
}