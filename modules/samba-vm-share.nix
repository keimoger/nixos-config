{ ... }:
{
  systemd.tmpfiles.rules = [
    "d /home/keimoger/vm-share 0750 keimoger users -"
  ];

  services.samba = {
    enable = true;
    openFirewall = false;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "keibook";
        security = "user";
        "map to guest" = "never";
        "interfaces" = "virbr0 127.0.0.1";
        "bind interfaces only" = "yes";
      };

      vm-share = {
        path = "/home/keimoger/vm-share";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "keimoger";
        "force user" = "keimoger";
        "create mask" = "0660";
        "directory mask" = "0770";
      };
    };
  };

  # Permit SMB only on libvirt's private NAT bridge, not on the LAN/Wi-Fi.
  networking.firewall.interfaces.virbr0.allowedTCPPorts = [ 445 ];
}
