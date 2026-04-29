# copilot-utils

PowerShell utilities for [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli).

## Switch-CopilotModel.ps1

Interactively switch between GitHub Copilot providers and models — including
GitHub-hosted (default), LiteLLM BYOK proxy, Azure AI Foundry Local, and Ollama.

### Setup

Dot-source the script in your PowerShell profile so all functions are available in every session:

```powershell
. /path/to/Switch-CopilotModel.ps1
```

Set your LiteLLM connection details once (if using LiteLLM):

```powershell
$env:LITELLM_BASE_URL = 'https://your-litellm-instance/v1'
$env:LITELLM_API_KEY  = 'your-api-key'
```

### Functions

| Function | Alias | Description |
|---|---|---|
| `Switch-CopilotModel` | `scm` | Interactive or parameterized provider/model switcher |
| `Reset-CopilotModel` | `rcm` | Restore GitHub-hosted routing (clear all BYOK vars) |
| `Get-CopilotModel` | `gcm` | Display current active provider and model |

### Usage

**Interactive menu** — lists all available providers and models:

```powershell
Switch-CopilotModel
# or
scm
```

**Non-interactive** — switch directly by model name:

```powershell
Switch-CopilotModel -Model 'claude-sonnet-4.6'
Switch-CopilotModel -Model 'phi-4-mini' -Provider 'FoundryLocal'
```

**Reset to GitHub default:**

```powershell
Reset-CopilotModel
# or
rcm
```

**Check current provider:**

```powershell
Get-CopilotModel
# or
gcm
```

### Providers

| Provider | Requirements | Notes |
|---|---|---|
| **GitHub** | None | Default GitHub-hosted routing |
| **LiteLLM** | `LITELLM_BASE_URL`, `LITELLM_API_KEY` env vars | BYOK proxy; edit `$script:LiteLLMModels` to customize available models |
| **FoundryLocal** | [`foundry` CLI](https://github.com/microsoft/ai-toolkit), models in cache | Service started on demand; models discovered via `foundry cache list` |
| **Ollama** | [`ollama` CLI](https://ollama.com), models pulled locally | Models discovered via `ollama list`; context length queried automatically |

### Menu demo

```
──────────────────────────────────────────────────────────────────────
GitHub Copilot — Provider & Model Switcher
──────────────────────────────────────────────────────────────────────
Select a provider and model:

1) GitHub [current]
2) [LiteLLM] claude-haiku-4.5
3) [LiteLLM] gpt-5-mini
4) [LiteLLM] claude-opus-4.7
5) [LiteLLM] claude-sonnet-4.6
6) [FoundryLocal] phi-4-mini
7) [Ollama] gemma3:latest
8) Exit

Enter number (1-8) [Esc to cancel]:
```
