#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
if [[ -f "$project_dir/.env.release.local" ]]; then
  source "$project_dir/.env.release.local"
fi
exec /usr/bin/python3 "$project_dir/Scripts/release.py" "$@"
