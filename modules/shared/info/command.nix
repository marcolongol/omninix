# The omninix-info command, in callPackage form. `info` is the host's half
# (omninix.info.data, from default.nix); what only the running machine knows
# is read when the command runs: the generation and when it was switched to,
# the running kernel, whether a reboot is due.
#
# `omninix-info` prints text (info.jq); `omninix-info --json` the merged JSON.
{
  writeShellApplication,
  writeText,
  coreutils,
  jq,
  info,
}:
writeShellApplication {
  name = "omninix-info";
  runtimeInputs = [coreutils jq];
  text = ''
    format=(-r -f ${./info.jq})
    if [ "''${1:-}" = --json ]; then
      format=(.)
    fi

    # The system profile's current link, e.g. system-142-link. Its own
    # mtime (not its target's, which is 1970) is when it was made.
    profiles=/nix/var/nix/profiles
    generation=null
    switched=null
    if [ -L "$profiles/system" ]; then
      link=$(readlink "$profiles/system")
      generation=''${link#system-}
      generation=''${generation%-link}
      switched="\"$(date -d "@$(stat -c %Y "$profiles/$link")" '+%Y-%m-%d %H:%M')\""
    fi

    # NixOS only: a reboot is due when the booted kernel, initrd or modules
    # aren't the current ones.
    reboot=null
    if [ -e /run/booted-system ]; then
      reboot=false
      for part in kernel initrd kernel-modules; do
        if [ "$(readlink -f /run/booted-system/$part)" != "$(readlink -f /run/current-system/$part)" ]; then
          reboot=true
        fi
      done
    fi

    jq \
      --argjson generation "$generation" \
      --argjson switched "$switched" \
      --argjson reboot "$reboot" \
      --arg kernel "$(uname -r)" \
      '. + {generation: $generation, switched: $switched, rebootNeeded: $reboot, kernel: $kernel}' \
      ${writeText "omninix-info.json" (builtins.toJSON info)} \
      | jq "''${format[@]}"
  '';
}
