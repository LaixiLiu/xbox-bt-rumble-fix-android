# Xbox Bluetooth Rumble Fix (Magisk)

让 **Xbox Series X|S 蓝牙手柄**（VID:PID `045e:0b13`）在 Android 上恢复游戏驱动的震动。

部分 Android 内核会让 `hid-generic` 接管这个蓝牙 HID 设备：手柄输入正常，但游戏拿不到 FF（力反馈）能力，震动失效。内核自带的 `hid-microsoft` 驱动其实支持该型号的震动，本模块通过 Magisk Action 把手柄重新绑定到 `hid-microsoft`。

在魅族 21 / Flyme 12.6 / Android 16 / 内核 6.1.25 上开发验证。

## 原理

```
游戏 → Android 框架 FF → 内核 hid-microsoft（FF 驱动）
     → HID 输出报文 → 蓝牙 → 手柄马达
```

同一个蓝牙 HID 设备在内核里只能绑定一个 HID 驱动。默认绑在 `hid-generic`（无 FF）上；把 `045e:0b13` 注册进 `hid-microsoft` 的 `new_id` 并重新 bind 后，设备由带 FF 实现的 `hid-microsoft` 接管，框架下发的震动请求就能到达手柄。

`select_controller.sh` 做的事：

1. 枚举 `/sys/bus/hid/devices/0005:*`（蓝牙 HID），列出名称、VID:PID、当前驱动
2. 只允许选择 `045e:0b13`；每次开机第一次运行时向 `/sys/bus/hid/drivers/microsoft/new_id` 注册动态 ID `0005 045E 0B13 80`（用 `/dev/xbox_bt_rumble_ff_boot_id` 记录 boot_id，避免重复注册）
3. 把设备从 `hid-generic` unbind，再 bind 到 `microsoft`；失败时尽量恢复 `hid-generic`

## 文件

| 文件 | 说明 |
|---|---|
| `module.prop` | Magisk 模块信息（id `xbox_bt_rumble_ff`） |
| `action.sh` | Magisk Action 入口，转调 `select_controller.sh` |
| `select_controller.sh` | 音量键选择设备并重新绑定到 `hid-microsoft` |

纯 shell，无需编译，无后台服务，无 sepolicy 规则。

## 安装

```sh
# 打包（模块 zip 的根目录即本仓库内容）
zip -r ../xbox.zip module.prop action.sh select_controller.sh
adb push ../xbox.zip /data/local/tmp/
adb shell su -c "magisk --install-module /data/local/tmp/xbox.zip"
# 按 Magisk 提示重启一次，之后每次开机手动运行一次 Action
```

## 使用

Magisk → 模块 → Xbox Bluetooth Rumble Fix → 操作（Action）：

- 菜单会列出当前连接的所有蓝牙 HID 设备，标记是否受支持，并显示当前驱动
- **音量+ = 下一项，音量- = 确认**（Magisk 的 Action 终端在本机不支持交互输入）
- 选中受支持的 `045e:0b13` 后按音量-，脚本完成重新绑定并打印结果
- 菜单 90 秒无操作自动退出；退出时会恢复菜单期间改变的媒体音量

## 注意

- 动态 `new_id` 是 VID:PID 级别的：本次开机内，之后连接的同型号手柄会自动绑定到 `microsoft`
- 绑定不跨重启，每次开机后需要重新运行一次 Action
- 只支持 `045e:0b13`（Xbox Series X|S 蓝牙）；其他蓝牙 HID 设备会列出，但标记为 not supported
- 绑定后如果出现问题，可重启手机恢复，或手动把设备 bind 回 `hid-generic`

## 许可证

本项目以 **GNU General Public License v3.0** 发布，详见 [LICENSE](LICENSE)。
