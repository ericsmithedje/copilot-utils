#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\Switch-CopilotModel.ps1')
}

# ---------------------------------------------------------------------------- #
# Reset-CopilotModel
# ---------------------------------------------------------------------------- #

Describe 'Reset-CopilotModel' {
    BeforeEach {
        $env:COPILOT_PROVIDER_BASE_URL         = 'https://example.com'
        $env:COPILOT_PROVIDER_API_KEY          = 'key'
        $env:COPILOT_MODEL                     = 'some-model'
        $env:COPILOT_PROVIDER_WIRE_API         = 'responses'
        $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS = '8192'
        $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS = '4096'
    }

    AfterEach {
        foreach ($var in @('COPILOT_PROVIDER_BASE_URL', 'COPILOT_PROVIDER_API_KEY', 'COPILOT_MODEL',
                           'COPILOT_PROVIDER_WIRE_API', 'COPILOT_PROVIDER_MAX_PROMPT_TOKENS', 'COPILOT_PROVIDER_MAX_OUTPUT_TOKENS')) {
            [System.Environment]::SetEnvironmentVariable($var, $null, 'Process')
        }
    }

    It 'clears COPILOT_PROVIDER_BASE_URL' {
        Reset-CopilotModel
        $env:COPILOT_PROVIDER_BASE_URL | Should -BeNullOrEmpty
    }

    It 'clears COPILOT_PROVIDER_API_KEY' {
        Reset-CopilotModel
        $env:COPILOT_PROVIDER_API_KEY | Should -BeNullOrEmpty
    }

    It 'clears COPILOT_MODEL' {
        Reset-CopilotModel
        $env:COPILOT_MODEL | Should -BeNullOrEmpty
    }

    It 'clears COPILOT_PROVIDER_WIRE_API' {
        Reset-CopilotModel
        $env:COPILOT_PROVIDER_WIRE_API | Should -BeNullOrEmpty
    }

    It 'clears COPILOT_PROVIDER_MAX_PROMPT_TOKENS' {
        Reset-CopilotModel
        $env:COPILOT_PROVIDER_MAX_PROMPT_TOKENS | Should -BeNullOrEmpty
    }

    It 'clears COPILOT_PROVIDER_MAX_OUTPUT_TOKENS' {
        Reset-CopilotModel
        $env:COPILOT_PROVIDER_MAX_OUTPUT_TOKENS | Should -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------- #
# Get-MaskedApiKey
# ---------------------------------------------------------------------------- #

Describe 'Get-MaskedApiKey' {
    It 'returns (none) for a null key' {
        Get-MaskedApiKey $null | Should -Be '(none)'
    }

    It 'returns (none) for an empty string' {
        Get-MaskedApiKey '' | Should -Be '(none)'
    }

    It 'returns **** for a short key (<= 8 chars)' {
        Get-MaskedApiKey 'short' | Should -Be '****'
    }

    It 'masks the middle of a long key' {
        $result = Get-MaskedApiKey 'abcd1234efgh'
        $result | Should -BeLike 'abcd****efgh'
    }

    It 'preserves the first 4 and last 4 characters' {
        $key    = 'sk-abcdefghijklmnop'
        $result = Get-MaskedApiKey $key
        $result | Should -Match '^sk-a'
        $result | Should -Match 'mnop$'
    }
}

# ---------------------------------------------------------------------------- #
# Build-ProviderEntries
# ---------------------------------------------------------------------------- #

Describe 'Build-ProviderEntries' {
    BeforeEach {
        $env:LITELLM_BASE_URL = $null
        $env:LITELLM_API_KEY  = $null
    }

    AfterEach {
        $env:LITELLM_BASE_URL = $null
        $env:LITELLM_API_KEY  = $null
    }

    It 'always includes a GitHub entry as the first item' {
        $entries = Build-ProviderEntries
        $entries[0].Provider | Should -Be 'GitHub'
        $entries[0].Model    | Should -BeNullOrEmpty
    }

    It 'includes LiteLLM entries when LITELLM_BASE_URL is set' {
        $env:LITELLM_BASE_URL = 'https://litellm.example.com'
        $entries = Build-ProviderEntries
        $litellm = $entries | Where-Object { $_.Provider -eq 'LiteLLM' }
        $litellm | Should -Not -BeNullOrEmpty
    }

    It 'does not include LiteLLM entries when LITELLM_BASE_URL is not set' {
        $entries = Build-ProviderEntries
        $litellm = $entries | Where-Object { $_.Provider -eq 'LiteLLM' }
        $litellm | Should -BeNullOrEmpty
    }

    It 'has the correct count of LiteLLM entries when configured' {
        $env:LITELLM_BASE_URL = 'https://litellm.example.com'
        $entries = Build-ProviderEntries
        $litellm = @($entries | Where-Object { $_.Provider -eq 'LiteLLM' })
        $litellm.Count | Should -Be $script:LiteLLMModels.Count
    }
}

# ---------------------------------------------------------------------------- #
# Get-CopilotModel
# ---------------------------------------------------------------------------- #

Describe 'Get-CopilotModel' {
    BeforeEach {
        $env:COPILOT_PROVIDER_BASE_URL = $null
        $env:COPILOT_PROVIDER_API_KEY  = $null
        $env:COPILOT_MODEL             = $null
    }

    AfterEach {
        $env:COPILOT_PROVIDER_BASE_URL = $null
        $env:COPILOT_PROVIDER_API_KEY  = $null
        $env:COPILOT_MODEL             = $null
    }

    It 'runs without error when no BYOK vars are set' {
        { Get-CopilotModel } | Should -Not -Throw
    }

    It 'runs without error when BYOK vars are set' {
        $env:COPILOT_PROVIDER_BASE_URL = 'https://litellm.example.com'
        $env:COPILOT_PROVIDER_API_KEY  = 'sk-testkey12345678'
        $env:COPILOT_MODEL             = 'claude-sonnet-4.6'
        { Get-CopilotModel } | Should -Not -Throw
    }

    It 'reports GitHub provider when no vars are set' {
        $output = Get-CopilotModel *>&1 | Out-String
        $output | Should -Match 'GitHub'
    }

    It 'reports LiteLLM provider when BYOK URL matches LITELLM_BASE_URL' {
        $env:LITELLM_BASE_URL          = 'https://litellm.example.com'
        $env:COPILOT_PROVIDER_BASE_URL = 'https://litellm.example.com'
        $env:COPILOT_MODEL             = 'claude-sonnet-4.6'
        $output = Get-CopilotModel *>&1 | Out-String
        $output | Should -Match 'LiteLLM'
    }
}

# ---------------------------------------------------------------------------- #
# Get-OllamaModels
# ---------------------------------------------------------------------------- #

Describe 'Get-OllamaModels' {
    It 'returns an array (possibly empty) without throwing' {
        { Get-OllamaModels } | Should -Not -Throw
    }

    It 'returns an empty array when ollama is not installed' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ollama' } -ModuleName ''
        $result = Get-OllamaModels
        $result.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------- #
# Build-ProviderEntries (Ollama)
# ---------------------------------------------------------------------------- #

Describe 'Build-ProviderEntries Ollama' {
    It 'includes Ollama entries when ollama returns models' {
        Mock Get-OllamaModels { return @('llama3.2:latest', 'mistral:latest') }
        $entries = Build-ProviderEntries
        $ollama  = $entries | Where-Object { $_.Provider -eq 'Ollama' }
        $ollama | Should -Not -BeNullOrEmpty
    }

    It 'sets BaseUrl to localhost:11434 for Ollama entries' {
        Mock Get-OllamaModels { return @('llama3.2:latest') }
        $entries = Build-ProviderEntries
        $entry   = $entries | Where-Object { $_.Provider -eq 'Ollama' } | Select-Object -First 1
        $entry.BaseUrl | Should -Be 'http://localhost:11434/v1'
    }

    It 'does not include Ollama entries when no models are available' {
        Mock Get-OllamaModels { return @() }
        $entries = Build-ProviderEntries
        $ollama  = $entries | Where-Object { $_.Provider -eq 'Ollama' }
        $ollama | Should -BeNullOrEmpty
    }
}
