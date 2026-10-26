#!/bin/bash
# Double-click installer (macOS): same as `bash install.sh --yes`. Only the Mac password is asked (once).
cd "$(dirname "$0")" || exit 1
bash install.sh --yes
echo
read -r -p "Done. Press Return to close this window. "
