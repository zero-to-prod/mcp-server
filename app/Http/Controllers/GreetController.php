<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use Mcp\Capability\Attribute\McpTool;
use Mcp\Capability\Attribute\Schema;
use Mcp\Schema\ToolAnnotations;

/**
 * Example greeting controller demonstrating basic MCP tool patterns
 *
 * Note: Namespace is optional. Controllers can be defined with or without a namespace.
 */
class GreetController
{
    #[McpTool(
        name: 'greet',
        description: <<<TEXT
            Returns a personalized greeting message
            TEXT,
        annotations: new ToolAnnotations(
            title: 'Greeting Tool',
            readOnlyHint: true
        )
    )]
    public function greet(
        #[Schema(
            type: 'string',
            description: <<<TEXT
                Name of the person to greet
                TEXT,
        )]
        ?string $name = null,
    ): string {
        return $name
            ? "Hello, {$name}! Welcome to the MCP Server."
            : "Hello! Welcome to the MCP Server.";
    }
}