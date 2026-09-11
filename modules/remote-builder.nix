# Offloads nix builds to a separate, more powerful machine (an Arch
# desktop, 192.168.8.16, i7-14700F/28 threads/62GB RAM) over SSH --
# deliberately NOT running Nix on that machine's actual host OS (kept
# entirely inside a Docker container there instead, per its owner's
# preference), just a plain SSH-reachable Nix daemon as far as this
# config is concerned. Works whether reached over the LAN directly or
# via Tailscale while away, since Tailscale negotiates a direct
# peer-to-peer path automatically when both ends are already on the
# same LAN -- same address either way, no conditional config needed.
#
# The SSH key was generated specifically for this (not this user's
# regular key) -- private half lives at ~/.ssh/nix-remote-builder,
# never committed; only the path is referenced here.
{ ... }:
{
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      # There's no dedicated port field on this submodule (checked the
      # actual nixpkgs module source) -- but setting protocol="ssh"
      # here makes NixOS write this as a real ssh:// URI to
      # /etc/nix/machines (not a bare user@host positional argument),
      # and ssh:// URIs support a :port suffix natively, so it's
      # embedded directly in hostName instead of needing a separate
      # ~/.ssh/config entry.
      protocol = "ssh";
      hostName = "192.168.8.16:2222";
      sshUser = "builder";
      sshKey = "/home/keimoger/.ssh/nix-remote-builder";
      systems = [ "x86_64-linux" ];
      maxJobs = 8;
      speedFactor = 2;
    }
  ];
}
