# Offloads nix builds to a separate, more powerful machine (an Arch
# desktop, 192.168.8.16, i7-14700F/28 threads/62GB RAM) over SSH --
# deliberately NOT running Nix on that machine's actual host OS (kept
# entirely inside a Docker container there instead, per its owner's
# preference), just a plain SSH-reachable Nix daemon as far as this
# config is concerned. The configured address is a LAN address; remote
# access requires a route to that LAN (for example a Tailscale subnet
# router). Merely enabling Tailscale does not make this address reachable.
#
# The SSH key was generated specifically for this (not this user's
# regular key) -- private half lives at ~/.ssh/nix-remote-builder,
# never committed; only the path is referenced here.
{ ... }:
{
  # Was off for a while in favor of build-nix.nu's hand-picked
  # "heavy" package list -- that was a workaround for the remote
  # box's limited disk, not a preference: distributed builds send
  # *everything* Nix needs to build (including, it turns out, whole
  # dependency cascades from a single low-level patch -- e.g.
  # powerdevil rebuilding because it's built against plasma-workspace,
  # which is built against kwin, which is built against libinput),
  # not just a hardcoded list, which is what "heavy" mode couldn't do
  # and why it kept silently falling back to full local rebuilds.
  # Re-enabled on the understanding that the disk-space side needs
  # its own fix (see the remote-gc entry -- TODO once decided) rather
  # than staying off indefinitely.
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
