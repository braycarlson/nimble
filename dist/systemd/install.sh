#!/usr/bin/env bash
# Install the nimble daemon and its client tools as systemd --user services so
# they start on graphical login and stop on logout. Idempotent: safe to re-run
# after a rebuild.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace="$(cd "$here/../../.." && pwd)"

bin_dir="$HOME/.local/bin"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

services=(nimbled.service locker.service mute.service deafen.service phantom.service)
binaries=(nimble/nimbled locker/locker mute/mute mute/deafen phantom/phantom)

echo "Installing binaries into $bin_dir"
mkdir -p "$bin_dir"

for entry in "${binaries[@]}"; do
    repository="${entry%%/*}"
    name="${entry##*/}"
    source="$workspace/$repository/zig-out/bin/$name"

    if [ ! -x "$source" ]; then
        echo "  $name is missing, build it with:"
        echo "    (cd $workspace/$repository && zig build -Doptimize=ReleaseSafe)"

        continue
    fi

    install -m 0755 "$source" "$bin_dir/$name"
    echo "  $name"
done

echo "Installing units into $unit_dir"
mkdir -p "$unit_dir"

for service in "${services[@]}"; do
    install -m 0644 "$here/$service" "$unit_dir/$service"
    echo "  $service"
done

echo "Reloading the user systemd manager"
systemctl --user daemon-reload

echo "Enabling services (they will start with graphical-session.target)"
systemctl --user enable "${services[@]}"

echo
echo "Verifying the daemon can reach /dev/uinput"
if [ -w /dev/uinput ]; then
    echo "  /dev/uinput is writable by this user"
else
    echo "  /dev/uinput is NOT writable. Install the udev rule (needs sudo):"
    echo "    sudo cp $here/99-nimble-uinput.rules /etc/udev/rules.d/"
    echo "    sudo udevadm control --reload-rules && sudo udevadm trigger /dev/uinput"
    echo "  and confirm you are in the input group: id -nG | grep -q input"
fi

echo
echo "Done. Start now without waiting for a re-login:"
echo "  systemctl --user start ${services[*]}"
echo "Status:      systemctl --user status nimbled.service"
echo "Logs:        journalctl --user -u nimbled.service -f"
echo "Disable all: systemctl --user disable --now ${services[*]}"
