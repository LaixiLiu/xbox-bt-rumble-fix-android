#!/system/bin/sh
# Xbox Bluetooth Rumble Fix - Magisk Action.
# Key-driven menu (Magisk's Action stdin is not a TTY on this device):
#   physical Volume-Up   = move to next device
#   physical Volume-Down = confirm selection
# Captured key codes on this Meizu unit:
#   physical Volume-Up   -> 0073
#   physical Volume-Down -> 0072

HID_GLOB='/sys/bus/hid/devices/0005:*'
HID_DRIVERS='/sys/bus/hid/drivers'
NEW_ID="$HID_DRIVERS/microsoft/new_id"
BOOT_MARKER='/dev/xbox_bt_rumble_ff_boot_id'
LIST="/dev/xbox_bt_rumble_ff_devices.$$"
MENU_TIMEOUT=90
VOL_SAVED=

cleanup() {
  rm -f "$LIST"
  [ -n "$VOL_SAVED" ] && settings put system volume_music "$VOL_SAVED" 2>/dev/null
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "Xbox Rumble: ERROR: $*"
  exit 1
}

# Wait for one volume-key press. Prints NEXT or CHOOSE; empty on timeout.
wait_key() {
  line=$(timeout "$1" getevent -q 2>/dev/null | grep -m1 -E '0001 007[23] 00000001$')
  [ -n "$line" ] || return 1
  code=$(echo "$line" | awk '{print $3}')
  case "$code" in
    0073) echo NEXT ;;
    0072) echo CHOOSE ;;
    *) return 1 ;;
  esac
}

VOL_SAVED=$(settings get system volume_music 2>/dev/null)

: > "$LIST" || fail 'cannot create the temporary device list.'

echo '=== Xbox Bluetooth Rumble Fix ==='
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

echo
echo '音量+ = 下一项    音量- = 确认    (90 秒无操作自动退出)'
echo

N=$COUNT
SEL=1
while :; do
  ROW=$(sed -n "${SEL}p" "$LIST")
  OLD_IFS=$IFS
  IFS='|'
  read -r HID_ID NAME UNIQUE DRIVER SUPPORTED <<EOF
$ROW
EOF
  IFS=$OLD_IFS

  MARK=''
  [ "$SUPPORTED" = yes ] && MARK='  [supported]'
  printf '> 选择: [%d/%d] %s  %s  driver=%s%s\n' \
    "$SEL" "$N" "$NAME" "$HID_ID" "${DRIVER:-unbound}" "$MARK"

  key=$(wait_key "$MENU_TIMEOUT") || { echo; echo '未检测到按键，退出。'; exit 0; }
  if [ "$key" = NEXT ]; then
    SEL=$(( SEL % N + 1 ))
    continue
  fi
  echo
  break
done

HID_PATH="/sys/bus/hid/devices/$HID_ID"
[ -e "$HID_PATH" ] || fail 'the selected device disconnected; run Action again.'

if [ "$SUPPORTED" != yes ]; then
  fail "$NAME ($HID_ID) is not supported. This module currently supports Xbox Series Bluetooth VID:PID 045e:0b13 only."
fi

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
