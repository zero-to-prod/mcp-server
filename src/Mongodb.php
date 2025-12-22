<?php declare(strict_types=1);

namespace App\Http\Controllers;

use Exception;
use Mcp\Capability\Attribute\{McpTool, Schema};
use Mcp\Exception\ToolCallException;
use Mcp\Schema\ToolAnnotations;
use MongoDB\Client;
use MongoDB\Driver\Exception\ConnectionException;
use MongoDB\Driver\Exception\RuntimeException;

/**
 * @link https://github.com/zero-to-prod/mcp-server
 */
final class Mongodb
{
    private static ?Client $client = null;

    private function client(): Client
    {
        if (self::$client === null) {
            $host = getenv('MONGODB_HOST') ?: 'localhost';
            $port = (int)(getenv('MONGODB_PORT') ?: 27017);
            $username = getenv('MONGODB_USERNAME') ?: null;
            $password = getenv('MONGODB_PASSWORD') ?: null;

            try {
                $uri = 'mongodb://';

                if ($username && $password) {
                    $uri .= urlencode($username) . ':' . urlencode($password) . '@';
                }

                $uri .= $host . ':' . $port;

                $options = [
                    'connectTimeoutMS' => 2000,
                    'serverSelectionTimeoutMS' => 2000,
                ];

                self::$client = new Client($uri, $options);

                // Test connection
                self::$client->listDatabases();
            } catch (ConnectionException $e) {
                throw new ToolCallException("MongoDB connection failed: {$host}:{$port} - " . $e->getMessage());
            } catch (Exception $e) {
                throw new ToolCallException("MongoDB client error: " . $e->getMessage());
            }
        }

        return self::$client;
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'mongodb.document.find',
        description: 'Find documents in collection. USE: retrieving, searching, filtering. Maps to: MongoDB find()',
        annotations: new ToolAnnotations(
            title: 'mongodb.document.find',
            readOnlyHint: true
        )
    )]
    public function find(
        #[Schema(type: 'string', description: 'Database name')]
        string $database,

        #[Schema(type: 'string', description: 'Collection name')]
        string $collection,

        #[Schema(type: 'string', description: 'JSON-encoded query filter. Optional "_limit" for result limit. Example: "{\"status\": \"active\", \"_limit\": 10}"')]
        string $query = '{}'
    ): array {
        try {
            $filter = json_decode($query, true, 512, JSON_THROW_ON_ERROR);

            $limit = $filter['_limit'] ?? null;
            unset($filter['_limit']);

            $coll = $this->client()->selectCollection($database, $collection);
            $options = $limit ? ['limit' => (int)$limit] : [];
            $cursor = $coll->find($filter, $options);
            $documents = $cursor->toArray();

            return [
                'database' => $database,
                'collection' => $collection,
                'count' => count($documents),
                'documents' => $documents
            ];
        } catch (\JsonException $e) {
            throw new ToolCallException("Invalid JSON in query: " . $e->getMessage());
        } catch (RuntimeException $e) {
            throw new ToolCallException("MongoDB find failed: " . $e->getMessage());
        } catch (Exception $e) {
            throw new ToolCallException("Find operation error: " . $e->getMessage());
        }
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'mongodb.document.insert',
        description: 'Insert one or more documents into a MongoDB collection. Supports single document or bulk insert operations. Maps to: MongoDB insertOne() or insertMany() operations',
        annotations: new ToolAnnotations(
            title: 'mongodb.document.insert',
            readOnlyHint: false
        )
    )]
    public function insert(
        #[Schema(type: 'string', description: 'Database name')]
        string $database,

        #[Schema(type: 'string', description: 'Collection name')]
        string $collection,

        #[Schema(type: 'string', description: 'JSON-encoded document or array of documents. Format: single "{\"field\": \"value\"}" or multiple "[{...}, {...}]". Example: "[{\"name\": \"John\"}, {\"name\": \"Jane\"}]"')]
        string $document
    ): array {
        try {
            $docs = json_decode($document, true, 512, JSON_THROW_ON_ERROR);

            if (empty($docs)) {
                throw new ToolCallException('Document cannot be empty');
            }

            $coll = $this->client()->selectCollection($database, $collection);

            // Check if bulk insert (array of documents)
            $is_bulk = isset($docs[0]) && is_array($docs[0]);

            if ($is_bulk) {
                $result = $coll->insertMany($docs);
                $inserted_ids = array_values((array)$result->getInsertedIds());

                return [
                    'database' => $database,
                    'collection' => $collection,
                    'inserted_count' => $result->getInsertedCount(),
                    'inserted_ids' => $inserted_ids
                ];
            } else {
                $result = $coll->insertOne($docs);

                return [
                    'database' => $database,
                    'collection' => $collection,
                    'inserted_count' => 1,
                    'inserted_id' => (string)$result->getInsertedId()
                ];
            }
        } catch (\JsonException $e) {
            throw new ToolCallException("Invalid JSON in document: " . $e->getMessage());
        } catch (RuntimeException $e) {
            throw new ToolCallException("MongoDB insert failed: " . $e->getMessage());
        } catch (Exception $e) {
            throw new ToolCallException("Insert operation error: " . $e->getMessage());
        }
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'mongodb.document.update',
        description: 'Update documents in a MongoDB collection. Uses MongoDB update operators to modify documents. Maps to: MongoDB updateOne() or updateMany() operations',
        annotations: new ToolAnnotations(
            title: 'mongodb.document.update',
            readOnlyHint: false
        )
    )]
    public function update(
        #[Schema(type: 'string', description: 'Database name')]
        string $database,

        #[Schema(type: 'string', description: 'Collection name')]
        string $collection,

        #[Schema(type: 'string', description: 'JSON-encoded filter to match documents. Optional "_multiple": true for updateMany. Example: "{\"_id\": \"...\", \"_multiple\": true}"')]
        string $filter,

        #[Schema(type: 'string', description: 'JSON-encoded update operations using $ operators. Example: "{\"\$set\": {\"status\": \"active\"}}"')]
        string $update
    ): array {
        try {
            $filter_doc = json_decode($filter, true, 512, JSON_THROW_ON_ERROR);
            $update_doc = json_decode($update, true, 512, JSON_THROW_ON_ERROR);

            $update_multiple = $filter_doc['_multiple'] ?? false;
            unset($filter_doc['_multiple']);

            $coll = $this->client()->selectCollection($database, $collection);

            if ($update_multiple) {
                $result = $coll->updateMany($filter_doc, $update_doc);
            } else {
                $result = $coll->updateOne($filter_doc, $update_doc);
            }

            return [
                'database' => $database,
                'collection' => $collection,
                'matched_count' => $result->getMatchedCount(),
                'modified_count' => $result->getModifiedCount(),
            ];
        } catch (\JsonException $e) {
            throw new ToolCallException("Invalid JSON: " . $e->getMessage());
        } catch (RuntimeException $e) {
            throw new ToolCallException("MongoDB update failed: " . $e->getMessage());
        } catch (Exception $e) {
            throw new ToolCallException("Update operation error: " . $e->getMessage());
        }
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'mongodb.document.delete',
        description: 'Delete documents from a MongoDB collection. Removes one or multiple documents matching a filter. WARNING: Delete operations are permanent. Maps to: MongoDB deleteOne() or deleteMany() operations',
        annotations: new ToolAnnotations(
            title: 'mongodb.document.delete',
            readOnlyHint: false
        )
    )]
    public function delete(
        #[Schema(type: 'string', description: 'Database name')]
        string $database,

        #[Schema(type: 'string', description: 'Collection name')]
        string $collection,

        #[Schema(type: 'string', description: 'JSON-encoded filter to match documents. Optional "_multiple": true for deleteMany. Example: "{\"status\": \"archived\", \"_multiple\": true}"')]
        string $filter
    ): array {
        try {
            $filter_doc = json_decode($filter, true, 512, JSON_THROW_ON_ERROR);

            $delete_multiple = $filter_doc['_multiple'] ?? false;
            unset($filter_doc['_multiple']);

            $coll = $this->client()->selectCollection($database, $collection);

            if ($delete_multiple) {
                $result = $coll->deleteMany($filter_doc);
            } else {
                $result = $coll->deleteOne($filter_doc);
            }

            return [
                'database' => $database,
                'collection' => $collection,
                'deleted_count' => $result->getDeletedCount()
            ];
        } catch (\JsonException $e) {
            throw new ToolCallException("Invalid JSON in filter: " . $e->getMessage());
        } catch (RuntimeException $e) {
            throw new ToolCallException("MongoDB delete failed: " . $e->getMessage());
        } catch (Exception $e) {
            throw new ToolCallException("Delete operation error: " . $e->getMessage());
        }
    }

    /**
     * @link https://github.com/zero-to-prod/mcp-server
     */
    #[McpTool(
        name: 'mongodb.data.aggregate',
        description: 'Run aggregation pipeline on a MongoDB collection. Execute data transformations using MongoDB\'s aggregation framework. Pipeline stages: $match: Filter documents, $group: Group and aggregate, $sort: Sort results, $limit: Limit results, $project: Shape output. USE: complex queries, analytics, computing aggregates. Maps to: MongoDB aggregate() operation',
        annotations: new ToolAnnotations(
            title: 'mongodb.data.aggregate',
            readOnlyHint: true
        )
    )]
    public function aggregate(
        #[Schema(type: 'string', description: 'Database name')]
        string $database,

        #[Schema(type: 'string', description: 'Collection name')]
        string $collection,

        #[Schema(type: 'string', description: 'JSON-encoded aggregation pipeline array of stage objects. Example: "[{\"\$match\": {\"status\": \"active\"}}, {\"\$group\": {\"_id\": \"\$userId\"}}]"')]
        string $pipeline
    ): array {
        try {
            $stages = json_decode($pipeline, true, 512, JSON_THROW_ON_ERROR);

            if (!is_array($stages)) {
                throw new ToolCallException('Pipeline must be an array of stages');
            }

            if (empty($stages)) {
                throw new ToolCallException('Pipeline cannot be empty');
            }

            $coll = $this->client()->selectCollection($database, $collection);
            $cursor = $coll->aggregate($stages);
            $results = $cursor->toArray();

            return [
                'database' => $database,
                'collection' => $collection,
                'result_count' => count($results),
                'results' => $results
            ];
        } catch (\JsonException $e) {
            throw new ToolCallException("Invalid JSON in pipeline: " . $e->getMessage());
        } catch (RuntimeException $e) {
            throw new ToolCallException("MongoDB aggregation failed: " . $e->getMessage());
        } catch (Exception $e) {
            throw new ToolCallException("Aggregation operation error: " . $e->getMessage());
        }
    }
}
