#!/bin/sh

# SPDX-FileCopyrightText: SAP SE or an SAP affiliate company and Gardener contributors
#
# SPDX-License-Identifier: Apache-2.0

set -e

# sync authorized keys (mounted file) into git's home
if [ -f /authorized_keys ]; then
  install -o git -g git -m 600 /authorized_keys /home/git/.ssh/authorized_keys
fi

# initialize bare repositories
git config --global init.defaultBranch main
for repo_name in ${REPO_NAMES:-}; do
  repo_path="/srv/git/${repo_name}"
  if [ ! -d "$repo_path" ]; then
    git init --bare "$repo_path"
    echo "Initialized bare repo at $repo_path"
  fi
done

# fix permissions
chown -R git:git /srv/git /home/git

# start sshd (non-daemon; PID 1)
exec /usr/sbin/sshd -D -e
