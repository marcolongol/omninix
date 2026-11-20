# omninix-info's text output, from its JSON (omninix-info --json).

def version: if .revision == null then "unknown" else .revision + (if .date == null then "" else " (\(.date))" end) end;
def age: if .date == null then "" else ", \((now - (.date + "T00:00:00Z" | fromdateiso8601)) / 86400 | floor) days old" end;
def list: if length == 0 then "none" else map(tostring) | join(", ") end;

"\(.host)  \(.system)  kernel \(.kernel)  stateVersion \(.stateVersion)",
"config   \(.config | version)",
"omninix  \(.omninix)",
(.inputs.nixpkgs // empty | "nixpkgs  \(version)\(age)"),
(select(.generation != null) | "gen      \(.generation), switched \(.switched)"
  + (if .rebootNeeded == null then "" elif .rebootNeeded then "  reboot needed" else "  no reboot needed" end)),
"roles    \(.roles | list)",
(.users | to_entries[] | "user     \(.key)"
  + (if .value.groups == [] then "" else " (\(.value.groups | list))" end)
  + "  profiles: \(.value.profiles | list)"),
(select(.ports.tcp != [] or .ports.udp != []) | "ports    tcp: \(.ports.tcp | list)  udp: \(.ports.udp | list)"),
(select(.secrets != []) | "secrets  \(.secrets | list)")
