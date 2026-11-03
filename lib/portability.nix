# OmniNix portability check
#
# Proves a flake's exported pieces (roles, profiles, nixosModules, homeModules)
# work in someone else's flake: no flake inputs or other OmniNix extras, no
# personal values, inert until enabled, and readable errors when a required
# module is missing. Receives the extended-lib fixpoint `final`.
{final}: let
  inherit (final) attrNames concatMap filter filterAttrs genAttrs hasSuffix mapAttrs' nameValuePair optional optionals;

  # Module args only OmniNix (or a flake's own wiring) provides.
  bannedArgs = ["inputs" "self" "secretsPath" "hostName" "users" "profiles" "homeManagerModules" "mkHomeModules"];

  nixosKinds = ["roles" "nixosModules"];
  homeKinds = ["profiles" "homeModules"];

  # `nfs-client` -> `nfsClient`, the convention for roles.<name>.enable.
  camel = name: let
    parts = filter builtins.isString (builtins.split "-" name);
  in
    builtins.head parts + final.concatMapStrings (p: final.toUpper (builtins.substring 0 1 p) + builtins.substring 1 (-1) p) (builtins.tail parts);

  # Every .nix file of a piece (a file, or a directory with default.nix).
  nixFiles = p:
    if builtins.readFileType p == "directory"
    then
      concatMap (
        n: let
          t = (builtins.readDir p).${n};
        in
          if t == "directory"
          then nixFiles (p + "/${n}")
          else optional (t == "regular" && hasSuffix ".nix" n) (p + "/${n}")
      ) (attrNames (builtins.readDir p))
    else [p];

  matches = re: text: builtins.length (builtins.split re text) > 1;

  # Text lint: [label regex]. Applies to every file; `home` adds osConfig.
  codeRules = [
    ["reads specialArgs indirectly (_module.specialArgs/_module.args)" "_module\\.(specialArgs|args)"]
    ["fetches at eval time (builtins.fetch*/getFlake)" "builtins\\.(fetchTarball|fetchGit|fetchTree|getFlake)"]
    ["imports from internal/" "(\\./|/)internal/"]
  ];
  personalRules = [
    ["an email address" "[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\\.[A-Za-z.]{2,}"]
    ["a private IP address" "(^|[^0-9.])(10\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])|192\\.168\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])|172\\.(1[6-9]|2[0-9]|3[01])\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9]))([^0-9.]|$)"]
    ["a /home/<name> path" "(^|[^A-Za-z0-9_.-])/home/[a-z]"]
    ["key material" "(ssh-ed25519 AAAA|ssh-rsa AAAA|BEGIN PGP|age1[a-z0-9]{20,})"]
    ["coordinates" "-?[0-9]{1,3}\\.[0-9]{4,},[ ]*-?[0-9]{1,3}\\.[0-9]{4,}"]
  ];
