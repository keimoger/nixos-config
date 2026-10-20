# Tailscale as a system service (tailscaled + the tailscale CLI).
{ pkgs, ... }:
{
  services.tailscale.enable = true;

  # Start Tailscale's built-in Linux tray client with every graphical user
  # session, so the tray icon does not depend on a one-off manual launch.
  environment.systemPackages = [ pkgs.tailscale ];
  systemd.user.services.tailscale-systray = {
    description = "Tailscale system tray client";
    after = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.tailscale}/bin/tailscale systray";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

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
