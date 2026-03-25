#!/usr/bin/env bash
set -euo pipefail

# 1. Change the default for all future users (Cleanest way)
echo "Setting default shell to fish for new users..."
sed -i 's|SHELL=/bin/bash|SHELL=/usr/bin/fish|' /etc/default/useradd

# 2. Create the "Smart Jump" in /etc/profile.d/
# This ensures existing users (like you) get fish on login 
# without breaking manual 'bash' commands.
echo "Creating global shell-jump for existing users..."
cat > /etc/profile.d/active-fish.sh <<'EOF'
if [[ $- == *i* && $SHLVL -eq 1 && -z "$FISH_VERSION" ]]; then
    if [ -x /usr/bin/fish ]; then
        export SHELL=/usr/bin/fish
        exec /usr/bin/fish
    fi
fi
EOF

chmod +x /etc/profile.d/active-fish.sh