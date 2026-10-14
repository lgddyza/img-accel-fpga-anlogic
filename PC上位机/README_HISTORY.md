# RK3576 PC 视觉控制台

日期：2026-10-14。适配已部署的 EHP2 FPGA、RK3576/2GB、原六类 YOLOv8n 640 模型。

当前以首次视频版为基础，修正RK预览取帧位置：MJPEG / 960×540 / 15 FPS / JPEG quality80，从HDMI显示器输入端的最终帧生成预览；不直接转发PCIe原始帧，不增加PC亮度补偿。原HDMI查看器、PCIe采集、模型、FPGA和时域处理未修改。保留首次版界面与控制功能，窗口标题包含“HDMI 同源预览”。取帧/编码代码和部署证据见 `verification/preview_cadence_20261014/`，首次版回退记录见 `verification/rollback_first_video_20261014/`。下方后续预览优化章节为历史记录，不是当前运行版本。

## 打开程序

本机直接双击 `launch.cmd`，或打开 `dist_hdmi_preview/RKVisionHost/RKVisionHost.exe`。
发布 ZIP 解压后打开 `RKVisionHost/RKVisionHost.exe`。整个 RKVisionHost 目录需要保留。
可执行版本已包含 Python、Qt、SSH 与串口运行依赖，不要求安装 Python。

当前预览在HDMI最终sink输入处保留独立帧元数据和共享像素内存的安全引用，固定每四个60 FPS输入帧选一帧；缩放、格式转换、JPEG编码和网络发送在独立管线/线程执行。它读取HDMI显示器接收的帧，不代表外部仪器测量的逐次scanout，也不是显示器屏幕截图。没有新的PCIe采集器。输入与编码队列各只保留最新帧，网络慢时不等待主显示。

部署RK升级需重启viewer一次：仅替换 `/root/jpeg_rk/network_preview.py` 为 `../road_damage_yolov8n/runs/pc_hdmi_preview_20261014/board/network_preview.py`，其余文件保留；重启前记录当前运行模式、connector、interval与confidence，重启后核对预处理/QF未改变。本机板卡已部署，无需再次升级。

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
连接配置，不需要 Windows 管理员权限或调整 WLAN。2026-10-13网口曾协商100Mbps；2026-10-14关闭PC的Gigabit Lite后双方达到1000Mbps全双工，短时RK→PC TCP约919Mbps。此次网卡属性调整使用了管理员权限。
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
- 输入帧率选择（标称）：FPGA 30/60配置；当前HDMI OSD FPS也来自末端实测值。
- 检测结果年龄：板端monotonic计算，超过2秒不再显示旧框。
- 默认约1秒一次查询；RK日志部分指标约5秒更新。连接响应超过6秒时清除显示数据、禁用参数提交。
- 系统负载是Linux一分钟load average，不是CPU百分比；内存用MemAvailable计算。
- 启动确认要求实际HDMI帧和新推理结果；仅有进程存在不会被认为启动成功。
- FPGA故障0、未配对0、sink dropped0均不能单独证明全链路零丢帧。

此次短时实测和限度见 `verification/REPORT.md`。上位机保留现有视频算法和生产权重，
状态查询会使用少量CPU与网络资源；尚未进行长时间、固定素材的性能差异验收。
当前版本支持 PC 网口实时视频预览，尚无 PC 端图像上传推理按钮。

## 2026-10-14 MJPEG 画质优先优化版（历史版本，已回退）

PC预览修复版2发布包为 `RKVisionHost_20261014_mjpeg_stable.zip`。关闭之前打开的上位机窗口后，通过`launch.cmd`或`dist_preview_v2/RKVisionHost/RKVisionHost.exe`打开新版，连接后点击“开始”。窗口标题包含“预览修复版2”。针对文字/框仍在、背景忽明忽暗的症状，预览默认勾选“亮度稳定”：用同一帧的亮度LUT补偿快速亮度跳变，遇到明显场景切换或停顿则重置；没有叠加/平均前后帧，不改变细裂缝的空间位置。纯白文字与框保留白色。取消勾选可直接对比原始预览。

保留PC完整帧缓冲、固定FPS文字高度、资源饼图扇区更新，以及断流保留最后画面并明确标注的改进。首轮仅改绘制未消除用户报告的亮度闪动，未继续切换OpenGL。RK的viewer、HDMI参数和板端程序保持现状，PC补偿不改变HDMI或YOLO输入。详细证据和限制见发布包 `verification/REPORT.md`。

用户反馈H.264试验版的路面细节偏模糊，当前已恢复原MJPEG编码方式：960×540、GRAY8、原缩放方式、JPEG quality80。保留原深色界面、资源饼图、PCIe条形图、检测框与实时参数。发布包为 `RKVisionHost_20261014_mjpeg.zip`，连接后点击视频区“开始”。

