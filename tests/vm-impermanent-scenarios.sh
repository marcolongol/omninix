#!/usr/bin/env bash
# Runs the generated rollback-root script against loopback btrfs images and
# asserts each scenario's outcome. Usage: vm-impermanent-scenarios.sh <plain> <override>
set -u
PLAIN=$1 OVERRIDE=$2
W=/root/work
mkdir -p "$W/fakebin"
FAILED=/run/rollback-root.failed
REAL_BTRFS=$(command -v btrfs)
cat >"$W/fakebin/btrfs" <<FAKE
#!/usr/bin/env bash
if [[ "\$1" == subvolume && "\$2" == create ]]; then echo "fake: create failed" >&2; exit 1; fi
exec $REAL_BTRFS "\$@"
FAKE
chmod +x "$W/fakebin/btrfs"
ERRORS=0

setup() {
  IMG=$W/$1.img
  rm -f "$IMG"
  truncate -s 1G "$IMG"
  mkfs.btrfs -q -f "$IMG" >/dev/null
  LOOP=$(losetup -f --show "$IMG")
  M=$W/m-$1
  mkdir -p "$M"
  mount -o subvolid=5 "$LOOP" "$M"
  rm -f "$FAILED"
}
mkroot() {
  btrfs subvolume create "$M/root" >/dev/null
  echo r >"$M/root/marker"
}
mkdata() {
  btrfs subvolume create "$M/nix" >/dev/null
  echo n >"$M/nix/marker"
  btrfs subvolume create "$M/persist" >/dev/null
  echo p >"$M/persist/marker"
}
mkarch() {
  mkdir -p "$M/old_roots"
  btrfs subvolume create "$M/old_roots/$1" >/dev/null
  btrfs subvolume create "$M/old_roots/$1/nested" >/dev/null
  touch -d "$2 days ago" "$M/old_roots/$1"
}
# run <script> [sed-expr] [PATH]
run() {
  local s=$W/run.sh
  { echo 'set -e'; sed "s|/dev/disk/by-label/nixos|$LOOP|g${2:+;$2}" "$1"; } >"$s"
  umount "$M"
  PATH=${3:-$PATH} unshare -m --propagation private bash "$s" >"$W/out.txt" 2>&1
  RC=$?
  mount -o subvolid=5 "$LOOP" "$M"
}
teardown() {
  umount "$M"
  losetup -d "$LOOP"
  rm -f "$IMG"
}
expect() {
  if eval "$2"; then echo "  ok   $1"; else
    echo "  FAIL $1"
    sed 's/^/       /' "$W/out.txt"
    ERRORS=$((ERRORS + 1))
  fi
}
data_intact() { [[ -f $M/nix/marker && -f $M/persist/marker ]]; }
fresh_root() { [[ -d $M/root && ! -e $M/root/marker ]]; }

echo "S1 healthy: root archived, fresh root, aged archive pruned, recent kept"
setup s1; mkroot; mkdata; mkarch aged 40; mkarch recent 1
run "$PLAIN"
expect "exit 0" '[[ $RC == 0 ]]'
expect "fresh root" fresh_root
expect "nix and persist intact" data_intact
expect "aged archive pruned" '[[ ! -e $M/old_roots/aged ]]'
expect "recent archive kept" '[[ -d $M/old_roots/recent ]]'
expect "previous root archived" '[[ -n $(find "$M/old_roots" -maxdepth 2 -name marker) ]]'
expect "no failure flag" '[[ ! -e $FAILED ]]'
teardown

echo "S2 no root and a stale old_roots (old_roots must not match itself)"
setup s2; mkdata; mkdir -p "$M/old_roots"; touch -d "40 days ago" "$M/old_roots"
run "$PLAIN"
expect "exit 0" '[[ $RC == 0 ]]'
expect "root created" '[[ -d $M/root ]]'
expect "nix and persist intact" data_intact
teardown

echo "S3 plain directory in old_roots (only subvolumes are pruned)"
setup s3; mkroot; mkdata; mkdir -p "$M/old_roots/keep"; touch -d "40 days ago" "$M/old_roots/keep"
run "$PLAIN"
expect "exit 0" '[[ $RC == 0 ]]'
expect "nix and persist intact" data_intact
expect "plain directory left alone" '[[ -d $M/old_roots/keep ]]'
teardown

echo "S4 archive name collision"
setup s4; mkroot; mkdata
ts=$(date --date="@$(stat -c %Y "$M/root")" "+%Y-%m-%d_%H:%M:%S")
mkdir -p "$M/old_roots"; btrfs subvolume create "$M/old_roots/$ts" >/dev/null; echo old >"$M/old_roots/$ts/existing"
run "$PLAIN"
expect "exit 0" '[[ $RC == 0 ]]'
expect "existing archive untouched" '[[ -f $M/old_roots/$ts/existing && ! -e $M/old_roots/$ts/root ]]'
expect "new archive under a unique name" '[[ -f $M/old_roots/$ts.1/marker ]]'
teardown

echo "S5 subvolume create fails: previous root restored, flagged"
setup s5; mkroot; mkdata
run "$PLAIN" "" "$W/fakebin:$PATH"
expect "exit non-zero" '[[ $RC != 0 ]]'
expect "previous root restored" '[[ -f $M/root/marker ]]'
expect "nix and persist intact" data_intact
expect "failure flag written" '[[ -e $FAILED ]]'
teardown

echo "S6 wipe.device override on a different device: nothing touched, flagged"
setup s6; mkroot; mkdata
OTHER_IMG=$W/other.img; truncate -s 300M "$OTHER_IMG"; mkfs.btrfs -q -f "$OTHER_IMG" >/dev/null
OTHER=$(losetup -f --show "$OTHER_IMG")
run "$OVERRIDE" "s|/dev/disk/by-label/other|$OTHER|g"
expect "exit non-zero" '[[ $RC != 0 ]]'
expect "root untouched" '[[ -f $M/root/marker && ! -e $M/old_roots ]]'
expect "failure flag written" '[[ -e $FAILED ]]'
losetup -d "$OTHER"; rm -f "$OTHER_IMG"
teardown

echo "S7 wipe.device override resolving to the root device: wipes"
setup s7; mkroot; mkdata
run "$OVERRIDE" "s|/dev/disk/by-label/other|$LOOP|g"
expect "exit 0" '[[ $RC == 0 ]]'
expect "fresh root" fresh_root
expect "nix and persist intact" data_intact
teardown

if [[ $ERRORS != 0 ]]; then
  echo "$ERRORS check(s) failed"
  exit 1
fi
echo "all scenarios passed"
