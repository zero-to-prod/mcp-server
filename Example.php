<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use Mcp\Capability\Attribute\{McpTool, McpResource, McpResourceTemplate, McpPrompt, Schema, CompletionProvider};
use Mcp\Exception\{ToolCallException, ResourceReadException, PromptGetException};
use Mcp\Schema\ToolAnnotations;
use Mcp\Schema\Content\{TextContent, ImageContent};

/**
 * Comprehensive MCP SDK feature demonstration
 * Shows all attributes, validation patterns, error handling, and return types
 */
class Example
{
    // ===================================================================
    // TOOL: Basic with validation and error handling
    // ===================================================================

    #[McpTool(name: 'calculate', description: 'perform arithmetic operations')]
    public function calculate(
        #[Schema(type: 'number', description: 'first operand')]
        float $a,
        #[Schema(type: 'number', description: 'second operand')]
        float $b,
        #[Schema(type: 'string', enum: ['add', 'subtract', 'multiply', 'divide'], description: 'operation')]
        #[CompletionProvider(['add', 'subtract', 'multiply', 'divide'])]  // auto-completion
        string $operation = 'add'
    ): float {
        // enum validation
        $valid = ['add', 'subtract', 'multiply', 'divide'];
        if (!in_array($operation, $valid, true)) {
            throw new ToolCallException("invalid operation '{$operation}': " . implode('|', $valid));
        }

        // business logic validation
        if ($operation === 'divide' && $b === 0.0) {
            throw new ToolCallException('cannot divide by zero');
        }

        return match ($operation) {
            'add' => $a + $b,
            'subtract' => $a - $b,
            'multiply' => $a * $b,
            'divide' => $a / $b,
        };
    }

    // ===================================================================
    // TOOL: Advanced with annotations, schema validation, content types
    // ===================================================================