仅做小幅优化：保持原C层限速，增加5/10/15/30自动档位；从15档开始，负载许可时提高到30档，CPU超过90%、HDMI相对关闭预览基线下降超过0.7 FPS、YOLO下降超过5%时降档。目标30档包含限速、JPEG编码和调度耗时，实际帧率以界面显示为准。使用单帧邮箱、HTTP分块传输，关闭预览后停止缩放与编码。画质参数不随帧率降低。

本次模糊的主要怀疑因素是原H.264目标3Mbps与复杂路面细节不匹配。两个版本分辨率和缩放相同，不能仅凭不同时间截图把问题完全归因于编码；未做相同输入逐像素画质验收。主业务优先，详细现场对照、截图与限制见 `verification/REPORT.md`。板端备份 `before_mjpeg.tar.gz` 可恢复本次替换前的预览模块和agent；回退前先停止输出，恢复文件后重新启动。

## 2026-10-14 硬件 H.264 预览版（试验版本）

该试验版本为`RKVisionHost_20261014_h264.zip`，采用MPP硬件H.264编码，预览仍为960×540，实际码率随场景变化。PC用PyAV/FFmpeg解码，打包EXE包含依赖；无须安装FFmpeg。界面分别显示解码FPS、实际Qt绘制FPS、码率和当前目标档位，最大化与截图功能保留。

使用步骤：网线/SSH连接，确认HDMI在输出，点击视频区“开始”。预览默认自动调速，上限60 FPS；新连接先从30档开始，每5秒检查近期CPU、HDMI和YOLO。CPU超过90%、HDMI相对预览关闭基线下降超过0.7 FPS、或YOLO下降超过5%时降低预览档位；CPU低于86%且主业务稳定时逐档提升。档位为5/10/15/30/45/60；目标档位不是保证帧率，预览管线调度与缩放会产生额外耗时。相机画面与预处理改变时，实际档位会调整；主业务性能优先。没有客户端时关闭valve，停止预览缩放/编码，MPP缓冲在该viewer生命周期内保留以支持快速重连。

编码器是独立GStreamer管线，与HDMI仅共享完成叠加后的灰度帧。主显示不等待网络；输入泄漏队列及appsrc各自有界。编码输出保留16个访问单元，客户端落后时跳过失效参考帧并请求关键帧；每个IDR附带SPS/PPS。PC发现序号间断会等待新IDR再解码，不把损坏P帧作为有效预览。编码异常只停预览，板端错误与自动调速状态在遥测里可查看。HTTP分块传输携带H.264访问单元与序号，令牌鉴权沿用可信直连网络方案。

现场Sobel/QF95/interval2固定配置下：60档实际解码59.90 FPS，HDMI平均59.65 FPS，YOLO29.77 FPS，CPU85.28%，视频约3.06 Mbps；预览关闭基线HDMI约59.9 FPS、YOLO约29.7～29.8 FPS、CPU约79%。自动模式短时平均预览56.49 FPS、HDMI59.60 FPS，零访问单元序号缺失/解码错误。结果取决于现场负载，不能保证所有预处理与场景同时保持60 FPS。详细对照见发布包`verification/REPORT.md`。

该阶段RK更新了`network_preview.py`与agent，原viewer继续调用同名预览模块。迁移板卡时，先安装原完整RK环境，停止输出并备份同名文件，再复制`rk_video`中的四个Python文件；新版PC连接会上传对应agent。`before_h264.tar.gz`备份硬件预览升级前的network_preview.py/agent，用于回退MJPEG版本；回退前应停止输出。历史发布包与EXE目录保留，使用当前新版EXE避免旧软件覆盖新agent。

## 2026-10-14 MJPEG 视频版（历史版本）

参考提供的 HTML 改为深色三栏：左侧运行与预处理控制，中间真实视频和资源饼图，右侧 FPS、PCIe 码率、温度和网口。中间下方箭头可展开实时参数、识别结果、RK 日志与操作记录。

连接后先确认 HDMI 正在输出；若未启动，点击“显示 + YOLO”或“仅显示”。点击视频区“开始”接入实时预览；“停止”仅关闭 PC 视频，不停止 HDMI 或推理。保存图标保存当前预览 PNG，最大化图标进入全屏，可用退出按钮或 Esc 返回。串口连接仅控制与查看状态，视频需网线/SSH连接。

预览为 MJPEG / 960×540 / 上限15 FPS / JPEG quality80，与 FPGA JPEG QF 参数分别控制。它在现有灰度视频完成时域处理、文字与识别框叠加后分支；HDMI 保持1920×1080原输出，YOLO输入仍为原灰度帧。没有第二组PCIe采集器或重复JPEG条带解码。预览队列最大1帧，下游慢时丢弃旧帧；PC也只保留最新解码帧。关闭预览后valve停止缩放与编码；当前板端已部署。显示里的预览FPS/码率是PC收到的有效JPEG帧/字节，不与HDMI FPS混用。

