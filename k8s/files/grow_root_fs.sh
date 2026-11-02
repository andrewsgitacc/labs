#!/usr/bin/env bash
# Grow the partition, LVM volume and filesystem holding / to fill the (already
# enlarged) system disk. Used by tasks/grow_root_fs.yml; can also be run by hand:
#   sudo bash grow_root_fs.sh
# Prints "CHANGED" when / got bigger. Safe to re-run.
set -euo pipefail
SRC=$(findmnt -n -o SOURCE /)
if lvs "$SRC" >/dev/null 2>&1; then
  VG=$(lvs --noheadings -o vg_name "$SRC" | tr -d ' ')
  PV=$(pvs --noheadings -o pv_name -S vg_name="$VG" | head -1 | tr -d ' ')
else
  PV="$SRC"
fi
DISK=/dev/$(lsblk -no pkname "$PV")
PARTNUM=$(cat /sys/class/block/"$(basename "$PV")"/partition)
BEFORE=$(df -BG --output=size / | tail -1 | tr -d ' G')
# growpart exits 1 with NOCHANGE when the partition already fills the disk;
# any other failure is real and must stop the play.
set +e
GP_OUT=$(TMPDIR=/dev/shm growpart "$DISK" "$PARTNUM" 2>&1); GP_RC=$?
set -e
echo "growpart: $GP_OUT"
if [ "$GP_RC" -ne 0 ] && ! grep -q NOCHANGE <<<"$GP_OUT"; then
  echo "growpart failed (rc=$GP_RC)" >&2; exit 1
fi
if lvs "$SRC" >/dev/null 2>&1; then
  # LVM normally writes a metadata backup to /etc/lvm/{backup,archive} first,
  # which fails on a full root filesystem - skip it for this resize only.
  NOBACKUP='backup { backup=0 archive=0 }'
  pvresize --config "$NOBACKUP" "$PV"
  FREE=$(vgs --noheadings --units b --nosuffix -o vg_free "$VG" | tr -d ' ')
  if [ "$FREE" -gt 0 ]; then lvextend --config "$NOBACKUP" -r -l +100%FREE "$SRC"; fi
  vgcfgbackup "$VG" >/dev/null || true   # refresh the normal backup now there's room
else
  xfs_growfs /
fi
AFTER=$(df -BG --output=size / | tail -1 | tr -d ' G')
echo "root filesystem: ${BEFORE}G -> ${AFTER}G"
[ "$AFTER" -gt "$BEFORE" ] && echo CHANGED || true
