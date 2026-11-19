#!/system/bin/sh

HID_GLOB='/sys/bus/hid/devices/0005:*'
HID_DRIVERS='/sys/bus/hid/drivers'
NEW_ID="$HID_DRIVERS/microsoft/new_id"
BOOT_MARKER='/dev/xbox_bt_rumble_ff_boot_id'
LIST="/dev/xbox_bt_rumble_ff_devices.$$"

cleanup() { rm -f "$LIST"; }
trap cleanup EXIT HUP INT TERM

fail() {
  echo "Xbox Rumble: ERROR: $*"
  exit 1
}

: > "$LIST" || fail 'cannot create the temporary device list.'

echo 'Connected Bluetooth HID devices:'
COUNT=0
for HID_PATH in $HID_GLOB; do
  [ -e "$HID_PATH" ] || continue
  HID_ID=${HID_PATH##*/}
  UEVENT="$HID_PATH/uevent"
  VIDPID=${HID_ID#0005:}
  VIDPID=${VIDPID%%.*}
  VENDOR=${VIDPID%%:*}
  PRODUCT=${VIDPID#*:}
  NAME=$(sed -n 's/^HID_NAME=//p' "$UEVENT" 2>/dev/null | head -n 1)
  UNIQUE=$(sed -n 's/^HID_UNIQ=//p' "$UEVENT" 2>/dev/null | head -n 1)
  DRIVER=$(basename "$(readlink -f "$HID_PATH/driver" 2>/dev/null)")
  [ -n "$NAME" ] || NAME=$(cat "$HID_PATH/name" 2>/dev/null)
  [ -n "$NAME" ] || NAME='(unnamed HID device)'
  [ -n "$UNIQUE" ] || UNIQUE="$HID_ID"

  SUPPORTED=no
  case "$HID_ID" in
    0005:045E:0B13.*) SUPPORTED=yes ;;
  esac

  COUNT=$((COUNT + 1))
  printf '%s|%s|%s|%s|%s\n' "$HID_ID" "$NAME" "$UNIQUE" "$DRIVER" "$SUPPORTED" >> "$LIST"
  if [ "$SUPPORTED" = yes ]; then
    printf ' %d) %s  VID:PID=%s:%s  driver=%s  address/id=%s  [supported]\n' \
      "$COUNT" "$NAME" "$VENDOR" "$PRODUCT" "${DRIVER:-unbound}" "$UNIQUE"
  else
    printf ' %d) %s  VID:PID=%s:%s  driver=%s  address/id=%s  [not supported by this module]\n' \
      "$COUNT" "$NAME" "$VENDOR" "$PRODUCT" "${DRIVER:-unbound}" "$UNIQUE"
  fi
done

[ "$COUNT" -gt 0 ] || fail 'no Bluetooth HID devices are connected.'

if [ ! -t 0 ]; then
  fail 'interactive input is unavailable. Open this module with Magisk App > Modules > Action.'
fi

printf 'Select a device number (or q to cancel): '
IFS= read -r CHOICE
case "$CHOICE" in
  q|Q|'') echo 'Xbox Rumble: cancelled.'; exit 0 ;;
  *[!0-9]*) fail 'please enter a listed number.' ;;
esac

ROW=$(sed -n "${CHOICE}p" "$LIST")
[ -n "$ROW" ] || fail 'selection is outside the list.'
OLD_IFS=$IFS
IFS='|'
read -r HID_ID NAME UNIQUE DRIVER SUPPORTED <<EOF
$ROW
EOF
IFS=$OLD_IFS

if [ "$SUPPORTED" != yes ]; then
  fail "$NAME ($HID_ID) is not supported. This module currently supports Xbox Series Bluetooth VID:PID 045e:0b13 only."
fi

HID_PATH="/sys/bus/hid/devices/$HID_ID"
[ -e "$HID_PATH" ] || fail 'the selected device disconnected; run Action again.'
DRIVER=$(basename "$(readlink -f "$HID_PATH/driver" 2>/dev/null)")

if [ "$DRIVER" = microsoft ]; then
  echo "Xbox Rumble: $NAME is already bound to microsoft."
  exit 0
fi

[ -e "$NEW_ID" ] || fail 'hid-microsoft driver is not available.'
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
if [ -z "$BOOT_ID" ] || [ "$(cat "$BOOT_MARKER" 2>/dev/null)" != "$BOOT_ID" ]; then
  echo '0005 045E 0B13 80' > "$NEW_ID" || fail 'could not register the Microsoft FF ID.'
  [ -n "$BOOT_ID" ] && echo "$BOOT_ID" > "$BOOT_MARKER"
fi

if [ "$DRIVER" = hid-generic ]; then
  echo "$HID_ID" > "$HID_DRIVERS/hid-generic/unbind" || fail 'could not unbind the selected device.'
fi

# new_id may probe the device as soon as it is unbound; avoid a duplicate bind.
DRIVER=$(basename "$(readlink -f "$HID_PATH/driver" 2>/dev/null)")
if [ "$DRIVER" != microsoft ]; then
  echo "$HID_ID" > "$HID_DRIVERS/microsoft/bind" 2>/dev/null || true
fi

DRIVER=$(basename "$(readlink -f "$HID_PATH/driver" 2>/dev/null)")
if [ "$DRIVER" = microsoft ]; then
  echo "Xbox Rumble: enabled for $NAME ($HID_ID)."
  echo 'Note: the dynamic ID is VID:PID-wide, so a future connection of another 045e:0b13 controller may also bind automatically until reboot.'
else
  [ -e "$HID_PATH" ] && echo "$HID_ID" > "$HID_DRIVERS/hid-generic/bind" 2>/dev/null
  fail 'could not bind the selected device to microsoft; restored hid-generic where possible.'
fi
