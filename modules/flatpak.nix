{ ... }:
{
  # Flatpak is used for upstream desktop builds whose bundled runtime is
  # more complete than the Nix package (for example OrcaSlicer nightly).
  services.flatpak.enable = true;
}
