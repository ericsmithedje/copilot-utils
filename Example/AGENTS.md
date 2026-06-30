# AGENTS

This workspace guidance applies to all agents and Copilot-assisted tasks.

1. Keep this file up to date whenever workspace-level conventions, defaults, or operating rules change.
2. For Azure DevOps operations, the default project is **My180 Architecture Redesign**, unless the user explicitly specifies a different project.
3. When working in a cloned repository, read and follow that repository’s `AGENTS.md` (and any `.github/copilot-instructions.md`) before making changes.
4. When working on a feature branch, always commit and push completed changes without waiting for the user to explicitly ask.
5. In Azure DevOps, reference pull requests with `!12345` (not `#12345`; `#` is for work items/issues). Breaking changes still use `!` in commit/PR titles (for example, `feat(12345)!:`).
6. Never amend commits unless the user explicitly asks to amend one.
7. After every completed task, run the Lessons Learned Check (`.github/skills/lessons-learned-check.md`) and append only new, non-duplicate durable learnings to this file.
8. For implementation tasks, always create and work from a feature branch off latest `main` unless the user explicitly directs otherwise.
9. Never use `--force` / `--force-with-lease` on pushes unless the user explicitly requests a force push.


## Session Learnings — Shared Monitoring (LAW/AMPLS)

- `azurerm_monitor_private_link_scoped_service` is a child of the AMPLS resource. If AMPLS is in Management, scoped-service operations must use the Management provider/subscription context.
- With centralized monitoring, infra pipeline identities need RBAC on shared Management resources (not just app/env resources). In practice this includes `Log Analytics Contributor` on `log-orion180-mgt` for diagnostic settings workflows that require `sharedKeys/action`.
- Environment shared-monitoring cleanup uses:
  - `log_analytics_config = null`
  - `ampls_config = null`
  - keep `existing_log_analytics_workspace_*` and `existing_ampls_*` pointing to Management resources
- Log Analytics is centralized: all diagnostics and flow logs must target the shared Management LAW (`log-orion180-mgt`), not per-environment LAW resources.
- Keep guardrails in place to prevent accidental reintroduction of environment-created LAW/AMPLS configuration.
- AMPLS health triage should check all three layers before changing Terraform: (1) AMPLS scoped resources include app insights + LAW, (2) Azure Monitor private DNS A records exist (`privatelink.monitor/oms/ods/agentsvc`), and (3) VNet links for hub + spokes are completed.
- Even with correct AMPLS/DNS wiring, telemetry visibility can lag due to private DNS propagation/eventual consistency; short-lived gaps may self-recover without config changes.
- In App Insights, end-to-end transaction diagnostics are available for successful requests too (not only failures): use **Search** or **Performance** and drill into a request operation.

## Session Learnings — AFD Cache Purge (Build 133967)

- In `Orion180.DocumentSolutions` deploy flow, `Purge AFD Cache` can run much longer than expected: one attempt stalled and hit the default ~60-minute Azure DevOps timeout, while a later attempt completed in ~32 minutes for the first endpoint purge.
- A long/stuck purge here is likely runtime/platform latency in `az afd endpoint purge` (with `/*`) rather than YAML control-flow issues.
- The purge step currently has no explicit timeout override, so default job timeout is the practical failure boundary.
- Pipeline logs show the `afd` command group deprecation warning (move to `cdn` extension); migrate this command path to reduce future risk.

## Session Learnings — ACR Build Subscription Context

- `az acr build` is a control-plane operation and resolves the ACR resource in the active subscription context; if the service connection defaults to a different subscription, builds fail with registry-not-found even when `az acr login`/`docker push` previously worked.
- For shared ACR usage across app pipelines, pass an explicit `acrSubscriptionId` to the Docker build template and run `az account set --subscription "$ACR_SUBSCRIPTION_ID"` before ACR commands.

## Session Learnings — ACR Build RBAC

- `az acr build` needs control-plane task permissions on the registry; `Container Registry Repository Writer` alone is not enough.
- Least-privilege role set for CI image builders is: `Container Registry Repository Writer` (content push) + `Container Registry Tasks Contributor` (build/task execution) scoped to the ACR resource.
- In environments using constrained `Role Based Access Control Administrator` ABAC conditions, adding a new assignable role (like `Container Registry Tasks Contributor`) also requires updating the allowlisted RoleDefinitionIds in the ABAC condition; otherwise `Microsoft.Authorization/roleAssignments/write` fails with 403 AuthorizationFailed.
- `az acr build` can still fail after successful auth/queueing if the build agent cannot reach a private base image in ACR; the failure shows up as a data-plane firewall denial on the `FROM` pull, not an RBAC error.
- ACR task-agent-pool subnet delegation `Microsoft.ContainerRegistry/registries` is rejected by both `azurerm` validation and Azure Network RP apply (`InvalidServiceNameOnDelegation`); use a non-delegated subnet for ACR agent pools.
- Azure Pipelines redacts service-connection secrets in logs, so `servicePrincipalId` echoed via `AzureCLI@2` + `addSpnToEnvironment` appears as `***`; use non-secret identifiers (for example Entra service principal object ID queried at runtime) for diagnosable output.
- ACR task builds may not run with BuildKit features enabled; Dockerfile instructions like `COPY --chmod=...` can fail under `az acr build` and should be rewritten to BuildKit-independent syntax.

## Session Learnings — Terraform Module Git Refs (Azure DevOps)

- Terraform module `source` refs for Azure DevOps Git should use branch/tag names directly (for example, `?ref=feature/my-branch` or `?ref=4.1.0`), not full Git ref paths like `refs/heads/...`.
