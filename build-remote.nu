let remote_addr = '192.168.8.16'
let remote_port = 2222
let ssh_host = $"builder@($remote_addr)"
let host = (hostname)

let built_drv = (nix eval $".#nixosConfigurations.($host).config.system.build.toplevel.drvPath" --json | from json)

nix copy --to ssh-ng://($ssh_host):($remote_port) $built_drv

let built_sys = ssh $ssh_host -p $remote_port nix build --print-out-paths -Lv --extra-experimental-features '"nix-command flakes"' $"($built_drv)^*"

nix copy --from ssh-ng://($ssh_host):($remote_port) $built_sys

nixos-rebuild --switch --flake . --sudo

