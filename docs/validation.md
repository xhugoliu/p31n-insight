# P31n 蓝牙遥测验证路线

目标是验证正常蓝牙打字与物理按键遥测共存，再检查计数、时长和重连。先在终端或 Probe 中证明事件准确，之后接入菜单栏、SQLite 和统计面板。

## 已验证的基础

Minix Insight 使用 QMK Raw HID 的矩阵事件。P31n 使用 ZMK `zmk_position_state_changed` 的位置、状态和设备时间戳，外部模块增加独立的加密 GATT 服务。Mac 原生程序通过 CoreBluetooth 接收事件，不从系统 HID 输出反推物理按键。

链路为：物理事件 → 非阻塞队列 → 独立发送线程 → BLE GATT → Mac 采集器 → SQLite 与统计。正常键盘输入继续使用原有蓝牙 HID 服务。

外部模块链接到 ZMK 的 `app`，在 combo、hold-tap 监听器之前采集，并返回 `ZMK_EV_EVENT_BUBBLE`。由于 combo 会重新派发部分位置事件，模块按位置、状态和原始时间戳去重。原始事件先去重，再分配遥测序号，避免把重派发误判为丢包。队列写入使用 `K_NO_WAIT`，蓝牙发送在独立的低优先级线程中执行。

## 不改固件的初步验证

1. P31n 固件启用 ZMK Studio 和其 BLE transport。
2. 拔掉 USB，用原生 macOS ZMK Studio 读取布局。
3. 保持连接，正常打字、并击和切层。

此步骤证明 HID 与 GATT 基本共存；不证明遥测计数准确。只读取，不保存 Studio 改键，避免覆盖日后通过 keymap 编译刷入的键位。Studio 不是正式应用的运行依赖。

## Probe 真机验收

先刷入支持遥测的 P31n 固件，退出其他采集程序和 Studio，拔掉 USB。在 Probe 中允许蓝牙权限，等待“蓝牙遥测已开启”。每项测试开始时松开所有键，用鼠标点击“重新计数”；测试结束后同样用鼠标点击“暂停”，避免操作快捷键污染计数。

| 测试 | 操作 | 验收 |
| --- | --- | --- |
| 单键 | 短按 A 20 次 | A 的 DOWN=20、UP=20，40 个连续事件 |
| 并击 | B、N 同时按下并松开，重复 20 次 | B、N 各 20 对物理事件，空格输出正常 |
| 双功能键 | Q 短按一次，再按住约 3 秒 | 2 对物理事件，长按时长约 3000ms |
| 重连 | 断电约 5 秒再开机，然后 A 五次 | 自动恢复，启动标识改变，5 对完整事件 |

受控测试要求：序号无缺口、接收端无重复、所有键均已松开、固件丢弃为 0。固件的“已去重”可以大于 0，代表已剔除 ZMK 内部重派发，不能与接收端重复报文混为一谈。

2026 年 10 月 10 日上述四项全部通过。Q 短按为 102ms，长按为 2833ms。最初未清零的探索会话收到一次没有 DOWN 的 Z 松开，符合开始采集时跨越已有按键的边界；清零后的四项测试均无配对异常。详细结果见 [validation-results.json](validation-results.json)。

受控事件作为自动测试夹具保留，替换启动标识并使用相对设备时间；不保存普通打字日志或本机绝对路径。

## 继续验证

正式应用上线使用前，应继续记录快速滚动输入、Mac 睡眠/唤醒、蓝牙档位切换和长期连接。续航需要功耗测量或可比较的长期使用数据；短时计数测试不能给出续航结论。

键盘重启、重连或新采集会话都会使未完成的按键配对失效；序号出现缺口时，也不再累计跨缺口的按住时长。界面应报告数据缺失，避免补造事件。

## 参考实现

- [ZMK 位置事件](https://github.com/zmkfirmware/zmk/blob/main/app/include/zmk/events/position_state_changed.h)
- [ZMK 事件监听顺序](https://zmk.dev/docs/development/events)
- [ZMK combo 重派发](https://github.com/zmkfirmware/zmk/blob/main/app/src/combo.c)
- [ZMK 外部模块](https://zmk.dev/docs/development/module-creation)
- [ZMK Studio 蓝牙 transport](https://zmk.dev/docs/development/studio-rpc-protocol)