板端监听TCP8766，最多两个客户端，通过SSH领取当前viewer随机令牌后访问，令牌随viewer重启失效。仅用于可信的本机直连网络；MJPEG未加密。关闭上位机、断开SSH或重启viewer会停止PC预览；重启显示/推理后点击“开始”重新接入。断流或3秒无新帧时提示过期，不把旧图当实时视频。

发布ZIP的`rk_video`包含当前部署的两份viewer、network_preview.py和采集遥测capture_jpeg_tiles.py，需原完整RK部署包及已验证的GStreamer JPEG/videoscale插件。迁移板卡时先通过原上位机停止输出，备份同名文件，将这四份文件放到`/root/jpeg_rk/`；新版上位机连接自动上传board_agent.py，再启动显示与预览。`before_video.tar.gz`是当前板升级前的三文件备份，回退前必须停止viewer；回退后可删除network_preview.py并使用旧版上位机。预览升级未改FPGA RTL、bit、驱动或模型。

实机对照数据与截图见`verification/REPORT.md`；当前QF100高纹理场景的CPU基线较高，预览不是60 FPS镜像。若需要1080p60或录像，需另行验证MPP硬件H.264编码及长时间负载，不直接放大现有MJPEG规格。

## 2026-10-13 仪表盘更新

首屏“运行概览”包含CPU、内存、NPU环形饼图，PCIe三路接收码率与合计条形图，并显示最高温度、GPU负载、网口协商速率。连接栏的箭头展开SSH密钥设置；原有预处理、推理参数、检测表格、日志、导出功能保留。小窗口可滚动，过期/断开状态会清空图表。

CPU百分比来自两次/proc/stat差分（100%表示全部核心忙，iowait计入空闲），各核心百分比仍在实时参数表。内存按MemTotal−MemAvailable计算。NPU来自rknpu驱动各核心负载的平均采样值；它可能短时为0，不能用YOLO耗时倒数替代。GPU读取devfreq/load；接口不可用显示“—”。系统load average单独展示，不与CPU百分比混用。

PCIe码率按实际采集的累计JPEG字节数差分，约1秒采样；单位Mbps，不含PCIe TLP、链路编码、填充和未送到appsink的字节开销。三个通道分别发布，合计是相近窗口之和；不是物理链路利用率。初次连接、采样过期、显示进程重启、缺少一个通道时，未知值显示“—”，不估造0或合计。旧查看器需重启一次启用新增计数器。

RK额外变更仅为board_agent.py及capture_jpeg_tiles.py中的轻量计数/状态发布；文件使用/run tmpfs，每通道每秒一次原子更新，且失败不会中断视频。未改变解码、配对、检测或FPGA RTL。上板记录与原两文件回退包保存于`../road_damage_yolov8n/runs/pc_dashboard_20261013/`。当前RK agent已更新，连接新版EXE也会校验/上传对应agent；请退出旧版上位机再使用新版，避免旧版重连上传旧agent。

发布包`rk_telemetry/board/capture_jpeg_tiles.py`是现有RK应用的采集统计更新，不包含模型/全部驱动。转移到另一块同系统板卡时，先安装之前的完整RK部署包，再在停止viewer/启动器/K1助手后备份并替换`/root/jpeg_rk/capture_jpeg_tiles.py`，通过新版上位机重连上传agent，再启动显示。当前这块板已完成替换。`before_telemetry.tar.gz`供当前板回退两个文件；停止输出后提取到`/root/jpeg_rk`，再使用对应版本PC程序启动。

## 部署与维护

PC源码：`app.py`、`transport.py`、`video_preview.py`；RK控制：`board_agent.py`。
连接时自动上传/校验为 `/root/jpeg_rk/pc_host_agent_v1.py`；它只依赖 Python 标准库与已有
`preproc_mode.py`、`jpeg_control.py`。视频版同时更新原查看器并增加`network_preview.py`，没有更换模型、RTL、bit或系统镜像。
原启动脚本负责软件JPEG三线程、HDMI RGBx/KMS、灰度图内状态栏和AI失败回退。
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

本机已准备虚拟环境。运行 `build_dashboard.ps1` 重建新版Windows可执行版本，然后执行 `.venv/Scripts/python.exe package_release.py --dashboard` 归档，开发打包需另装pyinstaller。新版输出到dist_dashboard，旧dist及旧发布包保留。
`verify_board.py` 会实际切换模式、启动/停止并恢复模式3/QF90/interval2/conf0.10；
`verify_live_ui.py` 会实际操作GUI按钮；它们不是只读测试。

撤回上位机功能：关闭PC程序；若板端仍运行，继续使用原K1/原启动脚本即可。
`pc_host_agent_v1.py`是新增独立文件，移除它不会改变原工程。
