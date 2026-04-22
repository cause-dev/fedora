#!/usr/bin/env bash
set -euo pipefail

# 1. Read the "install" array from the recipe
get_json_array INSTALL_LIST 'try .["install"][]' "$1"

echo "Configuring System Extensions for: ${INSTALL_LIST[*]}"

# 2. Setup tmpfiles to ensure /var directories exist on every boot
mkdir -p /usr/lib/tmpfiles.d
cat <<EOF > /usr/lib/tmpfiles.d/sysext.conf
d /var/lib/extensions     0755 root root  -   -
d /var/lib/extensions.d   0755 root root  -   -
EOF

# 3. Create sysupdate configurations for each app in the list
for APP in "${INSTALL_LIST[@]}"; do
    mkdir -p "/etc/sysupdate.${APP}.d"
    cat <<EOF > "/etc/sysupdate.${APP}.d/${APP}.conf"
[Transfer]
Verify=false

[Source]
Type=url-file
Path=https://extensions.fcos.fr/community/
Name=${APP}.raw.xz

[Target]
Type=extensions-directory
Path=/var/lib/extensions
EOF
done

# 4. Generate the 'sysext-mgr' CLI tool
# We pass the list of apps directly into the script
cat <<EOF > /usr/bin/sysext-mgr
#!/bin/bash
APPS=(${INSTALL_LIST[*]})

case "\$1" in
    install)
        echo "Installing listed extensions: \${APPS[*]}"
        for app in "\${APPS[@]}"; do
            sudo /usr/lib/systemd/systemd-sysupdate update --component "\$app"
        done
        sudo systemctl restart systemd-sysext.service
        sudo update-desktop-database /usr/share/applications
        ;;
    update)
        echo "Updating all system extensions..."
        for c in \$(/usr/lib/systemd/systemd-sysupdate components --json=short | jq --raw-output '.components[]'); do
            sudo /usr/lib/systemd/systemd-sysupdate update --component "\$c"
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

# 5. Enable the systemd-sysext service
# This creates the symlink in the image so it starts on boot
systemctl enable systemd-sysext.service