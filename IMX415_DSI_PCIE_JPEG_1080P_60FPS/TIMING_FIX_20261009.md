# EHP1 时序修复记录

## 目标与基线

目标：保持 JPEG 编码时钟 200 MHz、相机处理时钟 90.025 MHz，以及视频算法、JPEG 字节内容和传输吞吐；修复最终布线后的 setup 违例，hold 同时通过。板上实际帧率需要烧录后的独立验证。

基线为用户 2026-10-09 21:08 完成的 GUI 实现，报告 `fpga_prj_jpeg_Runs/phy_1/final_timing.rpt`。与此前综合估算 -0.917 ns 区分：该次最终布线 SWNS -0.378 ns、STNS -4.813 ns、28 个 setup 违例端点；HWNS +0.020 ns、HTNS 0。相机域 SWNS +0.828 ns，违例全部在 JPEG 域。

资源基线：Slice 54,043/64,320，ERAM 259/272，DSP 122/240。这里包含 GUI 的调试器逻辑，资源数不同于此前未插入调试器的独立综合报告。

原布线数据库 SHA-256：`2007AFAC28829E0941D1B798DEAEDF657AAA4DD7D7CED90F0670DE1212884CAC`。

原 GUI `best_result/fpga_prj_jpeg.bit` SHA-256：`6AFB8479907E3938E968FFC06F63731F0EDE4B1C69A5D43123D9DBFCD9138145`。

## 路径定位

| 路径 | 基线最差裕量 | 处理 |
| --- | ---: | --- |
| JPEG 输入 FIFO 读指针 → 占用量/empty → 输入缓存 wr_x 控制 | -0.378 ns | 在 FIFO 与编码器之间加可背压输出寄存器 |
| JFIF 头状态译码 → blk_ready → 输入缓存 RAM 读地址 | -0.332 ns | 寄存头完成标志，容量判断仍即时生效 |

第一条路径有六级逻辑，布线约占 66% 延迟；第二条路径布线约占 87%。两条均为真实同域单周期路径。

## 尝试一：物理优化

脚本 `tools/td_timing_physfix.tcl` 导入原 GUI 布线数据库，执行 `phys_opt -post_route -effort high`，并按 TD 建议设置 `route post_route_opt high`、`route postrt_opt_extra_round 4`。随后执行 hold 修复和最终时序分析。输出单独保存到 `tools/timingfix_phys_20261009/`。

最终 SWNS -0.129 ns、STNS -1.147 ns，13 个违例端点；HWNS +0.020 ns、HTNS 0。资源不变。日志 `td_20261009_211243.log`，终端状态 `TIMING_PHYSFIX_NOT_CLOSED`。没有生成该轮候选 bit。该实验说明布局优化有效，但不足以消除两条控制路径违例。

## 尝试二：RTL 流水线

- `uisrc/01_rtl/jpeg_gray4_axis_cdc.v`：增加 18 位数据/标记寄存器和 valid。输出有空位或下游接收时才从 FIFO 取数；背压时数据、SOF、EOL 保持。保留同步 RAM 首读等待及故障抑制逻辑。增加一拍延迟，持续吞吐仍为一像素/编码时钟。
- `third_party/mjpegZero/rtl/mjpegzero_enc_top.v`：寄存 `jfif_headers_done`，帧开始时清除旧状态。`pipeline_depth < HUFF_BANKS_CAP` 的容量判断保持即时生效。头完成后多等待一拍，不改变 JPEG 表、压缩算法或输出内容。

完整实现脚本为 `tools/td_timing_rtlfix.tcl`，包含原 GUI 的 `insert_debugger`，输出目录 `tools/timingfix_rtl_20261009/`。使用原约束进行综合、布局、布线和高强度布线后优化。只有最终 setup 和 hold 均无负裕量才生成候选 bit。

用户随后完成了采用该 RTL 的 GUI 综合与布局布线：综合结束于 21:51:55，布线数据库及 bit 结束于 22:19。最终 setup WNS +0.114 ns、TNS 0、0 个违例端点，先前两条 setup 违例已消除；但 hold WNS -0.017 ns、TNS -0.017 ns、1 个违例端点。相机域 setup WNS +0.649 ns。独立完整实现进程因用户已有这一轮真实布线结果而停止，后续直接基于用户的新数据库修复。

`tools/td_timing_rtlfix.tcl` 的完整流程已补入布线后的独立 `fix_hold`，并在最终时序通过后才生成 bit。该流程以后重新运行的结果仍需以当轮最终报告为准。

## 尝试三：最新布线的 hold 修复

输入为用户 22:19 完成的 `fpga_prj_jpeg_Runs/phy_1/fpga_prj_jpeg_pr.db`。输入数据库、bit、时序及资源报告已快照到 `tools/timingfix_hold_20261009_2219/input*`，GUI 原输出未被本轮修复覆盖。