    #[McpTool(
        name: 'process_data',
        description: 'process and format data with validation',
        annotations: new ToolAnnotations(
            title: 'Data Processor',
            readOnlyHint: false,              // indicates state modification
            category: 'data-processing'
        )
    )]
    public function processData(
        #[Schema(
            type: 'string',
            minLength: 1,
            maxLength: 1000,
            description: 'data to process'
        )]
        string $data,
        #[Schema(
            type: 'string',
            enum: ['json', 'xml', 'csv'],
            default: 'json',
            description: 'output format'
        )]
        #[CompletionProvider(['json', 'xml', 'csv'])]
        string $format = 'json',
        #[Schema(
            type: 'boolean',
            default: false,
            description: 'include metadata'
        )]
        bool $includeMetadata = false
    ): array {
        // validation order: empty → length → format → enum → business logic
        if (empty($data)) throw new ToolCallException('data empty');
        if (strlen($data) > 1000) throw new ToolCallException('data too long: max 1000');

        $valid = ['json', 'xml', 'csv'];
        if (!in_array($format, $valid, true)) {
            throw new ToolCallException("invalid format '{$format}': " . implode('|', $valid));
        }

        // return with TextContent (rich response)
        $result = ['data' => $data, 'format' => $format];
        if ($includeMetadata) {
            $result['metadata'] = ['processed_at' => date('Y-m-d H:i:s'), 'length' => strlen($data)];
        }

        return [new TextContent(json_encode($result, JSON_PRETTY_PRINT))];
    }

    // ===================================================================
    // TOOL: Complex schema with properties, pattern, advanced validation
    // ===================================================================

    #[McpTool(name: 'validate_user', description: 'validate user data structure')]
    public function validateUser(
        #[Schema(
            type: 'string',
            format: 'email',
            maxLength: 254,
            description: 'user email'
        )]
        string $email,
        #[Schema(
            type: 'string',
            minLength: 3,
            maxLength: 50,
            pattern: '/^[a-zA-Z0-9_-]+$/',
            description: 'username (alphanumeric, dash, underscore)'
        )]
        string $username,
        #[Schema(
            type: 'integer',
            minimum: 18,
            maximum: 120,
            description: 'user age'
        )]
        int $age
    ): array {
        // email validation
        if (empty($email)) throw new ToolCallException('email empty');
        if (strlen($email) > 254) throw new ToolCallException('email too long: max 254');
        if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            throw new ToolCallException("invalid email format: {$email}");
        }

        // username validation
        if (empty($username)) throw new ToolCallException('username empty');
        if (strlen($username) < 3) throw new ToolCallException('username too short: min 3');
        if (strlen($username) > 50) throw new ToolCallException('username too long: max 50');
        if (!preg_match('/^[a-zA-Z0-9_-]+$/', $username)) {
            throw new ToolCallException('username must be alphanumeric with dash/underscore');
        }

        // age validation
        if ($age < 18) throw new ToolCallException('age too low: min 18');
        if ($age > 120) throw new ToolCallException('age too high: max 120');

        return ['valid' => true, 'email' => $email, 'username' => $username, 'age' => $age];
    }

    // ===================================================================
    // RESOURCE: Static with all parameters
    // ===================================================================

    #[McpResource(
        uri: 'config://app/settings',
        name: 'Application Settings',
        description: 'app configuration and metadata',
        mimeType: 'application/json'
    )]
    public function getSettings(): array {
        $settings = [
            'version' => '1.0.0',
            'environment' => 'production',
            'features' => ['api', 'webhooks', 'caching'],
        ];

        return $settings;
    }

    // ===================================================================
    // RESOURCE: Static returning TextResourceContents
    // ===================================================================

    #[McpResource(
        uri: 'file://readme',
        name: 'README',
        description: 'application readme',
        mimeType: 'text/markdown'
    )]
    public function getReadme(): array {
        // return as text resource
        return ['text' => '# Application\n\nThis is a sample application demonstrating MCP features.'];
    }

    // ===================================================================
    // RESOURCE TEMPLATE: Dynamic with single variable
    // ===================================================================

    #[McpResourceTemplate(
        uriTemplate: 'data://user/{userId}',
        name: 'User Profile',
        description: 'user profile by id',
        mimeType: 'application/json'
    )]
    public function getUserProfile(
        #[Schema(
            type: 'string',
            pattern: '/^[a-z0-9]+$/',
            description: 'user id (alphanumeric lowercase)'
        )]
        string $userId
    ): array {
        // validation order: empty → format → exists
        if (empty($userId)) throw new ResourceReadException('userId empty');
        if (!preg_match('/^[a-z0-9]+$/', $userId)) {
            throw new ResourceReadException('userId must be alphanumeric lowercase');
        }

        // mock user database
        $users = [
            'user123' => ['id' => 'user123', 'name' => 'Alice', 'email' => 'alice@example.com'],
            'user456' => ['id' => 'user456', 'name' => 'Bob', 'email' => 'bob@example.com'],
        ];

        if (!isset($users[$userId])) {
            throw new ResourceReadException("user not found: {$userId}");
        }

        return $users[$userId];
    }

    // ===================================================================
    // RESOURCE TEMPLATE: Dynamic with multiple variables (parameter order matters!)
    // ===================================================================

    #[McpResourceTemplate(
        uriTemplate: 'data://user/{userId}/posts/{postId}',
        name: 'User Post',
        description: 'specific post by user id and post id',
        mimeType: 'application/json'
    )]
    public function getUserPost(
        #[Schema(type: 'string', description: 'user id')]
        string $userId,
        #[Schema(type: 'string', description: 'post id')]
        string $postId
    ): array {
        // parameter order must match URI template order
        if (empty($userId)) throw new ResourceReadException('userId empty');
        if (empty($postId)) throw new ResourceReadException('postId empty');
        if (!ctype_alnum($userId)) throw new ResourceReadException('userId must be alphanumeric');
        if (!ctype_alnum($postId)) throw new ResourceReadException('postId must be alphanumeric');

        // mock posts
        $post = [
            'userId' => $userId,
            'postId' => $postId,
            'title' => 'Sample Post',
            'content' => 'This is a sample post.',
        ];

        return $post;
    }

    // ===================================================================
    // PROMPT: Basic with enum validation
    // ===================================================================

    #[McpPrompt(
        name: 'code_review',
        description: 'generate code review prompt with style'
    )]
    public function codeReviewPrompt(
        #[Schema(
            type: 'string',
            enum: ['strict', 'balanced', 'lenient'],
            default: 'balanced',
            description: 'review style'
        )]
        #[CompletionProvider(['strict', 'balanced', 'lenient'])]
        string $style = 'balanced'
    ): array {
        $valid = ['strict', 'balanced', 'lenient'];
        if (!in_array($style, $valid, true)) {
            throw new PromptGetException("invalid style '{$style}': " . implode('|', $valid));
        }

        $prompts = [
            'strict' => 'Review with strict standards: security, performance, style, best practices.',
            'balanced' => 'Review with balanced approach: major issues and best practices.',
            'lenient' => 'Review with lenient approach: critical issues only.',
        ];

        // standard return format: array with role + content
        return [
            [
                'role' => 'user',
                'content' => ['type' => 'text', 'text' => $prompts[$style]],
            ],
        ];
    }

    // ===================================================================
    // PROMPT: Advanced with multiple parameters
    // ===================================================================

    #[McpPrompt(
        name: 'translation',
        description: 'generate translation prompt'
    )]
    public function translationPrompt(
        #[Schema(
            type: 'string',
            minLength: 2,
            maxLength: 2,
            description: 'target language code (ISO 639-1)'
        )]
        #[CompletionProvider(['es', 'fr', 'de', 'it', 'pt', 'ja', 'zh', 'ru'])]
        string $languageCode,
        #[Schema(
            type: 'string',
            minLength: 1,
            maxLength: 5000,
            description: 'text to translate'
        )]
        string $text
    ): array {
        // validation
        if (empty($languageCode)) throw new PromptGetException('languageCode empty');
        if (strlen($languageCode) !== 2) {
            throw new PromptGetException('languageCode must be 2 chars (ISO 639-1)');
        }
        if (empty($text)) throw new PromptGetException('text empty');
        if (strlen($text) > 5000) throw new PromptGetException('text too long: max 5000');

        $supported = ['es', 'fr', 'de', 'it', 'pt', 'ja', 'zh', 'ru'];
        if (!in_array($languageCode, $supported, true)) {
            throw new PromptGetException("unsupported lang '{$languageCode}': " . implode('|', $supported));
        }

        return [
            [
                'role' => 'user',
                'content' => [
                    'type' => 'text',
                    'text' => "Translate to {$languageCode}:\n\n{$text}",
                ],
            ],
        ];
    }

    // ===================================================================
    // TOOL: Demonstrating generic exception (hides details from client)
    // ===================================================================

    #[McpTool(
        name: 'internal_operation',
        description: 'demonstrates generic exception handling for internal errors'
    )]
    public function internalOperation(): array {
        try {
            // simulate internal error that shouldn't expose details
            throw new \RuntimeException('Database connection failed: credentials=admin:password123@192.168.1.100');
        } catch (\RuntimeException $e) {
            // log internally but don't expose sensitive details to client
            error_log("Internal error: " . $e->getMessage());

            // generic exception hides message from client
            throw new \RuntimeException('internal operation failed');
        }
    }
}
