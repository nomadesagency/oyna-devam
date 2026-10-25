#!/bin/bash
# Double-click uninstaller (macOS): same as `bash uninstall.sh`.
cd "$(dirname "$0")" || exit 1
bash uninstall.sh
echo
read -r -p "Done. Press Return to close this window. "
