[CmdletBinding()]
param(
    [ValidateSet('generate', 'edit')][string]$Mode = 'generate',
    [Parameter(Mandatory)][string]$PromptFile,
    [Parameter(Mandatory)][string]$Out,
    [string[]]$ImageFiles = @(),
    [string]$ConfigFile = $env:IMAGE25_CONFIG_FILE,
    [string]$Python = $(if ($env:IMAGE25_PYTHON) { $env:IMAGE25_PYTHON } else { 'python' }),
    [string]$Model = 'gpt-image-2.5',
    [string]$Size = '1024x1024',
    [ValidateSet('low', 'medium', 'high', 'auto')][string]$Quality = 'medium',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
# Python 会把正常进度写到 stderr；交给退出码判断成功与否。
$PSNativeCommandUseErrorActionPreference = $false
$codexDirectory = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$cli = Join-Path $codexDirectory 'skills/.system/imagegen/scripts/image_gen.py'
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
    $ConfigFile = Join-Path $codexDirectory 'image25-api/config.json'
}
$pythonCommand = Get-Command $Python -CommandType Application -ErrorAction SilentlyContinue
if ($null -ne $pythonCommand) { $Python = $pythonCommand.Source }
foreach ($required in @($Python, $cli, $PromptFile) + $ImageFiles) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw '缺少 Python、内置 imagegen CLI、提示词或输入图片文件，请检查路径。'
    }
}
if ([IO.Path]::GetExtension($Out) -ne '.png') { throw '输出路径必须以 .png 结尾。' }
if (Test-Path -LiteralPath $Out) { throw '输出文件已存在，请使用新的版本文件名。' }
if ($Mode -eq 'edit' -and $ImageFiles.Count -eq 0) { throw '编辑模式至少需要一张输入图片。' }
if ($Mode -eq 'generate' -and $ImageFiles.Count -ne 0) { throw '提供输入图片时请使用 edit 模式。' }

$credential = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY', 'Process')
$endpoint = [Environment]::GetEnvironmentVariable('OPENAI_BASE_URL', 'Process')
if (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
    $configText = Get-Content -LiteralPath $ConfigFile -Raw -Encoding utf8
    if ($configText.TrimStart().StartsWith('{')) {
        try { $parsedConfig = $configText | ConvertFrom-Json }
        catch { throw '配置 JSON 无法解析。未输出原文，以免泄露密钥。' }
        $credential = [string]$parsedConfig.api_key
        $endpoint = [string]$parsedConfig.base_url
    } else {
        $urls = [regex]::Matches($configText, 'https?://[^\s"<>]+')
        $keys = [regex]::Matches($configText, 'sk-[^\s"<>]+')
        if ($urls.Count -ne 1 -or $keys.Count -ne 1) {
            throw '纯文本配置需要恰好一个接口地址和一个 sk- 密钥；也可使用 JSON 配置。'
        }
        $endpoint = $urls[0].Value
        $credential = $keys[0].Value
    }
} elseif ($PSBoundParameters.ContainsKey('ConfigFile')) {
    throw '指定的配置文件不存在。'
}
if ([string]::IsNullOrWhiteSpace($credential) -or [string]::IsNullOrWhiteSpace($endpoint)) {
    throw '缺少接口地址或密钥，请配置本地文件或进程环境变量。不要把密钥发到聊天。'
}
$uri = $null
if (-not [uri]::TryCreate($endpoint.Trim(), [UriKind]::Absolute, [ref]$uri) -or
    $uri.Scheme -notin @('http', 'https') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
    throw '接口地址无效，或在地址中包含了认证信息、查询参数或片段。'
}
$endpoint = $uri.AbsoluteUri.TrimEnd('/')
if (-not $endpoint.EndsWith('/v1')) { $endpoint += '/v1' }
$arguments = @($cli, $Mode, '--model', $Model, '--prompt-file', $PromptFile,
    '--no-augment', '--size', $Size, '--quality', $Quality, '--out', $Out)
foreach ($imagePath in $ImageFiles) { $arguments += @('--image', $imagePath) }
if ($DryRun) { $arguments += '--dry-run' }
$previousKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY', 'Process')
$previousUrl = [Environment]::GetEnvironmentVariable('OPENAI_BASE_URL', 'Process')
try {
    [Environment]::SetEnvironmentVariable('OPENAI_API_KEY', $credential, 'Process')
    [Environment]::SetEnvironmentVariable('OPENAI_BASE_URL', $endpoint, 'Process')
    Write-Output "Image request: mode=$Mode model=$Model; credentials hidden."
    & $Python @arguments 2>&1 | ForEach-Object {
        $safeLine = $_.ToString().Replace($credential, '[REDACTED]')
        $safeLine = [regex]::Replace($safeLine, 'sk-[^\s"<>]+', '[REDACTED]')
        Write-Output $safeLine
    }
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "生图工具失败，退出码 $code；请查看上方脱敏摘要。" }
    if (-not $DryRun -and -not (Test-Path -LiteralPath $Out -PathType Leaf)) {
        throw '工具返回成功但没有目标图片，请检查输出，勿重复提交。'
    }
} finally {
    [Environment]::SetEnvironmentVariable('OPENAI_API_KEY', $previousKey, 'Process')
    [Environment]::SetEnvironmentVariable('OPENAI_BASE_URL', $previousUrl, 'Process')
}
