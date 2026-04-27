<#
.SYNOPSIS
    Interactively select a GitHub Copilot model (LiteLLM BYOK or regular Copilot)
    and apply the required environment variables.

.DESCRIPTION
    This is a workaround until the Copilot CLI has a built-in model picker.

    All custom models route through a shared LiteLLM instance. The base URL and
    API key are constant; only COPILOT_MODEL changes between selections. Selecting
    "Regular Copilot" clears all three BYOK variables, restoring GitHub-hosted routing.

    Shared connection details are read from two user-level environment variables:
      LITELLM_BASE_URL  — the base URL of your LiteLLM instance
      LITELLM_API_KEY   — your LiteLLM API key

    Set those once (e.g., in your PowerShell profile or Windows user env settings).
    To add models, edit the $Models array below.

    IMPORTANT - Environment variable scope:
      * When run normally (.\Switch-CopilotModel.ps1), env vars are set for the
        child process only. Use -Launch to start `copilot` immediately with the
        selected config.
      * When dot-sourced (. .\Switch-CopilotModel.ps1 -EnvOnly), env vars are set
        in the CALLING shell's scope so they persist for the current session.

.PARAMETER Launch
    After applying the selected model, immediately start `copilot`.

.PARAMETER EnvOnly
    Set environment variables without launching `copilot`. Most useful when
    dot-sourcing so variables persist in the calling shell.

.PARAMETER Model
    Non-interactively select a model by name (case-insensitive). Skips the menu.
    Use "regular" or "copilot" to revert to GitHub-hosted models.

.EXAMPLE
    .\Switch-CopilotModel.ps1 -Launch
    Picks a model interactively, sets env vars, then starts copilot.

.EXAMPLE
    . .\Switch-CopilotModel.ps1 -EnvOnly
    Dot-source to pick a model and persist env vars in the current shell.

.EXAMPLE
    .\Switch-CopilotModel.ps1 -Model "claude-sonnet-4.6" -Launch
    Selects claude-sonnet-4.6 non-interactively and starts copilot.
#>
[CmdletBinding()]
param(
    [switch]$Launch,
    [switch]$EnvOnly,
    [string]$Model
)

# ─────────────────────────────────────────────────────────────────────────────
# MODELS — add or remove entries as needed.
# The first entry (empty string) always means "Regular Copilot" (clears BYOK vars).
# All other entries are model identifiers passed to LiteLLM as COPILOT_MODEL.
# ─────────────────────────────────────────────────────────────────────────────
$Models = @(
    '',                  # Regular Copilot (GitHub-hosted)
    'claude-haiku-4.5',
    'gpt-5-mini',
    'claude-opus-4.7',
    'claude-sonnet-4.6'
)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
function Write-Section([string]$Text) {
    Write-Host ''
    Write-Host ('─' * 70) -ForegroundColor DarkCyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('─' * 70) -ForegroundColor DarkCyan
}

function Mask-Key([string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return '(none)' }
    if ($Key.Length -le 8) { return '****' }
    return ($Key.Substring(0, 4) + ('*' * ($Key.Length - 8)) + $Key.Substring($Key.Length - 4))
}

# ─────────────────────────────────────────────────────────────────────────────
# Read shared LiteLLM connection details from user environment
# ─────────────────────────────────────────────────────────────────────────────
$litellmBaseUrl = [System.Environment]::GetEnvironmentVariable('LITELLM_BASE_URL')
$litellmApiKey  = [System.Environment]::GetEnvironmentVariable('LITELLM_API_KEY')

# ─────────────────────────────────────────────────────────────────────────────
# Model selection
# ─────────────────────────────────────────────────────────────────────────────
$selectedModel = $null

