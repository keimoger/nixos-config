{ pkgs, ... }:
{
  users.users."keimoger" = {
    isNormalUser = true;
    description = "Kei Moger";
    shell = pkgs.nushell;
    extraGroups = [
      "networkmanager"
      "wheel"
      "input"
      "uinput"
      "dialout"
    ];
    packages = with pkgs; [
      telegram-desktop
      spotify
      google-chrome
      thunderbird
      claude-code
      pkgs.orca-slicer
      bitwarden-desktop
      vscode
    ];
  };

  hardware.uinput.enable = true;
  users.groups.uinput = { };

  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", MODE="0666", TAG+="uaccess"
  '';
}
