#!/bin/sh
# This script allows Flatpak VS Code to talk to the host Podman
exec flatpak-spawn --host podman "$@"