唯一负裕量路径为第三路 JPEG `u_dct/u_col_dct/add8_syn_105` 输出至 `u_dct/ramread0_syn_24.dia[0]`，属于快角 hold：数据路径 0.288 ns、时钟偏斜 0.160 ns、最差裕量 -0.017 ns。此时 setup 已通过，因此采用 TD 物理 hold 修复增加短路径延迟。

脚本 `tools/td_timing_holdfix.tcl` 导入快照，设置 `route hold_fix_iteration 10` 后执行 `fix_hold`。实际第一轮通过：两个端点经 pin delay 调整后 HWNS +0.019 ns，再对一个端点增加 net delay 后 HWNS +0.020 ns。Slice、寄存器、ERAM、DSP 数量不变；feedthrough 从 19,614 增至 19,615。该步没有更改 RTL、时钟、算法或流接口延迟。

最终报告 `tools/timingfix_hold_20261009_2219/ehp1_route.timing`，生成时间 22:27:26，Routed、Slow/Fast 两角均检查：

| 指标 | 用户 22:19 新布线 | hold 修复后 |
| --- | ---: | ---: |
| Setup WNS | +0.114 ns | +0.114 ns |
| Setup TNS / 违例端点 | 0 / 0 | 0 / 0 |
| Hold WNS | -0.017 ns | +0.020 ns |
| Hold TNS / 违例端点 | -0.017 ns / 1 | 0 / 0 |
| JPEG 时钟 | 200 MHz | 200 MHz |
| Slice | 54,257/64,320 (84.35%) | 54,257/64,320 (84.35%) |
| ERAM | 259/272 (95.22%) | 259/272 (95.22%) |
| DSP | 122/240 (50.83%) | 122/240 (50.83%) |

首次 bit 生成在会话中断时未完成。恢复脚本 `tools/td_timing_holdfix_bitgen.tcl` 从已保存的修复数据库载入并重新计算最终时序，`ehp1_reloaded.ts` 再次确认 +0.114/+0.020 ns，然后生成候选 bit。布线修复日志为 `td_20261009_222401.log`；恢复生成日志为 `td_20261009_223027.log`。

恢复脚本退出码 0，终端状态 `TIMING_HOLDFIX_CLOSED`。候选 bit 于 22:32:19 完成，文件 [ehp1_candidate.bit](tools/timingfix_hold_20261009_2219/ehp1_candidate.bit)，大小 4,850,318 字节。无需再次综合即可手动烧录此文件。在后续回写原工程之前，`best_result/fpga_prj_jpeg.bit` 是用户 22:19 的输入版本；现在已按下节更新为新布线输出。

### 校验与边界

- 输入数据库 SHA-256：`36D958D6FE219CD03B5DC9D0750FE47472B4E4CAADD20C625B8DAC9A667C4818`。
- 输入 GUI bit SHA-256：`27542392282E4649E2C1CDD21C28A8FCEB4E5D7CE5F79BC01F326FD413C2A34B`。
- 修复数据库 `ehp1_route.db` SHA-256：`FB5C616B1792A9DE968CE0029D6E1CFE7EA8D18D4D3EE33EC24B17E2CD7FAFD6`。
- 候选 bit SHA-256：`3309883281A81241C97D1B6394A4B7691533B774B865429360465BB8CB19C927`。
- 生成完成后再次校验：GUI 原数据库以及 `phy_1`、`best_result` 原 bit 与输入快照校验值一致；修复 bit 和数据库独立保存。
- STA coverage 99.71%。已定义约束下的 setup/hold 已通过，并不代表所有外部接口均有完整输入/输出延迟约束。
- `check_timing` 报告与用户本轮原报告逐字节相同，SHA-256 均为 `EA4654EEF6940C00300A753969101B2611B8D2FE9CCD808346AF45030777D182`。仍有原先 I2C 派生时钟未定义、部分外部 IO 延迟缺失、PCIe PLL 请求 62.5 MHz/实际 125 MHz 的告警。
- 路由 DRC 已执行，结果在修复日志中；仍有原先 I2C、调试器及 DDR 参考时钟使用局部路由资源的告警，未出现连接、多驱动或 LUT bridge 错误。不能将本轮结果表述为全部告警清零。
- 当前正裕量较小，后续改动或重新布局布线后应再次做最终分析。ERAM 剩余 13 个。
- 候选尚未烧录，板上视频帧率、PCIe 稳定性及增强算法检测效果仍需上板验证。

从修复数据库恢复 bit 生成（工程根目录 PowerShell）：

```powershell
& 'F:\FPGA\AnLu\bin\td_commands_prompt.exe' tools/td_timing_holdfix_bitgen.tcl
```

`td_timing_holdfix.tcl` 复用保存的 22:19 输入快照；若将来要修复另一轮数据库，应使用新的结果目录，避免把历史快照当成新输入。

## 原工程接入新布线（22:55）

