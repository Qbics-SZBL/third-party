#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./manage_backup_branches.sh init [TARGET]
  ./manage_backup_branches.sh check [TARGET]
  ./manage_backup_branches.sh update [TARGET]
  ./manage_backup_branches.sh push [TARGET]
  ./manage_backup_branches.sh merge [TARGET]
  ./manage_backup_branches.sh list

TARGET:
USAGE
  printf '  %s\n' "$(target_usage)"
  cat <<'USAGE'

Commands:
  init    Create configured backup/* branches whose exact branch names do not exist.
  check   Fetch each configured upstream ref and report whether backup/* is current.
  update  Fast-forward the selected backup/* branch to its configured upstream ref.
  push    Push the selected local backup/* branch to the configured push remote.
  merge   On main, sync the selected backup/* tree into third-party/<name> and commit.
USAGE
  printf '\nKnown backup branches:\n'
  print_records
}

die() {
  echo "error: $*" >&2
  exit 1
}

run_git() {
  printf 'Running: git' >&2
  printf ' %q' -C "${repo_root}" "$@" >&2
  printf '\n' >&2
  git -C "${repo_root}" "$@"
}

# Columns: short|backup_branch|remote|remote_url|upstream_ref|vendor_prefix|submodule_policy
backup_prefix="backup/"
push_remote="gh"
records=(
  "dftd3|backup/dftd3-lib|dftd3-lib|https://github.com/dftbplus/dftd3-lib.git|main|third-party/dftd3-lib|skip"
  "dbcsr|backup/dbcsr|dbcsr|https://github.com/cp2k/dbcsr.git|develop|third-party/dbcsr|skip"
  "libxs|backup/libxs|libxs|https://github.com/hfp/libxs.git|main|third-party/libxs|skip"
)

target_usage() {
  local record short branch remote url ref prefix submodule_policy shorts backups other_branches
  shorts=()
  backups=()
  other_branches=()
  for record in "${records[@]}"; do
    IFS='|' read -r short branch remote url ref prefix submodule_policy <<<"${record}"
    shorts+=("${short}")
    if [[ "${branch}" == "${backup_prefix}"* ]]; then
      backups+=("${branch#"${backup_prefix}"}")
    else
      other_branches+=("${branch}")
    fi
  done
  local short_targets backup_targets other_targets output
  short_targets="$(join_by ' | ' "${shorts[@]}")"
  output="all | ${short_targets}"
  if [[ "${#backups[@]}" -gt 0 ]]; then
    backup_targets="$(join_by ',' "${backups[@]}")"
    output+=" | ${backup_prefix}{${backup_targets}}"
  fi
  if [[ "${#other_branches[@]}" -gt 0 ]]; then
    other_targets="$(join_by ' | ' "${other_branches[@]}")"
    output+=" | ${other_targets}"
  fi
  printf '%s\n' "${output}"
}

join_by() {
  local delimiter="$1"
  shift
  local output=""
  local item
  for item in "$@"; do
    if [[ -z "${output}" ]]; then
      output="${item}"
    else
      output+="${delimiter}${item}"
    fi
  done
  printf '%s\n' "${output}"
}

selected_records() {
  local target="${1:-all}"
  local short branch remote url ref prefix submodule_policy
  for record in "${records[@]}"; do
    IFS='|' read -r short branch remote url ref prefix submodule_policy <<<"${record}"
    if [[ "${target}" == "all" || "${target}" == "${short}" || "${target}" == "${branch}" ]]; then
      printf '%s\n' "${record}"
    fi
  done
}

require_known_target() {
  local target="${1:-all}"
  [[ "${target}" == "all" ]] && return 0
  [[ -n "$(selected_records "${target}")" ]] || die "unknown backup branch '${target}'"
}

ensure_clean_tree() {
  local status
  status="$(run_git status --porcelain)"
  [[ -z "${status}" ]] || die "working tree is not clean"
}

ensure_remote() {
  local remote="$1"
  local url="$2"
  local current_url=""

  if current_url="$(run_git remote get-url "${remote}" 2>/dev/null)"; then
    if [[ "${current_url}" != "${url}" ]]; then
      die "remote '${remote}' exists with url '${current_url}', expected '${url}'"
    fi
  else
    echo "Adding remote ${remote}: ${url}"
    run_git remote add "${remote}" "${url}"
  fi
}

fetch_ref() {
  local remote="$1"
  local ref="$2"
  if ! run_git fetch --quiet "${remote}" "${ref}"; then
    die "failed to fetch ${remote}/${ref}"
  fi
  run_git rev-parse --verify FETCH_HEAD^{commit}
}

status_one() {
  local branch="$1"
  local upstream_commit="$2"
  local local_commit=""

  if local_commit="$(run_git rev-parse --verify "${branch}^{commit}" 2>/dev/null)"; then
    if [[ "${local_commit}" == "${upstream_commit}" ]]; then
      echo "current"
    elif run_git merge-base --is-ancestor "${local_commit}" "${upstream_commit}"; then
      echo "behind"
    elif run_git merge-base --is-ancestor "${upstream_commit}" "${local_commit}"; then
      echo "ahead"
    else
      echo "diverged"
    fi
  else
    echo "missing"
  fi
}

check_one() {
  local short="$1" branch="$2" remote="$3" url="$4" ref="$5" prefix="$6" submodule_policy="$7"
  local upstream_commit local_commit state

  ensure_remote "${remote}" "${url}"
  upstream_commit="$(fetch_ref "${remote}" "${ref}")"
  local_commit="$(run_git rev-parse --verify "${branch}^{commit}" 2>/dev/null || true)"
  state="$(status_one "${branch}" "${upstream_commit}")"

  printf '%-16s %-9s local=%s upstream=%s %s/%s -> %s\n' \
    "${branch}" \
    "${state}" \
    "${local_commit:0:12}" \
    "${upstream_commit:0:12}" \
    "${remote}" \
    "${ref}" \
    "${prefix}"
}

update_one() {
  local short="$1" branch="$2" remote="$3" url="$4" ref="$5" prefix="$6" submodule_policy="$7"
  local upstream_commit local_commit state current_branch

  ensure_remote "${remote}" "${url}"
  upstream_commit="$(fetch_ref "${remote}" "${ref}")"
  local_commit="$(run_git rev-parse --verify "${branch}^{commit}" 2>/dev/null || true)"
  state="$(status_one "${branch}" "${upstream_commit}")"

  case "${state}" in
    current)
      echo "${branch}: already current at ${upstream_commit:0:12}"
      ;;
    missing|behind)
      current_branch="$(run_git branch --show-current)"
      if [[ "${current_branch}" == "${branch}" ]]; then
        ensure_clean_tree
        run_git merge --ff-only "${upstream_commit}"
      else
        run_git update-ref "refs/heads/${branch}" "${upstream_commit}" ${local_commit:+"${local_commit}"}
      fi
      echo "${branch}: fast-forwarded to ${upstream_commit:0:12}"
      ;;
    ahead)
      die "${branch} is ahead of ${remote}/${ref}; refusing to move it backward"
      ;;
    diverged)
      die "${branch} diverged from ${remote}/${ref}; resolve manually"
      ;;
  esac
}

init_one() {
  local short="$1" branch="$2" remote="$3" url="$4" ref="$5" prefix="$6" submodule_policy="$7"
  local upstream_commit

  if run_git rev-parse --verify --quiet "${branch}^{commit}" >/dev/null; then
    echo "${branch}: already exists, skipping"
    return 0
  fi

  ensure_remote "${remote}" "${url}"
  upstream_commit="$(fetch_ref "${remote}" "${ref}")"
  run_git update-ref "refs/heads/${branch}" "${upstream_commit}"
  echo "${branch}: initialized at ${upstream_commit:0:12} from ${remote}/${ref}"
}

skip_submodule_gitlinks() {
  local branch="$1"
  local prefix="$2"
  local meta path mode full_path

  while IFS=$'\t' read -r meta path; do
    mode="${meta%% *}"
    [[ "${mode}" == "160000" ]] || continue
    full_path="${prefix}/${path}"
    run_git update-index --force-remove "${full_path}"
    rm -rf "${repo_root:?}/${full_path}"
    echo "${full_path}: skipped nested submodule"
  done < <(git -C "${repo_root}" ls-tree -r "${branch}")
}

merge_one() {
  local short="$1" branch="$2" remote="$3" url="$4" ref="$5" prefix="$6" submodule_policy="$7"
  local branch_commit current_branch before_commit after_commit

  current_branch="$(run_git branch --show-current)"
  [[ "${current_branch}" == "main" ]] || die "merge must be run on main, current branch is '${current_branch}'"
  ensure_clean_tree
  ensure_remote "${remote}" "${url}"
  branch_commit="$(run_git rev-parse --verify "${branch}^{commit}")"
  before_commit="$(run_git rev-parse --verify HEAD)"

  run_git rm -r --quiet --ignore-unmatch "${prefix}"
  run_git read-tree --prefix="${prefix}/" -u "${branch}"
  case "${submodule_policy}" in
    skip)
      skip_submodule_gitlinks "${branch}" "${prefix}"
      ;;
    follow)
      ;;
    *)
      die "unknown submodule policy '${submodule_policy}' for ${branch}"
      ;;
  esac

  if run_git diff --cached --quiet; then
    echo "${prefix}: already matches ${branch} at ${branch_commit:0:12}"
    return 0
  fi

  run_git commit \
    -m "Update ${prefix} from ${branch}" \
    -m "Sync ${prefix} to ${branch_commit}." \
    -m "Source: ${remote}/${ref} (${url})."
  after_commit="$(run_git rev-parse --verify HEAD)"
  echo "${prefix}: committed ${after_commit:0:12} on top of ${before_commit:0:12}"
}

push_one() {
  local short="$1" branch="$2" remote="$3" url="$4" ref="$5" prefix="$6" submodule_policy="$7"
  local local_commit

  run_git remote get-url "${push_remote}" >/dev/null 2>&1 || die "remote '${push_remote}' is not configured"
  local_commit="$(run_git rev-parse --verify "${branch}^{commit}")"
  run_git push "${push_remote}" "${branch}:${branch}"
  echo "${branch}: pushed ${local_commit:0:12} to ${push_remote}/${branch}"
}

print_records() {
  local short branch remote url ref prefix submodule_policy
  local record_format='%-16s %-14s %-10s %-42s %-9s -> %s\n'
  printf "${record_format}" "Branch" "Upstream" "Remote" "URL" "Submodule" "Vendor prefix"
  for record in "${records[@]}"; do
    IFS='|' read -r short branch remote url ref prefix submodule_policy <<<"${record}"
    printf "${record_format}" "${branch}" "${remote}/${ref}" "${remote}" "${url}" "${submodule_policy}" "${prefix}"
  done
}

list_records() {
  print_records
}

main() {
  local command="${1:-check}"
  local target="${2:-all}"
  local record short branch remote url ref prefix submodule_policy

  cd "${repo_root}"

  case "${command}" in
    -h|--help|help)
      usage
      return 0
      ;;
    init)
      require_known_target "${target}"
      ;;
    list)
      list_records
      return 0
      ;;
    check|update|push|merge)
      require_known_target "${target}"
      ;;
    *)
      usage >&2
      return 2
      ;;
  esac

  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    IFS='|' read -r short branch remote url ref prefix submodule_policy <<<"${record}"
    "${command}_one" "${short}" "${branch}" "${remote}" "${url}" "${ref}" "${prefix}" "${submodule_policy}"
  done < <(selected_records "${target}")
}

main "$@"
