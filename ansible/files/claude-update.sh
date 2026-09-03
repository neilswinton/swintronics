#!/usr/bin/env bash
# Nightly unattended Claude Code update for the admin user's native install.
#
# Run by the claude-update.service/.timer systemd *user* units. Both those
# units and this script are deployed by ansible/playbooks/develop.yml —
# do not edit on the host, changes will be overwritten on the next run.
#
# The native installer keeps each release in ~/.local/share/claude/versions/
# and points ~/.local/bin/claude at the active one. `claude update` swaps that
# symlink, but already-running processes keep the version they launched with —
# so the long-lived Remote Control sessions (claude-rc*.service) have to be
# restarted to pick up a new release. That restart happens only when the
# version actually changed, so a no-op night never kills a live session.
#
# Failures exit non-zero; claude-update.service has OnFailure= wired to a
# Telegram alert. Everything else is journald: journalctl --user -u claude-update
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

# "2.1.259 (Claude Code)" -> "2.1.259"; empty if claude is missing/broken.
claude_version() {
    claude --version 2>/dev/null | awk '{print $1}'
}

before=$(claude_version)
if [[ -z "${before}" ]]; then
    echo "claude-update: no working claude on PATH (${HOME}/.local/bin/claude) — nothing to update." >&2
    exit 1
fi
echo "claude-update: current version ${before}"

# `claude update` is a no-op when already current. Don't trust its exit code
# on its own: compare versions afterwards so a non-zero exit that still
# updated (or a zero exit that silently did nothing) is reported accurately.
update_rc=0
claude update || update_rc=$?

after=$(claude_version)
if [[ -z "${after}" ]]; then
    echo "claude-update: claude is not runnable after 'claude update' (exit ${update_rc}) — install may be broken." >&2
    exit 1
fi

if [[ "${before}" == "${after}" ]]; then
    if (( update_rc != 0 )); then
        echo "claude-update: 'claude update' failed (exit ${update_rc}) and version is unchanged at ${after}." >&2
        exit 1
    fi
    echo "claude-update: already up to date at ${after}; leaving Remote Control sessions alone."
    exit 0
fi

echo "claude-update: updated ${before} -> ${after}"
if (( update_rc != 0 )); then
    echo "claude-update: note: 'claude update' exited ${update_rc} but the version did change; continuing."
fi

# Discover the Remote Control units rather than hardcoding them: this is a
# no-op on a machine that runs no RC sessions, and a third session added later
# is picked up without touching this script.
mapfile -t rc_units < <(
    systemctl --user list-unit-files --no-legend 'claude-rc*.service' 2>/dev/null | awk '{print $1}'
)

if (( ${#rc_units[@]} == 0 )); then
    echo "claude-update: no claude-rc*.service units on this machine; nothing to restart."
    exit 0
fi

restart_failed=0
for unit in "${rc_units[@]}"; do
    if ! systemctl --user is-active --quiet "${unit}"; then
        echo "claude-update: ${unit} is not active; skipping restart."
        continue
    fi
    echo "claude-update: restarting ${unit} onto ${after}..."
    if ! systemctl --user restart "${unit}"; then
        echo "claude-update: failed to restart ${unit}." >&2
        restart_failed=1
    fi
done

if (( restart_failed != 0 )); then
    exit 1
fi

echo "claude-update: done."