用户要求原工程采用修复后的布线。已先将 `fpga_prj_jpeg.al`、完整 `phy_1` 与 `best_result` 备份到 `tools/timingfix_original_backup_20261009_225130/`，再执行 `tools/td_apply_timingfix_original.tcl`。该脚本读取原 `.al` 和 `phy_1` 参数，导入已验证数据库并重新进行最终时序分析；setup/hold 非负后才回写原工程输出。

已更新 `phy_1` 的布线数据库、最终时序/异常/检查/资源报告、route QoR、clock utilization、route flow status、普通和压缩 bit、实例 BID、调试器 `cw/compiled.bit` 与 `compiled.cwc`。`best_result` 中对应 bit、BID、时序状态同步。布局阶段输出保持原样，因为本次仅在同一布局上修复引脚/布线延迟。

原 `phy_1/fpga_prj_jpeg.tcl` 的 editable zone 已加入显式布线后 hold 修复、`final_timing.rpt` 刷新及生成 bit 前的 setup/hold 检查。独立的恢复入口为 `tools/td_apply_timingfix_original.tcl`；该入口明确针对保存的 22:19 布线修复结果，不应用于将来的其他源码版本。TD 若重新生成运行脚本，应检查上述 editable zone 是否仍保留，重新布局布线的结果始终以当轮最终报告为准。

结果：22:53:57 最终报告 SWNS +0.114 ns、HWNS +0.020 ns、TNS 均为 0；route QoR setup/hold 违例端点均为 0，布线资源检查 0 issue。22:55:06 完成普通 bit，22:55:05 完成压缩 bit，脚本退出码 0、状态 `TIMING_ORIGINAL_UPDATED`。日志 `td_20261009_225230.log`，副本更新到 `phy_1/run.log`。

| 当前原工程文件 | SHA-256 |
| --- | --- |
| `phy_1/fpga_prj_jpeg_pr.db` | `FB5C616B1792A9DE968CE0029D6E1CFE7EA8D18D4D3EE33EC24B17E2CD7FAFD6` |
| `phy_1/fpga_prj_jpeg.bit` | `06B853A52E73157005B02300CF9E331BD94A9D0811DF5FC55EE3659B5A70F993` |
| `phy_1/fpga_prj_jpeg_compress.bit` | `093E21885E05301C22B8E86EEDAD80FB51168E19D3136EA6E69F0BB61BE897AB` |

原工程布线数据库与独立修复数据库逐字节相同。`best_result` 中两种 bit 分别与 `phy_1` 对应文件逐字节相同；`cw/compiled.bit` 与普通 bit 相同。普通 bit 大小 4,850,318 字节，压缩 bit 大小 4,638,272 字节。重新生成 bit 保留 `time_info on`，校验值与 22:32 独立候选不同，应使用上述当前输出校验值。

TD GUI 在更新期间处于打开状态，应重新打开 `fpga_prj_jpeg.al` 刷新内存中的旧报告/数据库。未停止 GUI，未烧录 FPGA，未访问 RK；上板验证边界仍如上节。

## 功能证据

`tools/verify_jpeg_timing.py` 使用 Icarus Verilog 编译工程中的实际 RTL，在源码修改前保存原始 JPEG 作为对照。

| 检查 | 结果 |
| --- | --- |
| 64 像素宽渐变，Q85，三路 JPEG | 3 个输出与基线逐字节一致 |
| 1920 像素宽随机纹理，Q85，三路 JPEG | 3 个输出与基线逐字节一致 |
| 1920 像素宽随机纹理，Q30，三路 JPEG | 3 个输出与基线逐字节一致 |
| 正常帧、跳过帧及溢出停流 | 通过 |
| 异常 SOF 和 FIFO 满故障细节 | 通过 |
| 五帧、2,560 像素，随机背压及输出稳定性 | 通过，连续 320 拍成功输出 |
| 三路 JPEG 连续三帧 | 通过，完成计数 3/3/3，fault 0 |
| 工程清单、AST、本地端口及原 demo 文件检查 | 通过 |

输出及日志位于 `tools/timingfix_sim/baseline/`、`tools/timingfix_sim/candidate/`。基线九张 JPEG 的 SHA-256 保存在 `baseline/hashes.json`。新背压用例修正了最初激励过早的问题：厂商 FIFO 内部跨域复位需要两拍释放，测试在释放后等待八个相机时钟才送入首帧；修正后用例通过。

复验命令，在本工程根目录执行：

```powershell
& 'C:\Users\21093\AppData\Local\Temp\road_damage_yolov8n_venv\Scripts\python.exe' tools/verify_jpeg_timing.py candidate
& 'F:\FPGA\AnLu\bin\td_commands_prompt.exe' tools/td_timing_rtlfix.tcl
```

保留现有 `baseline/` 对照数据；`baseline` 子命令仅用于在原实现源码上重新采集对照。
