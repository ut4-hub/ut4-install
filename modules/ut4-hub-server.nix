{ lib, ... }:
{
  # Stub. Real module implementation added in Task 11.
  options.services.ut4Hub = lib.mkOption {
    type = lib.types.attrs;
    default = { };
    description = "Stub; real module added in Task 11.";
  };
}
