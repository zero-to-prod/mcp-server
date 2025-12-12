<?php

declare(strict_types=1);

require __DIR__.'/../vendor/autoload.php';

const base_dir = __DIR__.'/..';
const mcp_sessions_dir = __DIR__.'/../storage/mcp-sessions';

use Mcp\Server;
use Mcp\Server\Session\FileSessionStore;
use Mcp\Server\Transport\StreamableHttpTransport;
use Nyholm\Psr7\Factory\Psr17Factory;
use Nyholm\Psr7Server\ServerRequestCreator;
use Psr\Log\AbstractLogger;

$logger = new class() extends AbstractLogger {
    public function __construct()
    {
    }

    public function log($level, string|Stringable $message, array $context = []): void
    {
        if(($_ENV['APP_DEBUG'] ?? 'false') !== 'true') {
            return;
        }
        /** @noinspection ForgottenDebugOutputInspection */
        error_log(
            sprintf(
                "[%s] [%s] %s%s",
                date('Y-m-d H:i:s'),
                $level,
                $message,
                !empty($context) ? ' '.json_encode($context) : ''
            )
        );
    }
};

if (!is_dir(mcp_sessions_dir) && !mkdir(mcp_sessions_dir, 0755, true) && !is_dir(mcp_sessions_dir)) {
    throw new RuntimeException(sprintf('Directory "%s" was not created', mcp_sessions_dir));
}

$psr17Factory = new Psr17Factory();

$response = Server::builder()
    ->setServerInfo($_ENV['MCP_SERVER_NAME'] ?? 'MCP Server', $_ENV['APP_VERSION'] ?? '0.0.0')
    ->setDiscovery(base_dir, ['app/Http/Controllers'])
    ->setSession(new FileSessionStore(mcp_sessions_dir))
    ->setLogger($logger)
    ->build()
    ->run(
        new StreamableHttpTransport(
            new ServerRequestCreator($psr17Factory, $psr17Factory, $psr17Factory, $psr17Factory)->fromGlobals(),
            logger: $logger
        )
    );

http_response_code($response->getStatusCode());

foreach ($response->getHeaders() as $name => $values) {
    foreach ($values as $value) {
        header(sprintf('%s: %s', $name, $value), false);
    }
}

echo $response->getBody();
