# omninix-info's text, from its JSON (omninix-info --json), for either
# renderer in command.nix. With `$part` "header": the title and subtitle
# lines; with "rows": one `label<TAB>value` line per row ("\t" for a gap).
# `$color` says whether to colour (output is a terminal, NO_COLOR unset).

def paint(code): if $color then "\u001b[\(code)m\(.)\u001b[0m" else . end;
def dim: paint("2");
def ok: paint("32");
def warn: paint("33");
def bad: paint("31");

def list: if length == 0 then ("none" | dim) else map(tostring) | join(", ") end;
def version: if .revision == null then ("unknown" | dim) else .revision + (if .date == null then "" else "  " + (.date | dim) end) end;
# How old an input is: yellow after a month, red after three.
def age:
  if .date == null then ""
  else ((now - (.date + "T00:00:00Z" | fromdateiso8601)) / 86400 | floor) as $days
    | "  " + ("\($days) days old" | if $days > 90 then bad elif $days > 30 then warn else dim end)
  end;
def row($name): $name + "\t" + .;
# Pad to $width ("" * 0 is null in jq, so not a repeat).
def pad($width): . + ([range($width - length)] | map(" ") | join(""));

if $part == "header" then
  .host,
  ([.system, "kernel \(.kernel)", "stateVersion \(.stateVersion)"] | join(" · "))
else
  (.config | version | row("config")),
  (.omninix | row("omninix")),
  (.inputs.nixpkgs // empty | "\(version)\(age)" | row("nixpkgs")),
  ([(select(.generation != null) | "gen \(.generation)", "switched \(.switched)"),
    (if .rebootNeeded == null then empty elif .rebootNeeded then "reboot needed" | warn else "✓ no reboot needed" | ok end)]
    | select(. != []) | join(" · ") | row("system")),
  "\t",
  (.roles | list | row("roles")),
  (if .users == {} then "none" | dim | row("users")
   else (.users | keys | map(length) | max) as $nameWidth
     | ([.users[].groups | join(", ") | length] | max) as $groupsWidth
     | .users | to_entries | to_entries[]
     | (if .key == 0 then "users" else "" end) as $label
     | .value
     | (.key | pad($nameWidth)) + "  "
       + (if $groupsWidth == 0 then "" else (.value.groups | join(", ") | pad($groupsWidth) | dim) + "  " end)
       + ("profiles" | dim) + " " + (.value.profiles | list)
     | row($label)
   end),
  (.ports | select(.tcp != [] or .udp != [])
    | [(select(.tcp != []) | "tcp \(.tcp | list)"), (select(.udp != []) | "udp \(.udp | list)")]
    | join(" · ") | row("ports")),
  (.secrets | select(. != []) | list | row("secrets"))
end
