# The omninix-info command, in callPackage form. `info` is the host's half
# (omninix.info.data, from default.nix); what only the running machine knows
# is read when the command runs: the generation and when it was switched to,
# the running kernel, whether a reboot is due.
#
# `omninix-info` prints text: info.jq makes the rows, drawn with gum when
# `fancy`, or by plain printf otherwise. `omninix-info --json` prints the
# merged JSON.
{
  lib,
  writeShellApplication,
  writeText,
  coreutils,
  jq,
  gum,
  info,
  fancy ? true,
}:
writeShellApplication {
  name = "omninix-info";
  runtimeInputs = [coreutils jq] ++ lib.optional fancy gum;
  text = ''
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

    data=$(jq \
      --argjson generation "$generation" \
      --argjson switched "$switched" \
      --argjson reboot "$reboot" \
      --arg kernel "$(uname -r)" \
      '. + {generation: $generation, switched: $switched, rebootNeeded: $reboot, kernel: $kernel}' \
      ${writeText "omninix-info.json" (builtins.toJSON info)})

    if [ "''${1:-}" = --json ]; then
      printf '%s\n' "$data"
      exit
    fi

    color=false
    if [ -t 1 ] && [ -z "''${NO_COLOR:-}" ]; then
      color=true
    fi
    text() { jq -r --argjson color "$color" --arg part "$1" -f ${./info.jq} <<<"$data"; }
    header=$(text header)
    rows=$(text rows)
    title=$(head -n 1 <<<"$header")
    subtitle=$(tail -n 1 <<<"$header")

    ${
      if fancy
      then ''
        # gum colours only for a terminal, and its output here goes to $(…):
        # tell it whether ours is one.
        if $color; then
          export CLICOLOR_FORCE=1
        else
          export NO_COLOR=1
        fi
        gum style --border rounded --border-foreground 6 --padding "0 1" \
          "$(gum style --bold --foreground 6 "$title")" \
          "$(gum style --faint "$subtitle")" \
          "" \
          "$(gum join --horizontal \
            "$(gum style --bold --padding "0 2 0 0" "$(cut -f 1 <<<"$rows")")" \
            "$(cut -f 2- <<<"$rows")")"
      ''
      else ''
        bold() { if $color; then printf '\e[1m%s\e[0m' "$1"; else printf '%s' "$1"; fi; }
        printf '%s\n%s\n\n' "$(bold "$title")" "$subtitle"
        # Split by hand: `read` would drop an empty label, tab being
        # whitespace to it.
        while IFS= read -r row; do
          label=''${row%%$'\t'*}
          value=''${row#*$'\t'}
          if [ -z "$label$value" ]; then
            echo
          else
            printf '  %s %s\n' "$(bold "$(printf '%-8s' "$label")")" "$value"
          fi
        done <<<"$rows"
      ''
    }
  '';
}
