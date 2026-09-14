# Tailscale as a system service (tailscaled + the tailscale CLI).
{ pkgs, ... }:
{
  services.tailscale.enable = true;

  # Tailscale has no official Linux tray client (unlike Windows/macOS)
  # -- trayscale is the common community GTK one, talking to the local
  # tailscaled over its usual unix socket. System-wide XDG autostart
  # (rather than a home-manager one) since this is a single-user
  # machine and it keeps everything tailscale-related in one file.

  # Direct P2P connectivity (NAT traversal) between tailnet peers --
  # separate from, and complementary to, trustedInterfaces below (that
  # one only covers traffic already arriving over tailscale0; this
  # opens the actual UDP port tailscale's own protocol uses).
  services.tailscale.openFirewall = true;

  # No authKeyFile: generating one needs tailnet admin rights, which
  # this account doesn't have. Falls back to the normal interactive
  # flow instead -- `sudo tailscale up` opens a login URL to authorize
  # the device by hand, same as any regular user-invited machine.

  # tailscaled creates its own tailscale0 interface; without this,
  # NixOS's default-deny firewall would block traffic arriving over it
  # even after a successful `tailscale up`.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
