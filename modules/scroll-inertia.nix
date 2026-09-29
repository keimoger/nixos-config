{ ... }:
{
  # Wheel-only kinetic scrolling. Touchpads remain on native libinput
  # gesture handling so no synthetic contacts can create phantom fingers.
  environment.etc."libinput/plugins/50-scroll-inertia.lua".source = ./scroll-inertia.lua;
}
