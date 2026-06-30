<?php
/**
 * XenoR2 Telemetry Receiver
 * Принимает callback'и от stage_v4.ps1
 * Пишет: лог на каждую машину + сводный лог
 */

// Только POST
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    die('Method Not Allowed');
}

// Читаем JSON
$raw = file_get_contents('php://input');
$data = json_decode($raw, true);

if (!$data) {
    http_response_code(400);
    die('Bad Request');
}

// Извлекаем поля
$hostname  = isset($data['hostname'])  ? preg_replace('/[^a-zA-Z0-9_-]/', '_', $data['hostname']) : 'unknown';
$username  = isset($data['username'])  ? $data['username']  : '?';
$ip        = isset($data['ip'])        ? $data['ip']        : '?';
$os        = isset($data['os'])        ? $data['os']        : '?';
$is_admin  = isset($data['is_admin'])  ? ($data['is_admin'] ? 'admin' : 'user') : '?';
$pid       = isset($data['pid'])       ? $data['pid']       : '?';
$stage     = isset($data['stage'])     ? $data['stage']     : '?';
$status    = isset($data['status'])    ? $data['status']    : '?';
$detail    = isset($data['detail'])    ? $data['detail']    : '';
$ts        = isset($data['ts'])        ? $data['ts']        : date('Y-m-d\TH:i:s');

// Директория логов
$logDir = __DIR__ . '/telemetry';
if (!is_dir($logDir)) {
    mkdir($logDir, 0755, true);
}

// Формат строки лога
$line = sprintf("[%s] %s | %s | %s | %s | %s | %s | %s\n",
    $ts, $stage, $status, $username, $ip, $os, $is_admin, $detail
);

// 1. Лог на конкретную машину
$hostLog = $logDir . '/' . $hostname . '.log';
file_put_contents($hostLog, $line, FILE_APPEND | LOCK_EX);

// 2. Сводный лог всех машин
$allLog = $logDir . '/_all.log';
file_put_contents($allLog, $line, FILE_APPEND | LOCK_EX);

// 3. JSON-дамп полных данных (для парсинга)
$jsonLog = $logDir . '/' . $hostname . '.jsonl';
file_put_contents($jsonLog, json_encode($data) . "\n", FILE_APPEND | LOCK_EX);

// 4. Статус-файл — последнее состояние машины
$statusFile = $logDir . '/' . $hostname . '.status';
$statusData = [
    'hostname'  => $hostname,
    'username'  => $username,
    'ip'        => $ip,
    'os'        => $os,
    'is_admin'  => $is_admin,
    'last_stage' => $stage,
    'last_status' => $status,
    'last_detail' => $detail,
    'last_seen'  => $ts,
    'total_callbacks' => 0,
];

// Сохраняем предыдущий счётчик
if (file_exists($statusFile)) {
    $prev = json_decode(file_get_contents($statusFile), true);
    if ($prev && isset($prev['total_callbacks'])) {
        $statusData['total_callbacks'] = $prev['total_callbacks'] + 1;
    }
} else {
    $statusData['total_callbacks'] = 1;
}

file_put_contents($statusFile, json_encode($statusData, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));

// Ответ
http_response_code(200);
header('Content-Type: application/json');
echo json_encode(['status' => 'ok', 'hostname' => $hostname]);
