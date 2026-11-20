# omninix-info: on every host unless turned off, with what OmniNix knows
# about the host (omninix.info.data). The command's runtime half is checked
# in the vm-host test.
{
  lib,
  inputs,
  evalHosts,
  ...
}: let
  # A role or profile named `name`, off until enabled.
  toggle = kind: name: {lib, ...}: {
    options.${kind}.${name}.enable = lib.mkEnableOption name;
  };

  host = extra:
    (evalHosts {
      roles = {
        web = toggle "roles" "web";
        idle = toggle "roles" "idle";
      };
      profiles = {
        git = toggle "profiles" "git";
        games = toggle "profiles" "games";
      };
      users.alice.profiles.git.enable = true;
      hosts.test = {
        imports = [extra];
        roles.web.enable = true;
        omninix.hostUsers.alice = {
          enable = true;
          extraGroups = ["wheel"];
        };
        users.users.alice.hashedPassword = "$y$fake";
        networking.firewall.allowedTCPPorts = [80];
      };
    })
    .test;

  hasInfo = config: lib.any (p: (p.name or "") == "omninix-info") config.environment.systemPackages;

  data = (host {}).omninix.info.data;

  # Whether the host's omninix-info script uses gum.
  usesGum = config: let
    command = lib.findFirst (p: (p.name or "") == "omninix-info") null config.environment.systemPackages;
  in
    lib.hasInfix "/bin/gum" command.drvAttrs.text || lib.hasInfix "-gum-" command.drvAttrs.text;
in {
  testInstalledByDefault = {
    expr = hasInfo (host {});
    expected = true;
  };

  testOptOut = {
    expr = let
      config = host {omninix.info.enable = false;};
    in {
      installed = hasInfo config;
      revision = config.system.configurationRevision;
    };
    expected = {
      installed = false;
      revision = null;
    };
  };

  # Fancy (gum) unless turned off; plain has no gum.
  testFancyByDefault = {
    expr = {
      fancy = usesGum (host {});
      plain = usesGum (host {omninix.info.fancy = false;});
    };
    expected = {
      fancy = true;
      plain = false;
    };
  };

  # Only what's on: roles and profiles that exist but are off aren't listed.
  testHostData = {
    expr = {
      inherit (data) host system roles users ports;
    };
    expected = {
      host = "test";
      system = "x86_64-linux";
      roles = ["web"];
      users.alice = {
        groups = ["wheel"];
        profiles = ["git"];
      };
      ports = {
        tcp = [80];
        udp = [];
      };
    };
  };

  # The config's revision (here, OmniNix's own checkout) is the system's
  # configurationRevision too.
  testRevisions = {
    expr = {
      config = data.config.revision == (inputs.self.shortRev or inputs.self.dirtyShortRev or null);
      configurationRevision = (host {}).system.configurationRevision == (inputs.self.rev or inputs.self.dirtyRev or null);
      nixpkgs = data.inputs.nixpkgs.revision == inputs.nixpkgs.shortRev;
    };
    expected = {
      config = true;
      configurationRevision = true;
      nixpkgs = true;
    };
  };
}
