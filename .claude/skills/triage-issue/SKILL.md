---
name: triage-issue
description: Take a GitHub issue number and drive it through branch → changes → PR. Use when the user says `/triage-issue <num>`. Encodes the issue-to-PR discipline so the work is auditable: feature branch, scoped edits, PR linking back to the issue. Does NOT deploy — `/deploy-and-verify` is the manual deploy step after merge.
---

# Triage Issue

Drive a GitHub issue from triage to open PR. The user supplies an issue number; you do the rest.

## Preflight

1. Confirm `gh auth status` shows logged in.
2. Confirm clean working tree: `git status --porcelain` must be empty. If not, stop and ask the user — don't stash silently.
3. Confirm you're on `main` and up-to-date: `git fetch origin && git status -sb`. If behind, `git pull --ff-only`.

If any check fails, surface the exact issue and ask the user how to proceed. Don't reset, stash, or check out other branches without permission.

## Fetch the issue

```bash
gh issue view <num> --json number,title,body,labels,state
```

If `state` is not `OPEN`, stop and ask the user — they may have linked the wrong issue.

Read the body carefully. If it's vague or missing acceptance criteria, ask the user one targeted question before proceeding. A clearer scope at the start saves a wasted branch.

## Create the branch

Slug the title (lowercase, dashes, alphanumeric only, max 40 chars):

```bash
slug=$(echo "<title>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-40)
git checkout -b "issue-<num>-${slug}"
```

The pre-commit hook in `~/.claude/settings.json` will reject commits on `main` anyway, but creating the branch up front avoids any chance of stray edits landing wrong.

## Make the changes

Use the repo context: read `CLAUDE.md` for architecture, look at existing patterns under `ansible/services/<similar-service>/` or `terraform/` before writing new code. The repo conventions matter — prefer editing existing playbooks/templates over creating new ones.

Common shapes for this repo:

- **Version bump for a service** → edit `ansible/versions.yml`; if upstream compose changed, also diff `ansible/services/<svc>/upstream.yml` and update `compose.yml.j2` (see `feedback_upstream_diffs` memory).
- **New monitor / config tweak** → likely edits under `ansible/services/gatus/` (for Gatus endpoints) or per-service compose.
- **Terraform change** → edits under `terraform/`, run `terraform plan` locally before committing.
- **Backup or cron logic** → likely under `server-scripts/` plus rendering via `ansible/services/backup/backup.env.j2`.

Stay scoped to what the issue asks for. Don't refactor surrounding code or fix unrelated style issues — those belong in separate issues/PRs.

## Verify locally (skip what doesn't apply)

- Terraform changes: `cd terraform && terraform plan` (no apply).
- Ansible changes: `cd ansible && ansible-playbook playbooks/<relevant>.yml --check --diff` if you can reach the target. If not, at minimum run `ansible-playbook --syntax-check`.
- Compose template changes: `ansible-playbook playbooks/deploy-versions.yml --check --diff` to see what would render.

Don't promise the change works if you can't verify — call it out in the PR body.

## Commit and push

Show the diff to the user and ask for confirmation before committing. Then:

```bash
git add <specific-files>           # never `git add -A`
git commit -m "<short subject>

<body referencing the issue and the approach>

Closes #<num>
"
git push -u origin "issue-<num>-${slug}"
```

The pre-commit hook will block any attempt to commit on main or to bypass GPG signing — don't try to work around it. If signing fails, surface the error to the user instead of disabling signing.

## Open the PR

```bash
gh pr create \
  --title "<short, under 70 chars>" \
  --body "$(cat <<EOF
## Summary
<1–3 bullets on what changed>

## Why
<link to issue context; the issue's "why" is the PR's "why">

## Test plan
- [ ] <how to verify; usually \`/deploy-and-verify <service>\` after merge>

Closes #<num>
EOF
)"
```

Return the PR URL to the user.

## What this skill does *not* do

- Deploy. `/deploy-and-verify` is the post-merge step the user runs locally.
- Auto-merge. The PR sits open for human review.
- Skip review when the issue is "obviously simple." Always show the diff and confirm before committing.
- Touch unrelated code. If you spot adjacent issues, mention them in the PR body or as a follow-up issue, don't fold them in.
