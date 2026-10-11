# 把 relay-client.js 打入 Cuckoo-Code 的 app.asar，替换飞书客户端为中继客户端。
# 用法：以管理员/普通权限运行（需 Cuckoo-Code 未运行）
$ErrorActionPreference = 'Stop'
$patchDir  = $PSScriptRoot
$logFile   = Join-Path $patchDir 'relay-patch.log'
$asar      = 'D:\Program Files\Cuckoo-Code\resources\app.asar'
$srcClient = Join-Path $patchDir 'relay-client.js'
# 复用 feishu-patch 里的 asar 工具
$asarCli   = Join-Path $env:USERPROFILE '.cuckoo\feishu-patch\node_modules\@electron\asar\bin\asar.js'
$stateFile = Join-Path $patchDir 'relay-state.json'

function Write-Log($m) {
    Add-Content -Path $logFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m) -Encoding UTF8
}

if (Get-Process Cuckoo-Code -ErrorAction SilentlyContinue) {
    Write-Log 'Cuckoo-Code 正在运行，先退出再打补丁'
    Write-Host '请先退出 Cuckoo-Code，再运行本脚本' -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $asar)) { Write-Log 'asar 不存在'; Write-Host '找不到 ' + $asar; exit 1 }
if (-not (Test-Path $asarCli)) { Write-Log '缺少 asar 工具'; Write-Host '缺少 asar 工具: ' + $asarCli; exit 1 }
if (-not (Test-Path $srcClient)) { Write-Log '缺少 relay-client.js'; Write-Host '缺少 relay-client.js'; exit 1 }

# 目标文件：out/src/feishu/client.js
$work = Join-Path $env:TEMP ('cuckoo-relay-' + [guid]::NewGuid().ToString('N'))
Write-Log ('解包 -> ' + $work)
node $asarCli extract $asar $work 2>&1 | Out-Null

$fClient = Join-Path $work 'out\src\feishu\client.js'
if (-not (Test-Path $fClient)) {
    Write-Log '目标 client.js 不存在（版本结构变化）'
    Write-Host '未找到 out\src\feishu\client.js，Cuckoo-Code 版本结构可能已变化' -ForegroundColor Red
    [System.IO.Directory]::Delete($work, $true)
    exit 1
}

# 备份原始 client.js（供回滚）
if (-not (Test-Path ($fClient + '.feishu.bak'))) {
    Copy-Item $fClient ($fClient + '.feishu.bak') -Force
}

# 替换
Copy-Item $srcClient $fClient -Force
Write-Log '已替换 client.js -> relay-client.js'

# 重新打包
$newAsar = Join-Path $env:TEMP ('cuckoo-relay-new-' + [guid]::NewGuid().ToString('N') + '.asar')
Write-Log '重新打包...'
node $asarCli pack $work $newAsar --unpack '**/ripgrep*/**' 2>&1 | Out-Null
if (-not (Test-Path $newAsar)) { Write-Log '打包失败'; [System.IO.Directory]::Delete($work, $true); exit 1 }

# 备份 + 替换 asar
if (-not (Test-Path ($asar + '.bak'))) { Copy-Item $asar ($asar + '.bak') -Force }
Copy-Item $newAsar $asar -Force

@{ patchedHash = (Get-FileHash $asar -Algorithm SHA256).Hash; patchedAt = (Get-Date -Format 'o') } |
    ConvertTo-Json | Set-Content $stateFile -Encoding UTF8

Write-Log '中继补丁应用完成'
Write-Host '✅ 中继补丁已应用。现在编辑 ~/.cuckoo/feishu.json，加 relayUrl 和 targetDeviceId，重启 Cuckoo-Code。' -ForegroundColor Green

[System.IO.Directory]::Delete($work, $true)
Remove-Item $newAsar -Force -ErrorAction SilentlyContinue
Remove-Item ($newAsar + '.unpacked') -Recurse -Force -ErrorAction SilentlyContinue
