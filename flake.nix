{
  description = "claude-kanban: unattended Claude task board (NixOS module for the PC)";

  # No inputs: the module uses the consuming system's pkgs.
  outputs =
    { self }:
    {
      nixosModules.default = import ./nix/module.nix;
    };
}
