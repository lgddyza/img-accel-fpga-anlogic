> 2026-10-13修复版补充：默认状态栏改为灰度图内绘制，HDMI FPS已改为实测值。当前常驻interval=1，PC界面启动默认仍为2；需要复现本次性能请设置1。下文独立状态层及固定FPS:60的描述属于修复前行为，以总包README为准。

# RK3576 PC 视觉控制台

日期：2026-10-13。适配已部署的 EHP2 FPGA、RK3576/2GB、原六类 YOLOv8n 640 模型。

## 打开程序

本机直接双击 `launch.cmd`，或打开 `dist/RKVisionHost/RKVisionHost.exe`。
发布 ZIP 解压后打开 `RKVisionHost/RKVisionHost.exe`。整个 RKVisionHost 目录需要保留。
可执行版本已包含 Python、Qt、SSH 与串口运行依赖，不要求安装 Python。

当前已实测的连接配置：

| 项目 | 值 |
| --- | --- |
| 首选连接 | 网线 / SSH |
| RK 地址 | 169.254.53.76 |
| 本机实体网口地址 | 169.254.53.75 / 16 |
| SSH 用户 / 端口 | root / 22 |
| 登录方式 | 本机专用 SSH 密钥；密码留空 |
| 备用串口 | COM12，1500000 baud，root shell |
| HDMI connector | 188 |

本次已通过串口安装 SSH 公钥并验证网线连接。现场存在 NetworkManager `codex-direct`
连接配置，不需要 Windows 管理员权限或调整 WLAN。网口当前协商为 100 Mbps。
IP、用户名和密钥路径可以在连接栏修改；地址变化时先从 RK 串口执行 `ip -br addr` 确认。

换另一台电脑时，在新电脑上选择正确串口，点击“串口配置 SSH 密钥”，再点击网线“连接”。
该步骤需要 RK 串口已经进入 root shell，保留已有 authorized_keys，只追加这台电脑的公钥。
也可填板卡 SSH 密码或选择已有私钥。SSH 控制需要 root 用户访问现有运行目录、PCIe BAR 与驱动。

## 操作

1. 点击“连接”。状态连接正常但 FPGA 未就绪时，确认 FPGA 已上电、EHP2 bit 已加载。
2. 必要时点击“初始化 PCIe / 驱动”。它仅在控制器未绑定时重新绑定，扫描设备并加载现有 JPEG 驱动。
3. 点击“显示 + YOLO”，或“仅显示 · 关闭 YOLO”。“停止输出”会停止查看器及相关状态/K1进程。
4. 选择灰度、高斯、Sobel、黑帽之一，按需勾选“增强后叠加 CLAHE”，点击“应用预处理”。
5. 修改 QF，点击其右侧确认图标。预处理和 QF 在线切换，回读 FPGA 已生效值。
6. 修改置信度、每 N 帧推理和 connector 后，点击“应用并重启 YOLO”。重启期间 HDMI 会短暂停顿。
7. 在“识别结果”查看标签、置信度与 1920×1080 坐标；在“RK 日志”查看板端实际日志。
8. 点击“导出记录”保存本次 JSON 采样、识别框与操作记录，最多保留最近约10000次采样。

关闭上位机、断开连接不会停止 RK 已启动的显示/推理；停止需要点击“停止输出”。
小窗口左侧可以滚动，长文本和参数不会互相覆盖。连接失败可查看“操作记录”并重新连接。

## 八种模式与参数边界

| 模式 | 界面选择 |
| --- | --- |
| 0 | 灰度 |
| 1 | 高斯 |
| 2 | 灰度 + CLAHE |
| 3 | 高斯 + CLAHE |
| 4 | Sobel |
| 5 | 黑帽 |
| 6 | Sobel + CLAHE |
| 7 | 黑帽 + CLAHE |

EHP2 Sobel 为3×3/gain0.5，黑帽为3×3/gain1/方向line5过滤。核大小、gain、CLAHE内部参数
仍固化在 FPGA bit 中，界面仅展示这些常量；当前没有可动态修改这些参数的硬件寄存器。
K1 长短按仍由原板端程序管理。K1 切换后，界面“请求 / 生效”及状态表会跟随实际寄存器，
左侧待应用选择不会被轮询覆盖。PC与K1同时修改时可能报告冲突，确认实际值后重新应用即可。

## 帧率与状态口径

- HDMI实测FPS：原查看器 GStreamer fpsdisplaysink 最新输出；不是显示器外部仪器测量。
- YOLO实时FPS：共享状态序号差/2除以板端两次结果时间戳差；每次新结果序号加2。
- 重建平均FPS：查看器从启动至当前的平均重建速率，不是瞬时帧率。
- 输入帧率选择（标称）：FPGA 30/60配置；HDMI原OSD固定FPS:60并不是此处实测值。
- 检测结果年龄：板端monotonic计算，超过2秒不再显示旧框。
- 默认约1秒一次查询；RK日志部分指标约5秒更新。连接响应超过6秒时清除显示数据、禁用参数提交。
- 系统负载是Linux一分钟load average，不是CPU百分比；内存用MemAvailable计算。
- 启动确认要求实际HDMI帧和新推理结果；仅有进程存在不会被认为启动成功。
- FPGA故障0、未配对0、sink dropped0均不能单独证明全链路零丢帧。

此次短时实测和限度见 `verification/REPORT.md`。上位机保留现有视频算法和生产权重，
状态查询会使用少量CPU与网络资源；尚未进行长时间、固定素材的性能差异验收。
当前版本控制 RK HDMI 输出并回传状态/框列表，没有 PC 实时视频预览或 PC 端图像上传推理按钮。

## 部署与维护

PC源码：`app.py`、`transport.py`；RK控制：`board_agent.py`。
连接时自动上传/校验为 `/root/jpeg_rk/pc_host_agent_v1.py`；它只依赖 Python 标准库与已有
`preproc_mode.py`、`jpeg_control.py`。没有更换模型、原查看器、RTL、bit或系统镜像。
原启动脚本负责软件JPEG三线程、HDMI RGBx/KMS、独立状态层和AI失败回退。
上位机启动时关闭历史额外诊断，默认 interval2/conf0.10，视频保持60输入选择。
预处理/QF的当前值保留，用户在界面明确点击后才改变。

本机密钥和SSH主机公钥记录位于 `%LOCALAPPDATA%/RKVisionHost`，不在发布包中；密码不写入配置。
连接配置保存在当前用户的 Qt QSettings；现场 SSH 公钥初次接受后保存，后续公钥变化会报错。
连接超时不重放之前的控制命令，避免重连后执行过期操作。

源码运行：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe app.py
```

本机已准备虚拟环境。运行 `build.ps1` 重建 Windows 可执行版本，开发打包需另装 pyinstaller。
`verify_board.py` 会实际切换模式、启动/停止并恢复模式3/QF90/interval2/conf0.10；
`verify_live_ui.py` 会实际操作GUI按钮；它们不是只读测试。

撤回上位机功能：关闭PC程序；若板端仍运行，继续使用原K1/原启动脚本即可。
`pc_host_agent_v1.py`是新增独立文件，移除它不会改变原工程。
