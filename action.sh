#!/system/bin/sh
MODDIR=${0%/*}
exec /system/bin/sh "$MODDIR/select_controller.sh"
