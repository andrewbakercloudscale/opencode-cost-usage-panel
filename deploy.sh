#!/usr/bin/env bash
# Deploy the OpenCode panel installer to this machine.
#
# There's no remote server here — the installer already writes straight to
# ~/.local/bin, ~/.zshrc and ~/.config/ghostty/config, so "deploy" means "run
# the installer again to pick up the latest script changes." It's idempotent
# (see README's "Idempotent" note), so re-running after every edit is safe.
#
# Usage:
#   bash deploy.sh

set -euo pipefail

main() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  echo "==> Deploying OpenCode panel..."
  bash "$dir/opencode-panel-setup.sh"

  echo
  echo "Deploy complete."
}

main "$@"
