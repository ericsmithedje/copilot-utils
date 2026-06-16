<#
.SYNOPSIS
    Updates all git repositories in the Orion180 workspace to the latest 'main'
    and prunes stale local branches.

.DESCRIPTION
    For each immediate child directory that is a git repository (excluding
    Orion180.Terraform):
      1. Fetches from origin with --prune (removes stale remote-tracking refs).
      2. Checks out 'main' and fast-forwards to origin/main.
      3. Deletes local branches (other than 'main') that are either:
           - Already merged into 'main', OR
           - Tracking a remote branch that no longer exists ([gone]).

    Repos with uncommitted changes are skipped entirely (no checkout, no pull,
    no branch deletion) and a warning is logged.

.PARAMETER Path
    Workspace root. Defaults to the script's directory.

.PARAMETER Force
    Use -D (force delete) for branches that are not merged into main.

.EXAMPLE
    .\Update-Workspace.ps1
    .\Update-Workspace.ps1 -WhatIf
    .\Update-Workspace.ps1 -Force
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = $PSScriptRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ExcludedRepos = @('Orion180.Terraform')
$DefaultBranch = 'main'

function Write-Section($Text) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
}

function Test-WorkingTreeClean {
    $status = git status --porcelain
    return [string]::IsNullOrWhiteSpace($status)
}

$repos = Get-ChildItem -Path $Path -Directory |
    Where-Object {
        (Test-Path (Join-Path $_.FullName '.git')) -and
        ($ExcludedRepos -notcontains $_.Name)
    }

if (-not $repos) {
    Write-Warning "No git repositories found under $Path"
    return
}

$summary = [System.Collections.Generic.List[object]]::new()

foreach ($repo in $repos) {
    Write-Section $repo.Name
    Push-Location $repo.FullName
    try {
        $result = [pscustomobject]@{
            Repo            = $repo.Name
            CurrentBranch   = $null
            Pulled          = $false
            DeletedBranches = @()
            Warnings        = @()
        }

        Write-Host "Fetching..." -ForegroundColor DarkGray
        git fetch --all --prune --quiet
        if ($LASTEXITCODE -ne 0) {
            $result.Warnings += "git fetch failed"
            $summary.Add($result); continue
        }

        # Verify origin/main exists
        git show-ref --verify --quiet "refs/remotes/origin/$DefaultBranch"
        if ($LASTEXITCODE -ne 0) {
            $result.Warnings += "origin/$DefaultBranch not found; skipping"
            Write-Warning "origin/$DefaultBranch not found in $($repo.Name); skipping."
            $summary.Add($result); continue
        }

        $currentBranch = git rev-parse --abbrev-ref HEAD
        $result.CurrentBranch = $currentBranch
        $clean = Test-WorkingTreeClean

        if (-not $clean) {
            $result.Warnings += "Working tree dirty on '$currentBranch'; skipped checkout/pull/cleanup"
            Write-Warning "Working tree has uncommitted changes; skipping."
            $summary.Add($result); continue
        }

        if ($currentBranch -ne $DefaultBranch) {
            Write-Host "Switching from '$currentBranch' to '$DefaultBranch'..." -ForegroundColor DarkGray
            git checkout $DefaultBranch --quiet
            if ($LASTEXITCODE -ne 0) {
                $result.Warnings += "Failed to checkout '$DefaultBranch'"
                Write-Warning "Failed to checkout '$DefaultBranch' in $($repo.Name)."
                $summary.Add($result); continue
            }
            $currentBranch = $DefaultBranch
            $result.CurrentBranch = $currentBranch
        }

        Write-Host "Fast-forwarding $DefaultBranch..." -ForegroundColor DarkGray
        git merge --ff-only "origin/$DefaultBranch" --quiet
        if ($LASTEXITCODE -eq 0) {
            $result.Pulled = $true
        } else {
            $result.Warnings += "Fast-forward failed (diverged from origin/$DefaultBranch)"
        }

        # Determine branches to delete
        $localBranches = git for-each-ref --format='%(refname:short)|%(upstream:track)' refs/heads/
        $toDelete = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ($line in $localBranches) {
            if (-not $line) { continue }
            $parts = $line.Split('|', 2)
            $name = $parts[0]
            $track = if ($parts.Length -gt 1) { $parts[1] } else { '' }

            if ($name -eq $DefaultBranch) { continue }
            if ($name -eq $currentBranch) { continue }

            $reason = $null
            if ($track -match '\[gone\]') {
                $reason = 'upstream gone'
            } else {
                $mergeBase = git merge-base $name $DefaultBranch 2>$null
                $branchTip = git rev-parse $name 2>$null
                if ($mergeBase -and $branchTip -and $mergeBase -eq $branchTip) {
                    $reason = 'merged'
                }
            }

            if ($reason) {
                $toDelete.Add([pscustomobject]@{ Name = $name; Reason = $reason })
            }
        }

        foreach ($b in $toDelete) {
            $useForce = $Force -or ($b.Reason -eq 'upstream gone')
            $flag = if ($useForce) { '-D' } else { '-d' }
            $msg = "Delete branch '$($b.Name)' ($($b.Reason))"
            if ($PSCmdlet.ShouldProcess($repo.Name, $msg)) {
                git branch $flag $b.Name 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $result.DeletedBranches += "$($b.Name) ($($b.Reason))"
                    Write-Host "  Deleted $($b.Name) [$($b.Reason)]" -ForegroundColor Yellow
                } else {
                    $result.Warnings += "Failed to delete $($b.Name) ($($b.Reason)); use -Force"
                    Write-Warning "Failed to delete $($b.Name); rerun with -Force to force-delete."
                }
            }
        }

        $summary.Add($result)
    }
    catch {
        Write-Warning "Error processing $($repo.Name): $_"
    }
    finally {
        Pop-Location
    }
}

Write-Section "Summary"
foreach ($r in $summary) {
    $status = if ($r.Pulled) { 'updated' } else { 'no-change' }
    Write-Host ("{0,-45} [{1}] on={2}" -f $r.Repo, $status, $r.CurrentBranch)
    foreach ($d in $r.DeletedBranches) { Write-Host "    - deleted: $d" -ForegroundColor Yellow }
    foreach ($w in $r.Warnings) { Write-Host "    ! $w" -ForegroundColor DarkYellow }
}