in {
  # Build the portability checks for a flake's exported pieces
  #
  # Type: { inputs, system, pieces, ... } -> { <checkName> = derivation; }
  #
  # Parameters:
  #   inputs        - the flake's inputs (needs nixpkgs and home-manager)
  #   system        - system to evaluate on (Linux)
  #   pieces        - { roles, profiles, nixosModules, homeModules } to check
  #                   (a flake's exported outputs)
  #   requires      - modules a consumer must bring, per piece:
  #                   { roles.desktop = [stylix.nixosModules.stylix]; }
  #                   (NixOS modules for roles/nixosModules, HM for the rest)
  #   scenarios     - name -> { nixos ? {}; home ? {}; requires ? []; homeRequires ? []; }
  #                   deep evals with pieces enabled (sample values)
  #   exclude       - [ "roles.desktop" ... ] pieces not checked yet (warns)
  #   enableOptions - { modules.<name> = "programs.foo.enable"; } enable options
  #                   for the enabled-bare check; roles/profiles default to
  #                   roles.<camelName>.enable / profiles.<camelName>.enable
  #   allow         - strings the personal-value lint ignores
  #
  # Checks (each its own attr, so `nix build .#checks.<sys>.<name>` reproduces one):
  #   omninix-portable-static        args, indirect args, fetchers, internal/
  #                                  imports, personal values (text lint)
  #   omninix-portable-inert         all pieces imported, none enabled, no
  #                                  requires: identical to a bare host
  #   omninix-portable-<kind>-<n>    the piece alone with its requires
  #                                  (structural); never pulls in internal/
  #   omninix-portable-<kind>-<n>-enabled
  #                                  enabled without its requires: may fail an
  #                                  assertion, must not throw
  #   omninix-portable-scenario-<n>  deep eval of a scenario
  mkPortableCheck = {
    inputs,
    system,
    pieces,
    requires ? {},
    scenarios ? {},
    exclude ? [],
    enableOptions ? {},
    allow ? [],
  }:
    assert (inputs ? nixpkgs && inputs ? home-manager)
    || throw "omninix-portable: needs nixpkgs and home-manager inputs"; let
      pkgs = inputs.nixpkgs.legacyPackages.${system};

      # kind -> name -> path, minus exclusions.
      checked =
        final.warnIf (exclude != [])
        "OmniNix portable check: not checked yet: ${toString exclude}"
        (genAttrs (nixosKinds ++ homeKinds) (kind: filterAttrs (name: _: !(builtins.elem "${kind}.${name}" exclude)) (pieces.${kind} or {})));
      requiresOf = kind: name: requires.${kind}.${name} or [];

      poison = genAttrs bannedArgs (n: throw "omninix-portable: shared pieces must not take `${n}`; use an option instead");

      # OmniNix's own module gets its extras by closure, so pieces only ever see
      # the poisoned ones. The named formals make the module system pass them.
      omninixModule = homePieces: {
        config,
        lib,
        options,
        pkgs,
        ...
      } @ args:
        import ../modules/nixos (args
          // {
            inputs = {};
            hostName = "portable";
            users = {};
            secretsPath = null;
            profiles = homePieces;
            homeManagerModules = {};
            inherit (final.omninix) mkHomeModules;
          });

      base = {lib, ...}: {
        boot.isContainer = true;
        system.stateVersion = "26.05";
        networking.hostName = "portable";
        nixpkgs.config.allowUnfree = true;
        omninix.hostUsers.probe.enable = true;
        users.users.probe.hashedPassword = "!";
        home-manager.extraSpecialArgs = lib.mkForce poison;
        home-manager.users.probe.home.stateVersion = "26.05";
      };

      host = {
        nixosPieces ? [],
        homePieces ? {},
        modules ? [],
      }:
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = poison;
          modules = [(omninixModule homePieces) inputs.home-manager.nixosModules.home-manager base] ++ nixosPieces ++ modules;
        };

      bareHost = host {};

      # Standalone Home Manager: no NixOS around it (so no osConfig), and its
      # `options` show what a piece declares.
      standaloneHome = modules:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = poison;
          modules =
            [
              ../modules/home
              {
                home.username = "probe";
                home.homeDirectory = "/home/probe";
                home.stateVersion = "26.05";
              }
            ]
            ++ modules;
        };

      # A no-op derivation when there are no problems; otherwise evaluation fails
      # with all of them listed.
      report = name: problems:
        if problems == []
        then pkgs.runCommandLocal name {} "touch $out"
        else throw "omninix-portable (${name}):\n  - ${final.concatStringsSep "\n  - " problems}";

      # Forces evaluation, assertions included (which also runs the module
      # system's unknown-option check).
      structural = cfg: builtins.deepSeq (map (a: a.assertion) cfg.config.assertions) true;
      toplevel = cfg: cfg.config.system.build.toplevel.drvPath;

      # --- static ---------------------------------------------------------
      staticProblems = concatMap (
        kind:
          concatMap (
            name:
              concatMap (
                file: let
                  v = import file;
                  args = optionals (builtins.isFunction v) (attrNames (builtins.functionArgs v));
                  bad = filter (a: builtins.elem a (bannedArgs ++ optional (builtins.elem kind homeKinds) "osConfig")) args;
                  text = builtins.readFile file;
                  cleaned = builtins.replaceStrings allow (map (_: "") allow) text;
                  where = "${kind}.${name}: ${toString file}";
                  rules = codeRules ++ optional (builtins.elem kind homeKinds) ["reads osConfig (absent in standalone Home Manager)" "osConfig"];
                in
                  map (a: "${where} takes `${a}`") bad
                  ++ concatMap (r: optional (matches (builtins.elemAt r 1) text) "${where} ${builtins.head r}") rules
                  ++ concatMap (r: optional (matches (builtins.elemAt r 1) cleaned) "${where} contains ${builtins.head r}") personalRules
              ) (nixFiles checked.${kind}.${name})
          ) (attrNames checked.${kind})
      ) (nixosKinds ++ homeKinds);

      # --- inert ----------------------------------------------------------
      allHost = modules:
        host {
          nixosPieces = concatMap (k: final.attrValues checked.${k}) nixosKinds;
          homePieces = checked.profiles // final.mapAttrs' (n: v: nameValuePair "module-${n}" v) checked.homeModules;
          inherit modules;
        };
      inertProblems = optional (toplevel (allHost []) != toplevel bareHost) "importing every piece without enabling any changes the system; something isn't gated on its enable option";

      # --- per piece ------------------------------------------------------
      pieceHost = kind: name: extra: let
        piece = checked.${kind}.${name};
        req = requiresOf kind name;
      in
        if builtins.elem kind nixosKinds
        then host {nixosPieces = [piece] ++ req ++ extra;}
        else
          host {
            homePieces.${name} = piece;
            modules = [{home-manager.sharedModules = req;}] ++ extra;
          };

      # Module graph is a tree (each entry's own imports nested under it).
      graphFiles = entries: concatMap (e: [(toString (e.file or e.key or ""))] ++ graphFiles (e.imports or [])) entries;
      internalImports = cfg: filter (final.hasInfix "/internal/") (graphFiles (cfg.graph or []));

      isolation = kind: name: let
        cfg = pieceHost kind name [];
        standalone = optionals (builtins.elem kind homeKinds) [(standaloneHome ([checked.${kind}.${name}] ++ requiresOf kind name))];
      in
        builtins.seq (structural cfg) (builtins.seq (map structural standalone) (map (f: "${kind}.${name} pulls in ${f}") (internalImports cfg)));

      enableOptionOf = kind: name:
        final.attrByPath [kind name] (
          if kind == "roles"
          then "roles.${camel name}.enable"
          else if kind == "profiles"
          then "profiles.${camel name}.enable"
          else null
        )
        enableOptions;

      # Enabled with no requires: assertions may fail (that's the readable
      # message a consumer gets), but evaluation itself must not throw.
      enabledBare = kind: name: let
        opt = enableOptionOf kind name;
        path = final.splitString "." opt;
        setting =
          if builtins.elem kind nixosKinds
          then final.setAttrByPath path true
          else {home-manager.users.probe = final.setAttrByPath path true;};
        cfg = host (
          if builtins.elem kind nixosKinds
          then {nixosPieces = [checked.${kind}.${name}] ++ [setting];}
          else {
            homePieces.${name} = checked.${kind}.${name};
            modules = [setting];
          }
        );
        ok = (builtins.tryEval (builtins.deepSeq (map (a: a.assertion) cfg.config.assertions) true)).success;
      in
        optional (hasEnableOption kind name && !ok) "${kind}.${name} enabled without its requires throws instead of failing an assertion (gate settings on `options ? x`, assert the requirement)";

      hasEnableOption = kind: name: let
        opt = enableOptionOf kind name;
        scope =
          if builtins.elem kind nixosKinds
          then (pieceHost kind name []).options
          else (standaloneHome ([checked.${kind}.${name}] ++ requiresOf kind name)).options;
      in
        final.hasAttrByPath (final.splitString "." opt) scope;

      perPiece = concatMap (
        kind:
          concatMap (
            name:
              [(nameValuePair "omninix-portable-${kind}-${name}" (report "${kind}-${name}" (isolation kind name)))]
              # Names never depend on evaluating a piece (an uncatchable error
              # there would hide every other result); -enabled passes when the
              # piece has no such option.
              ++ optional (enableOptionOf kind name != null) (nameValuePair "omninix-portable-${kind}-${name}-enabled" (report "${kind}-${name}-enabled" (enabledBare kind name)))
          ) (attrNames checked.${kind})
      ) (nixosKinds ++ homeKinds);

      # --- scenarios ------------------------------------------------------
      scenarioCheck = name: s: let
        cfg = allHost ([
            (s.nixos or {})
            {
              home-manager.users.probe.imports = [(s.home or {})];
              home-manager.sharedModules = s.homeRequires or [];
            }
          ]
          ++ (s.requires or []));
      in
        builtins.seq (toplevel cfg) (report "scenario-${name}" []);
    in
      {
        omninix-portable-static = report "static" staticProblems;
        omninix-portable-inert = report "inert" inertProblems;
      }
      // builtins.listToAttrs perPiece
      // mapAttrs' (n: s: nameValuePair "omninix-portable-scenario-${n}" (scenarioCheck n s)) scenarios;
}
