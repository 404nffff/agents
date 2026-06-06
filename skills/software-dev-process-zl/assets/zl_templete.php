<?php

/**
 * 业务链路探针模板。
 *
 * 使用方式：
 * 1. 复制本文件到 `docs/[需求目录]/[需求标识]_probe.php`。
 * 2. 将类名 `ZhiliaoBusinessProbeTemplate` 改成与需求匹配的唯一类名。
 * 3. 按需求替换 `loadBusinessDependencies()`、`buildRequestFromPayload()`、
 *    `runStep1()`、`runStep2()`、`runStep3()`、`runStep4()`、`runStep5()`、
 *    `assertStepResult()` 中的占位逻辑。
 * 4. 用 `db-query` 只读查询组装 payload JSON，再执行复制后的探针脚本。
 *
 * 注意：本文件是模板，不是可直接交付的业务探针；禁止直接把本文件作为
 * `sdlc-test` 的执行脚本。
 */

header('Content-Type: text/plain; charset=utf-8');

date_default_timezone_set('PRC');
define('ROOT_PATH', dirname(__FILE__) . '/../../');
define('APP_DEBUG', true);
define('APP_MODE', 'api');
define('APP_PATH', ROOT_PATH . 'Admin/');
define('APP_SWOOLE_NAME', 'zhiliao_script');

function app_exception_handler($e)
{
    error_log($e->getMessage());
}

function app_error_handler($errno, $errstr, $errfile, $errline)
{
    error_log('[' . $errno . '] ' . $errstr . '; ' . $errfile . ':' . $errline);
}

