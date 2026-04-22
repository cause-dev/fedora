#!/usr/bin/env bash
set -euo pipefail

# 1. Read both lists from the recipe
get_json_array COMMUNITY_LIST 'try .["community"][]' "$1"
get_json_array FEDORA_LIST 'try .["fedora"][]' "$1"

# Combine them for the CLI tool tracker
ALL_APPS=("${COMMUNITY_LIST[@]}" "${FEDORA_LIST[@]}")

echo "Setting up System Extension configs..."
echo "Community: ${COMMUNITY_LIST[*]}"
echo "Fedora: ${FEDORA_LIST[*]}"

# 2. Initialization: Ensure /var folders are created on boot
mkdir -p /usr/lib/tmpfiles.d
cat <<EOF > /usr/lib/tmpfiles.d/sysext.conf
d /var/lib/extensions     0755 root root  -   -
d /var/lib/extensions.d   0755 root root  -   -
EOF

# 3. Helper function to generate .transfer files
generate_sysupdate_config() {
    local APP=$1
    local TYPE=$2 # "community" or "fedora"
    
    mkdir -p "/etc/sysupdate.${APP}.d"
    cat <<EOF > "/etc/sysupdate.${APP}.d/${APP}.transfer"
[Transfer]
Verify=false

[Source]
Type=url-file
Path=https://extensions.fcos.fr/${TYPE}/${APP}/
MatchPattern=${APP}-@v-%w-%a.raw

[Target]
InstancesMax=2
Type=regular-file
Path=/var/lib/extensions.d/
MatchPattern=${APP}-@v-%w-%a.raw
CurrentSymlink=/var/lib/extensions/${APP}.raw
EOF
}

# 4. Generate configs for both types
for APP in "${COMMUNITY_LIST[@]}"; do
    generate_sysupdate_config "$APP" "community"
done

for APP in "${FEDORA_LIST[@]}"; do
    generate_sysupdate_config "$APP" "fedora"
done

# 5. Activation
systemctl enable systemd-sysext.service

# 6. The CLI Tool
cat <<EOF > /usr/bin/sysext-mgr
#!/bin/bash
APPS=(${ALL_APPS[*]})

case "\$1" in
    install)
        echo "Installing listed extensions: \${APPS[*]}"
        for app in "\${APPS[@]}"; do
            echo "--- Pulling \$app ---"
            sudo /usr/lib/systemd/systemd-sysupdate update --component "\$app"
        done
        sudo systemctl restart systemd-sysext.service
        mkdir -p ~/.local/share/applications
        update-desktop-database ~/.local/share/applications || true
        ;;
    update)
        echo "Checking for updates for all components..."
        for c in \$(/usr/lib/systemd/systemd-sysupdate components --json=short | jq --raw-output '.components[]'); do
            echo "Checking component: \$c"
            sudo /usr/lib/systemd/systemd-sysupdate update --component "\$c"
        done
        sudo systemctl restart systemd-sysext.service
        ;;
    remove)
        APP=\$2
        if [ -z "\$APP" ]; then echo "Usage: sysext-mgr remove <app>"; exit 1; fi
        echo "Removing \$APP..."
        sudo rm -f "/var/lib/extensions/\${APP}.raw"
        sudo rm -f /var/lib/extensions.d/\${APP}-*.raw
        sudo systemctl restart systemd-sysext.service
        echo "Done. \$APP has been unmerged and deleted."
        ;;
    prune)
        echo "Cleaning up orphaned extensions..."
        # Check every symlink in /var/lib/extensions
        for link in /var/lib/extensions/*.raw; do
            [ -e "\$link" ] || continue
            filename=\$(basename "\$link" .raw)
            # If no config exists in /etc/sysupdate.d, it's an orphan
            if [ ! -d "/etc/sysupdate.\${filename}.d" ]; then
                echo "Removing orphan: \$filename"
                sudo rm -f "\$link"
                sudo rm -f /var/lib/extensions.d/\${filename}-*.raw
            fi
        done
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