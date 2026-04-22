#!/usr/bin/env bash
set -euo pipefail

# 1. Read the list of apps from the recipe
get_json_array INSTALL_LIST 'try .["install"][]' "$1"

echo "Setting up System Extension configs for: ${INSTALL_LIST[*]}"

# 2. Initialization: Ensure /var folders are created on boot
mkdir -p /usr/lib/tmpfiles.d
cat <<EOF > /usr/lib/tmpfiles.d/sysext.conf
d /var/lib/extensions     0755 root root  -   -
d /var/lib/extensions.d   0755 root root  -   -
EOF

# 3. Configuration: Create the .transfer file for each app
for APP in "${INSTALL_LIST[@]}"; do
    mkdir -p "/etc/sysupdate.${APP}.d"
    # Using .transfer extension as suggested by systemd v257+
    cat <<EOF > "/etc/sysupdate.${APP}.d/${APP}.transfer"
[Transfer]
Verify=false

[Source]
Type=url-file
Path=https://extensions.fcos.fr/community/${APP}/
MatchPattern=${APP}-@v-%w-%a.raw

[Target]
InstancesMax=2
Type=regular-file
Path=/var/lib/extensions.d/
MatchPattern=${APP}-@v-%w-%a.raw
CurrentSymlink=/var/lib/extensions/${APP}.raw
EOF
done

# 4. Activation: Enable the merging service
systemctl enable systemd-sysext.service

# 5. The CLI Tool: Updated with your specific update loop
cat <<EOF > /usr/bin/sysext-mgr
#!/bin/bash
# List of apps from build-time
APPS=(${INSTALL_LIST[*]})

case "\$1" in
    install)
        echo "Installing listed extensions: \${APPS[*]}"
        for app in "\${APPS[@]}"; do
            echo "--- Pulling \$app ---"
            sudo /usr/lib/systemd/systemd-sysupdate update --component "\$app"
        done
        echo "Restarting merge service..."
        sudo systemctl restart systemd-sysext.service
        sudo update-desktop-database /usr/share/applications || true
        ;;
    update)
        echo "Checking for updates for all components..."
        # Your specific loop using jq to iterate through registered components
        for c in \$(/usr/lib/systemd/systemd-sysupdate components --json=short | jq --raw-output '.components[]'); do
            echo "Checking component: \$c"
            sudo /usr/lib/systemd/systemd-sysupdate update --component "\$c"
        done
        echo "Refreshing merges..."
        sudo systemctl restart systemd-sysext.service
        ;;
    status)
        systemd-sysext status
        ;;
    *)
        echo "Usage: sysext-mgr {install|update|status}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/bin/sysext-mgr