function fatal_error_handler()
{
    $e = error_get_last();
    if (!$e) {
        return;
    }
    switch ($e['type']) {
        case E_ERROR:
        case E_PARSE:
        case E_CORE_ERROR:
        case E_COMPILE_ERROR:
        case E_USER_ERROR:
            error_log(json_encode($e, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
            break;
    }
}

function check_runtime_environment()
{
    $runtimePath = APP_PATH . 'Runtime/';
    if (!file_exists($runtimePath)) {
        return mkdir($runtimePath, 0777, true);
    }
    return chmod($runtimePath, 0777);
}

register_shutdown_function('fatal_error_handler');
set_error_handler('app_error_handler');
set_exception_handler('app_exception_handler');

class ZhiliaoBusinessProbeTemplate
{
    /**
     * 真实 payload 数据，默认由 db-query 只读查询组装。
     *
     * @var array
     */
    private $payload = array(
        'step' => 1,
        'payload_file' => '',
    );

    public function __construct($argv = array())
    {
        $cliPayload = $this->parseCliPayload($argv);
        if (!empty($cliPayload)) {
            $this->payload = array_merge($this->payload, $cliPayload);
        }

        if (!empty($this->payload['payload_file'])) {
            $filePayload = $this->loadPayload($this->payload['payload_file']);
            $this->payload = array_merge($this->payload, $filePayload);
        }
    }

    /**
     * 加载业务运行环境。
     *
     * 复制模板后，按目标链路补充必要模块与业务类，例如：
     * - `\Think\Dispatcher::loadModule('Api')`
     * - `require_once ROOT_PATH . 'Library/.../Target.class.php'`
     *
     * @return void
     */
    private function loadThinkPhp()
    {
        static $loaded = false;
        if ($loaded) {
            return;
        }
        if (!check_runtime_environment()) {
            exit(1);
        }
        require ROOT_PATH . 'Core/ThinkPHP.php';

        $this->loadBusinessDependencies();
        $loaded = true;
    }

    /**
     * 加载当前探针所需业务依赖。
     *
     * @return void
     */
    private function loadBusinessDependencies()
    {
        // TODO: 复制到需求目录后，按目标链路加载模块和业务类。
        // 示例：
        // \Think\Dispatcher::loadModule('Api');
        // \Think\Dispatcher::loadModule('Zhiliao');
        // \Think\Dispatcher::loadModule('Admin');
        // require_once ROOT_PATH . 'Library/Zhiliao/Lib/Example/TargetService.class.php';
    }

    /**
     * 统一步骤入口。
     *
     * @param int|string $step 步骤编号或 all
     * @return array
     */
    public function run($step)
    {
        $this->loadThinkPhp();

        if ($step === 'all') {
            $items = array();
            foreach (array(1, 2, 3, 4) as $item) {
                $items[] = $this->run($item);
            }
            return array(
                'ok' => true,
                'step' => 'all',
                'payload' => $this->buildPayloadSummary($this->payload),
                'items' => $items,
            );
        }

        $step = intval($step);

        $start = microtime(true);
        $request = $this->buildRequestFromPayload($this->payload);
        switch ($step) {
            case 1:
                $result = $this->runStep1($request);
                break;
            case 2:
                $result = $this->runStep2($request);
                break;
            case 3:
                $result = $this->runStep3($request);
                break;
            case 4:
                $result = $this->runStep4($request);
                break;
            case 5:
                $result = $this->runStep5($request);
                break;
            default:
                $result = array(
                    'ok' => false,
                    'message' => 'step 仅支持 1、2、3、4、5 或 all',
                );
        }

        $costMs = round((microtime(true) - $start) * 1000, 2);
        return $this->formatStepResult($step, $request, $result, $costMs);
    }

    public function getStep()
    {
        return isset($this->payload['step']) ? $this->payload['step'] : 1;
    }

    /**
     * 根据 payload 构造目标业务链路入参。
     *
     * @param array $payload
     * @return array
     */
    private function buildRequestFromPayload($payload)
    {
        // TODO: 复制模板后，将 db-query 组装的真实 payload 转成目标业务方法入参。
        return array(
            'payload' => $payload,
        );
    }

    /**
     * Step 1: 常用于权限、配置或前置条件探针。
     *
     * @param array $request
     * @return mixed
     */
    private function runStep1($request)
    {
        return $this->placeholderResult('runStep1');
    }

    /**
     * Step 2: 常用于汇总数量、金额或状态探针。
     *
     * @param array $request
     * @return mixed
     */
    private function runStep2($request)
    {
        return $this->placeholderResult('runStep2');
    }

    /**
     * Step 3: 常用于明细列表或候选数据探针。
     *
     * @param array $request
     * @return mixed
     */
    private function runStep3($request)
    {
        return $this->placeholderResult('runStep3');
    }

    /**
     * Step 4: 常用于 dry-run 预览探针。
     *
     * @param array $request
     * @return mixed
     */
    private function runStep4($request)
    {
        return $this->placeholderResult('runStep4');
    }

    /**
     * Step 5: 常用于必须显式确认的执行链路探针。
     *
     * @param array $request
     * @return mixed
     */
    private function runStep5($request)
    {
        return $this->placeholderResult('runStep5');
    }

    /**
     * 格式化单个步骤结果，保证所有步骤走统一出口。
     *
     * @param int $step
     * @param array $request
     * @param mixed $result
     * @param float $costMs
     * @return array
     */
    private function formatStepResult($step, $request, $result, $costMs)
    {
        $assertion = $this->assertStepResult($step, $result, $this->payload);

        return array(
            'ok' => !empty($assertion['ok']),
            'step' => $step,
            'duration_ms' => $costMs,
            'payload' => $this->buildPayloadSummary($this->payload),
            'request' => $this->buildRequestSummary($request),
            'result_type' => is_array($result) ? 'array' : gettype($result),
            'data' => $this->normalizeValue($result),
            'assertion' => $this->normalizeValue($assertion),
        );
    }

    /**
     * 核验步骤结果是否符合预期。
     *
     * @param int $step
     * @param mixed $result
     * @param array $payload
     * @return array
     */
    private function assertStepResult($step, $result, $payload)
    {
        // TODO: 复制模板后，按步骤判断关键字段、状态码、落库前后状态或下游响应。
        return array(
            'ok' => false,
            'message' => '模板占位断言未替换，不能作为通过结果',
        );
    }

    private function placeholderResult($method)
    {
        return array(
            'template_placeholder' => true,
            'method' => $method,
            'message' => '请在复制后的探针脚本中替换 ' . $method . '() 占位逻辑',
        );
    }

    private function parseCliPayload($argv)
    {
        if (!is_array($argv) || count($argv) < 2) {
            return array();
        }

        $rawInput = trim(implode('&', array_slice($argv, 1)));
        if ($rawInput === '') {
            return array();
        }

        $queryString = $rawInput;
        if (strpos($rawInput, '://') !== false) {
            $parsedQuery = parse_url($rawInput, PHP_URL_QUERY);
            $queryString = $parsedQuery !== null ? $parsedQuery : '';
        }

        $queryString = ltrim($queryString, '?');
        if ($queryString === '') {
            return array();
        }

        parse_str($queryString, $params);
        if (!is_array($params) || empty($params)) {
            return array();
        }

        if (isset($params['step']) && $params['step'] !== 'all') {
            $params['step'] = intval($params['step']);
        }

        return $params;
    }

    private function loadPayload($payloadPath)
    {
        if (!preg_match('/^([A-Za-z]:)?[\/\\\\]/', $payloadPath)) {
            $payloadPath = __DIR__ . '/' . $payloadPath;
        }
        if (!is_file($payloadPath)) {
            return array(
                'payload_file_error' => 'payload 文件不存在: ' . $payloadPath,
            );
        }
        $payload = json_decode(file_get_contents($payloadPath), true);
        if (!is_array($payload)) {
            return array(
                'payload_file_error' => 'payload 不是合法 JSON: ' . $payloadPath,
            );
        }
        return $payload;
    }

    private function buildPayloadSummary($payload)
    {
        return array(
            'keys' => array_keys($payload),
            'count' => count($payload),
            'step' => isset($payload['step']) ? $payload['step'] : null,
            'payload_file' => isset($payload['payload_file']) ? $payload['payload_file'] : '',
        );
    }

    private function buildRequestSummary($request)
    {
        return array(
            'keys' => array_keys($request),
            'count' => count($request),
        );
    }

    private function normalizeValue($value)
    {
        if (is_array($value)) {
            $normalized = array();
            foreach ($value as $key => $item) {
                $normalized[$key] = $this->normalizeValue($item);
            }
            return $normalized;
        }
        if (is_object($value)) {
            return $this->normalizeValue(get_object_vars($value));
        }
        return $value;
    }
}

function zhiliao_business_probe_template_main($argv)
{
    $startedAt = microtime(true);
    if (version_compare(PHP_VERSION, '5.4.0', '<')) {
        return array(
            'ok' => false,
            'executed_at' => date('Y-m-d H:i:s'),
            'total_duration_ms' => round((microtime(true) - $startedAt) * 1000, 2),
            'error' => array(
                'message' => 'require PHP > 5.4.0 !',
            ),
        );
    }

    try {
        $runner = new ZhiliaoBusinessProbeTemplate(isset($argv) ? $argv : array());
        $result = $runner->run($runner->getStep());
        $result['executed_at'] = date('Y-m-d H:i:s');
        $result['total_duration_ms'] = round((microtime(true) - $startedAt) * 1000, 2);
        return $result;
    } catch (Exception $e) {
        return array(
            'ok' => false,
            'executed_at' => date('Y-m-d H:i:s'),
            'total_duration_ms' => round((microtime(true) - $startedAt) * 1000, 2),
            'error' => array(
                'message' => $e->getMessage(),
                'file' => $e->getFile(),
                'line' => $e->getLine(),
            ),
        );
    }
}

echo json_encode(zhiliao_business_probe_template_main(isset($argv) ? $argv : array()), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT), PHP_EOL;
