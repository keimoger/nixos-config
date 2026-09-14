{ ... }:
{
  networking.hostName = "keibook";
  networking.networkmanager.enable = true;
  services.resolved.enable = true;

  # Was previously just a plain package install (modules/users.nix),
  # which pulled in the kdeconnect-kde binary and its daemon started
  # fine, but never opened the firewall ports it needs (1714-1764,
  # TCP+UDP -- one port per paired device, plus discovery) -- phones
  # and this laptop could each see their own daemon running, but
  # never each other. programs.kdeconnect.enable pulls in the same
  # package (still kdePackages.kdeconnect-kde, the default) and opens
  # exactly that range, together, so they can't drift out of sync.
  programs.kdeconnect.enable = true;

  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
}