if (-not [string]::IsNullOrWhiteSpace($Model)) {
    if ($Model -imatch '^(regular|copilot)$') {
        $selectedModel = ''
    } elseif ($Models -icontains $Model) {
        $selectedModel = $Model
    } else {
        Write-Error "Model '$Model' not found. Valid options: $($Models | Where-Object { $_ } | Join-String -Separator ', ')"
        return
    }
} else {
    Write-Section 'GitHub Copilot — Model Switcher'
    Write-Host 'Select a model:' -ForegroundColor White
    Write-Host ''

    for ($i = 0; $i -lt $Models.Count; $i++) {
        $m = $Models[$i]
        if ([string]::IsNullOrEmpty($m)) {
            Write-Host "$($i + 1)) Regular Copilot" -ForegroundColor Yellow -NoNewline
            Write-Host '  — GitHub-hosted models (default)' -ForegroundColor DarkGray
        } else {
            Write-Host "$($i + 1)) $m" -ForegroundColor Yellow
        }
    }

    Write-Host ''
    $raw = Read-Host "Enter number (1-$($Models.Count))"
    $idx = 0
    if (-not [int]::TryParse($raw.Trim(), [ref]$idx) -or $idx -lt 1 -or $idx -gt $Models.Count) {
        Write-Warning "Invalid selection '$raw'. Aborting."
        return
    }
    $selectedModel = $Models[$idx - 1]
}

# ─────────────────────────────────────────────────────────────────────────────
# Apply environment variables
# ─────────────────────────────────────────────────────────────────────────────
$byokVars = @('COPILOT_PROVIDER_BASE_URL', 'COPILOT_PROVIDER_API_KEY', 'COPILOT_MODEL')

if ([string]::IsNullOrEmpty($selectedModel)) {
    Write-Section 'Applying: Regular Copilot'
    foreach ($var in $byokVars) {
        [System.Environment]::SetEnvironmentVariable($var, $null, 'Process')
    }
    Write-Host 'BYOK variables cleared.' -ForegroundColor Green
    Write-Host 'Regular GitHub Copilot routing will be used.' -ForegroundColor Green
} else {
    Write-Section "Applying: $selectedModel"

    if ([string]::IsNullOrWhiteSpace($litellmBaseUrl)) {
        Write-Warning "LITELLM_BASE_URL is not set. Set it with: `$env:LITELLM_BASE_URL = 'https://your-litellm-instance/v1'"
    }
    if ([string]::IsNullOrWhiteSpace($litellmApiKey)) {
        Write-Warning "LITELLM_API_KEY is not set. Set it with: `$env:LITELLM_API_KEY = 'your-key-here'"
    }

    $env:COPILOT_PROVIDER_BASE_URL = $litellmBaseUrl
    $env:COPILOT_PROVIDER_API_KEY  = $litellmApiKey
    $env:COPILOT_MODEL             = $selectedModel

    Write-Host "  COPILOT_PROVIDER_BASE_URL  = $litellmBaseUrl" -ForegroundColor Green
    Write-Host "  COPILOT_PROVIDER_API_KEY   = $(Mask-Key $litellmApiKey)" -ForegroundColor Green
    Write-Host "  COPILOT_MODEL              = $selectedModel" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# Launch copilot (if requested)
# ─────────────────────────────────────────────────────────────────────────────
if ($EnvOnly) {
    Write-Host ''
    Write-Host 'Environment variables set for this session (-EnvOnly).' -ForegroundColor Cyan
    Write-Host 'Run `copilot` when ready.' -ForegroundColor DarkGray

    if ($MyInvocation.InvocationName -ne '.') {
        Write-Host ''
        Write-Host 'NOTE: You invoked this script normally (not dot-sourced).' -ForegroundColor DarkYellow
        Write-Host '      Variables were set in the child process and will NOT persist.' -ForegroundColor DarkYellow
        Write-Host "      To persist, run:  . .\$($MyInvocation.MyCommand.Name) -EnvOnly" -ForegroundColor DarkYellow
    }
    return
}

if ($Launch) {
    Write-Host ''
    Write-Host 'Starting copilot...' -ForegroundColor Cyan
    copilot
    return
}

# Default: prompt the user
Write-Host ''
$answer = Read-Host 'Launch copilot now? [Y/n]'
if ($answer -match '^[Yy]?$') {
    Write-Host 'Starting copilot...' -ForegroundColor Cyan
    copilot
} else {
    Write-Host "Done. Run 'copilot' when ready." -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'TIP: To keep these vars in your shell without launching copilot, use:' -ForegroundColor DarkGray
    Write-Host "     . .\$($MyInvocation.MyCommand.Name) -EnvOnly" -ForegroundColor DarkGray
}
