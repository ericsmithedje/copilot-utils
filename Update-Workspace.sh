#!/usr/bin/env bash

set -uo pipefail

default_branch="main"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
workspace_path="$script_dir"
force_delete=false
dry_run=false

summary_repos=()
summary_branches=()
summary_pulled=()
summary_deleted=()
summary_warnings=()

cyan=$'\033[0;36m'
dark_cyan=$'\033[0;36m'
yellow=$'\033[0;33m'
dark_yellow=$'\033[0;33m'
dark_gray=$'\033[0;90m'
reset=$'\033[0m'

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Updates all git repositories in the workspace to the latest '$default_branch'
and prunes stale local branches.

Options:
  -p, --path <dir>    Workspace root (default: script directory)
  -f, --force         Use -D for branch deletions
  -n, --dry-run       Show what would be deleted without deleting branches
      --whatif        Alias for --dry-run
  -h, --help          Show this help
EOF
}

write_section() {
    local text="$1"
    echo
    printf '%b\n' "${dark_cyan}======================================================================${reset}"
    printf '%b\n' "${cyan}${text}${reset}"
    printf '%b\n' "${dark_cyan}======================================================================${reset}"
}

warn() {
    printf '%b\n' "${dark_yellow}WARNING: $*${reset}" >&2
}

test_working_tree_clean() {
    local status
    status="$(git status --porcelain)"
    [[ -z "$status" ]]
}

join_lines() {
    local -n arr_ref="$1"
    if ((${#arr_ref[@]} == 0)); then
        echo ""
        return
    fi
    printf '%s\n' "${arr_ref[@]}"
}

append_summary() {
    local repo="$1"
    local current_branch="$2"
    local pulled="$3"
    local deleted_text="$4"
    local warning_text="$5"

    summary_repos+=("$repo")
    summary_branches+=("${current_branch:-}")
    summary_pulled+=("$pulled")
    summary_deleted+=("$deleted_text")
    summary_warnings+=("$warning_text")
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            -p|--path)
                if (($# < 2)); then
                    echo "Error: $1 requires a value" >&2
                    usage
                    exit 1
                fi
                workspace_path="$2"
                shift 2
                ;;
            -f|--force)
                force_delete=true
                shift
                ;;
            -n|--dry-run|--whatif)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Error: unknown option '$1'" >&2
                usage
                exit 1
                ;;
        esac
    done
}

process_repo() {
    local repo_name="$1"
    local repo_path="$2"
    local old_pwd="$PWD"
    local current_branch=""
    local pulled="false"
    local -a deleted_branches=()
    local -a warnings=()

    write_section "$repo_name"

    if ! cd "$repo_path"; then
        warnings+=("Failed to enter repository")
        append_summary "$repo_name" "$current_branch" "$pulled" "$(join_lines deleted_branches)" "$(join_lines warnings)"
        return
    fi

    printf '%b\n' "${dark_gray}Fetching...${reset}"
    if ! git fetch --all --prune --quiet; then
        warnings+=("git fetch failed")
    elif ! git show-ref --verify --quiet "refs/remotes/origin/$default_branch"; then
        warnings+=("origin/$default_branch not found; skipping")
        warn "origin/$default_branch not found in $repo_name; skipping."
    else
        current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

        if ! test_working_tree_clean; then
            warnings+=("Working tree dirty on '$current_branch'; skipped checkout/pull/cleanup")
            warn "Working tree has uncommitted changes; skipping."
        else
            if [[ "$current_branch" != "$default_branch" ]]; then
                printf '%b\n' "${dark_gray}Switching from '$current_branch' to '$default_branch'...${reset}"
                if ! git checkout "$default_branch" --quiet; then
                    warnings+=("Failed to checkout '$default_branch'")
                    warn "Failed to checkout '$default_branch' in $repo_name."
                else
                    current_branch="$default_branch"
                fi
            fi

            if [[ "$current_branch" == "$default_branch" ]]; then
                printf '%b\n' "${dark_gray}Fast-forwarding $default_branch...${reset}"
                if git merge --ff-only "origin/$default_branch" --quiet; then
                    pulled="true"
                else
                    warnings+=("Fast-forward failed (diverged from origin/$default_branch)")
                fi

                mapfile -t local_branches < <(git for-each-ref --format='%(refname:short)|%(upstream:track)' refs/heads/)
                local line name track reason merge_base branch_tip flag use_force
                for line in "${local_branches[@]}"; do
                    [[ -z "$line" ]] && continue

                    name="${line%%|*}"
                    if [[ "$line" == *"|"* ]]; then
                        track="${line#*|}"
                    else
                        track=""
                    fi

                    [[ "$name" == "$default_branch" ]] && continue
                    [[ "$name" == "$current_branch" ]] && continue

                    reason=""
                    if [[ "$track" == *"[gone]"* ]]; then
                        reason="upstream gone"
                    else
                        merge_base="$(git merge-base "$name" "$default_branch" 2>/dev/null || true)"
                        branch_tip="$(git rev-parse "$name" 2>/dev/null || true)"
                        if [[ -n "$merge_base" && -n "$branch_tip" && "$merge_base" == "$branch_tip" ]]; then
                            reason="merged"
                        fi
                    fi

                    [[ -z "$reason" ]] && continue

                    use_force="false"
                    if [[ "$force_delete" == "true" || "$reason" == "upstream gone" ]]; then
                        use_force="true"
                    fi
                    flag="-d"
                    if [[ "$use_force" == "true" ]]; then
                        flag="-D"
                    fi

                    if [[ "$dry_run" == "true" ]]; then
                        printf '%b\n' "${yellow}  [dry-run] Delete branch '$name' ($reason)${reset}"
                    elif git branch "$flag" "$name" >/dev/null 2>&1; then
                        deleted_branches+=("$name ($reason)")
                        printf '%b\n' "${yellow}  Deleted $name [$reason]${reset}"
                    else
                        warnings+=("Failed to delete $name ($reason); use --force")
                        warn "Failed to delete $name; rerun with --force to force-delete."
                    fi
                done
            fi
        fi
    fi

    cd "$old_pwd" || true
    append_summary "$repo_name" "$current_branch" "$pulled" "$(join_lines deleted_branches)" "$(join_lines warnings)"
}

parse_args "$@"

if [[ ! -d "$workspace_path" ]]; then
    echo "Error: path does not exist: $workspace_path" >&2
    exit 1
fi

repos_found=0
shopt -s nullglob
for repo_path in "$workspace_path"/*; do
    [[ -d "$repo_path" ]] || continue
    [[ -d "$repo_path/.git" ]] || continue

    repo_name="$(basename "$repo_path")"
    repos_found=1
    process_repo "$repo_name" "$repo_path"
done
shopt -u nullglob

if [[ "$repos_found" -eq 0 ]]; then
    warn "No git repositories found under $workspace_path"
    exit 0
fi

write_section "Summary"
for i in "${!summary_repos[@]}"; do
    repo="${summary_repos[$i]}"
    current="${summary_branches[$i]}"
    pulled="${summary_pulled[$i]}"
    status="no-change"
    if [[ "$pulled" == "true" ]]; then
        status="updated"
    fi

    printf '%-45s [%s] on=%s\n' "$repo" "$status" "${current:-}"

    while IFS= read -r d; do
        [[ -z "$d" ]] && continue
        printf '%b\n' "${yellow}    - deleted: $d${reset}"
    done <<< "${summary_deleted[$i]}"

    while IFS= read -r w; do
        [[ -z "$w" ]] && continue
        printf '%b\n' "${dark_yellow}    ! $w${reset}"
    done <<< "${summary_warnings[$i]}"
done
