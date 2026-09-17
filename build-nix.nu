# Builds and switches this system's NixOS configuration.
#
# "remote" builds on the LAN builder box (copies the derivation over,
# builds there, copies the result back, then switches locally) -- the
# original behavior of this script, when it was build-remote.nu.
#
# "local" builds and switches right here instead, piped through `nom`
# (nix-output-monitor) for readable live progress instead of raw nix
# log spam.
#
# Usage:
#   nu build-nix.nu remote
#   nu build-nix.nu local

def main [mode: string] {
    if $mode == "remote" {
        build-remote
    } else if $mode == "local" {
        build-local
    } else {
        print $"Unknown mode: \"($mode)\" -- expected \"remote\" or \"local\""
        exit 1
    }
}

def build-remote [] {
    let remote_addr = '192.168.8.16'
    let remote_port = 2222
    let ssh_host = $"builder@($remote_addr)"
    let host = (hostname)

    let built_drv = (nix eval $".#nixosConfigurations.($host).config.system.build.toplevel.drvPath" --json | from json)

    nix copy --to ssh-ng://($ssh_host):($remote_port) $built_drv

    # Does the actual remote build, piped through nom for live, readable
    # progress -- internal-json is the log format nom itself parses. Its
    # result path isn't captured here: nom consumes the whole pipeline's
    # output for its own display, so anything piped through it can't
    # also be captured as a value in the same breath. The identical call
    # below re-runs against what's now a fully-built, cached derivation
    # to grab that path near-instantly instead, with nom out of the way.
    ssh $ssh_host -p $remote_port nix build --extra-experimental-features '"nix-command flakes"' --log-format internal-json -v $"($built_drv)^*" o+e>| nom --json

    let built_sys = ssh $ssh_host -p $remote_port nix build --print-out-paths --extra-experimental-features '"nix-command flakes"' $"($built_drv)^*"

    nix copy --from ssh-ng://($ssh_host):($remote_port) $built_sys

    nixos-rebuild --switch --flake . --sudo
}

def build-local [] {
    nixos-rebuild switch --flake . --sudo o+e>| nom
}
