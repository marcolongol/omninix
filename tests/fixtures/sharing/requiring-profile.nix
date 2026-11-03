# Sharing fixture: a Home Manager piece that needs a module nobody imports.
{
  omninix.requirements = [
    {
      by = "profiles.requiring";
      option = "programs.notImported";
      module = "a missing Home Manager module";
    }
  ];
}
