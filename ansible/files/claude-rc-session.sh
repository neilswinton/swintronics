#!/usr/bin/env bash
# Keep a Claude Code Remote Control session alive; relaunch if it exits.
#
# Run inside a detached tmux server by the claude-rc*.service systemd *user*
# units. Both those units and this script are deployed by
# ansible/playbooks/develop.yml — do not edit on the host, changes will be
# overwritten on the next run.
#
# Usage: claude-rc-session.sh <session-label> <working-directory>
#
# One script serves every session: the label and working directory come from
# the unit, so adding a session is a claude_rc_sessions entry in host_vars
# rather than another near-identical copy of this file.
set -u

if (( $# != 2 )); then
    echo "usage: ${0##*/} <session-label> <working-directory>" >&2
    exit 64
fi

label=$1
workdir=$2

export PATH="${HOME}/.local/bin:${PATH}"

cd "${workdir}" || exit 1

# The loop is what makes a session durable: `claude --remote-control` returns
# when the session ends, including a clean /exit or a nightly restart by
# claude-update.sh. It does NOT return when the bridge fails to connect — the
# CLI stays up in a disconnected state — so the loop cannot recover a failed
# connect. That case is prevented in the unit instead, by waiting for the
# network before launching.
#
# --continue picks up the most recent conversation in ${workdir}, so a reboot or
# a nightly restart resumes where the session left off instead of opening a
# blank one. Two things follow from "most recent in this directory":
#   * it is not necessarily the previous *Remote Control* conversation — an
#     ad-hoc `claude` run in the same directory is newer and wins;
#   * with no conversation there at all it starts a fresh one rather than
#     failing, so this is safe on a first launch and cannot spin the loop.
while true; do
    claude --continue --remote-control "${label}"
    sleep 5
done
