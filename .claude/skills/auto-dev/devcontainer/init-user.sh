#!/bin/bash
# Fix ownership of volume-mounted directories, then drop to autodev user
chown -R autodev:autodev /var/auto-dev /home/autodev/.claude 2>/dev/null || true
exec su -s /bin/bash autodev -c "/usr/local/bin/auto-dev-entrypoint.sh"
