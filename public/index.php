<?php

declare(strict_types=1);

require __DIR__.'/../vendor/autoload.php';

const base_dir = __DIR__.'/..';
const mcp_sessions_dir = __DIR__.'/../storage/mcp-sessions';

set_exception_handler(static function (Throwable $exception): void {
    error_log(
        sprintf(
            "[%s] [CRITICAL] Uncaught exception: %s in %s:%d\nStack trace:\n%s",
            date('Y-m-d H:i:s'),
            $exception->getMessage(),
            $exception->getFile(),
            $exception->getLine(),
            $exception->getTraceAsString()
        )
    );

    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'jsonrpc' => '2.0',
        'error' => [
            'code' => -32603,
            'message' => 'Internal server error',
            'data' => ($_ENV['APP_DEBUG'] ?? 'false') === 'true' ? [
                'exception' => get_class($exception),
                'message' => $exception->getMessage(),
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
            ] : null,
        ],
        'id' => null,
    ]);
    exit(1);
});

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
        $is_debug = ($_ENV['APP_DEBUG'] ?? 'false') === 'true';
        $is_error = in_array(strtolower($level), ['error', 'critical', 'alert', 'emergency'], true);

        if (!$is_error && !$is_debug) {
            return;
        }

        /** @noinspection ForgottenDebugOutputInspection */
        error_log(
            sprintf(
                "[%s] [%s] %s%s",
                date('Y-m-d H:i:s'),
                strtoupper($level),
                $message,
                !empty($context) ? ' '.json_encode($context, JSON_UNESCAPED_SLASHES) : ''
            )
        );
    }
};

if (!is_dir(mcp_sessions_dir) && !mkdir(mcp_sessions_dir, 0755, true) && !is_dir(mcp_sessions_dir)) {
    throw new RuntimeException(sprintf('Directory "%s" was not created', mcp_sessions_dir));
}

$psr17Factory = new Psr17Factory();

$controller_paths = !empty($_ENV['MCP_CONTROLLER_PATHS'])
    ? explode(':', $_ENV['MCP_CONTROLLER_PATHS'])
    : ['src'];
foreach ($controller_paths as $path) {
    $full_path = base_dir . '/' . $path;
    if (is_dir($full_path)) {
        foreach (glob($full_path . '/*.php') as $file) {
            require_once $file;
        }
    }
}

$response = Server::builder()
    ->setServerInfo($_ENV['MCP_SERVER_NAME'] ?? 'MCP Server', $_ENV['APP_VERSION'] ?? '0.0.0')
    ->setDiscovery(base_dir, $controller_paths)
    ->setSession(new FileSessionStore(mcp_sessions_dir))
    ->setLogger($logger)
    ->setPaginationLimit(PHP_INT_MAX) // Disable pagination by setting to max int
    ->build()
    ->run(
        new StreamableHttpTransport(
            (new ServerRequestCreator($psr17Factory, $psr17Factory, $psr17Factory, $psr17Factory))->fromGlobals(),
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
