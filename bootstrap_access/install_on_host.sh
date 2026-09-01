#!/usr/bin/env bash
# Runs the encoded PowerShell key-install script (install_keys.ps1, base64
# UTF-16LE via encode_ps_command.py) against one managed host over SSH,
# piping the desired key set in on stdin.
#
# Usage: install_on_host.sh <inventory_name> <ssh_user> <ssh_host> <encoded_command>
#
# Output is redirected to a per-host log instead of being captured by
# Ansible: the target's console locale may not be UTF-8, and Ansible
# refuses to deserialize a non-UTF-8 module response. The exit code is
# passed straight through from install_keys.ps1: 0 = already up to date,
# 77 = it updated the file, anything else = a real error (see that
# script for why it can't just print a message instead).

set -uo pipefail

inventory_name=$1
ssh_user=$2
ssh_host=$3
encoded_command=$4
log_file="/tmp/bootstrap_access_install-${inventory_name}.log"

ssh -o StrictHostKeyChecking=accept-new \
    "${ssh_user}@${ssh_host}" \
    powershell -NoProfile -NonInteractive -EncodedCommand "${encoded_command}" \
    > "${log_file}" 2>&1
