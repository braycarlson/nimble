set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-c"]

bin := home_directory() / ".local/bin"
release := justfile_directory() / "zig-out/release"
units := env("XDG_CONFIG_HOME", home_directory() / ".config") / "systemd/user"

[doc('Compile every artifact without running it')]
check:
    zig build check

[doc('Compile every artifact for Linux from any host')]
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu

[doc('Compile every artifact for Windows from any host')]
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu

[doc('Run the continuous integration pipeline')]
ci:
    zig build ci
    zig build test:unit -Doptimize=safe

[doc('Check a Linux host: just drill <probe|scan|synthesis|observe|grab>')]
drill *arguments:
    zig build drill -- {{ arguments }}

[doc('Check that killing the drill releases every grab')]
[unix]
drill-kill:
    zig build drill -- grab &
    sleep 2
    pkill -f "zig-out/bin/drill" || true
    sleep 1
    zig build drill -- scan

[doc('Build and run an example: just example [name]')]
example name="simple":
    zig build run-{{ name }}

[doc('Format build.zig, the examples, and every source file')]
fmt:
    zig fmt build.zig examples src

[doc('Run a fuzzer: just fuzz <fuzzer> [seed] [events]')]
fuzz *arguments:
    zig build fuzz -- {{ arguments }}

[doc('Build a release, install the daemon and its user service, and restart the service on the new build')]
[linux]
install:
    zig build --release=safe --prefix '{{ release }}'
    id -nG "$USER" | grep -qw input || { sudo usermod -aG input "$USER"; echo "nimble: sign out and back in for the input group, then run just install again"; exit 1; }
    [ "$(stat -c %G:%a /dev/uinput)" = input:660 ] || { sudo install -D -m 644 contrib/systemd/99-nimble-uinput.rules /etc/udev/rules.d/99-nimble-uinput.rules && sudo udevadm control --reload-rules && sudo udevadm trigger --sysname-match=uinput; }
    install -D -m 755 '{{ release }}/bin/nimbled' '{{ bin }}/nimbled.new'
    mv -f '{{ bin }}/nimbled.new' '{{ bin }}/nimbled'
    install -D -m 644 contrib/systemd/nimbled.service '{{ units }}/nimbled.service'
    systemctl --user daemon-reload
    systemctl --user enable nimbled.service
    systemctl --user restart nimbled.service
    sleep 2
    systemctl --user is-active nimbled.service

[doc('Lint build.zig, the examples, and every source file with tigerstyle-lsp')]
lint:
    tigerstyle-lsp check build.zig examples src --format concise

[default]
[doc('List every recipe')]
list:
    @just --list

[doc('Run every test suite and the format check')]
test:
    zig build test

[doc('Run the end to end tests against the fake backend: just test-fake [filter]')]
test-fake filter="":
    zig build test:fake {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run the Linux backend tests on a Linux host: just test-linux [filter]')]
test-linux filter="":
    zig build test:linux {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run the unit tests and the tidy check: just test-unit [filter]')]
test-unit filter="":
    zig build test:unit {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run the Windows backend tests on a Windows host: just test-windows [filter]')]
test-windows filter="":
    zig build test:windows {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}
