# RK3576 YOLOv8n / EHP2 / K1 部署归档

版本日期：**2026-10-10，Asia/Shanghai**。这是从当前RK板实际运行目录采集的部署包，含最新K1长按切换和左上角PREPROC显示。旧版2026-10-08归档保留。

## 内容

- `board.tar.gz`：47个实际部署文件，保留相对于 `/` 的路径和权限。包含当前640×640 INT8 RKNN模型、推理库、NPU `librknnrt.so`、HDMI/YOLO程序、状态图层源代码和二进制、GStreamer插件、EHP2/QF/K1控制脚本、PCIe/JPEG驱动及现存源码、PCIe恢复脚本和systemd配置。
- `source/`：从此板端归档提取的源码副本，方便在PC查看；启动仍使用归档恢复后的 `/root/jpeg_rk`。
- `manifest.json`：逐文件SHA256、大小、权限及捕获时FPGA寄存器。
- `environment.json`：内核、依赖、进程参数及相关环境变量、DRM图层、驱动/服务状态和日志尾部。没有采集完整进程环境。
- `PAYLOAD_SHA256SUMS`：归档内部47个文件的校验清单。
- `SHA256SUMS`：此发布目录中的文件校验清单。
- `verification.json`：在PC逐项核对归档内部文件后的结果。
- `start.sh`：恢复后的启动辅助脚本，要求匹配内核与EHP2；设置模式3、QF90后启动原HDMI+YOLO流程。
- `evidence/`：K1逻辑回放、八模式实际切换、状态缓冲图及部署说明；FPGA最终资源/时序报告和道路测试量化摘要。
- `capture_rk_release_20261010.py`：此次板端归档采集脚本。

这是运行程序归档，不是整张SD卡/根文件系统镜像。训练数据、其他权重、历史实验图像、大量运行日志、FPGA bit及系统通用OpenCV/GStreamer/libdrm共享库没有混入部署包；其中NPU运行库已单独包含。需要匹配的原板Linux环境，依赖详情见 `environment.json`。

## 固定版本与功能

| 项目 | 归档配置 |
| --- | --- |
| 硬件 / 内核 | RK3576，2GB；aarch64；Linux6.1.99，驱动还需匹配内核构建/vermagic |
| FPGA能力 | EHP2 `0x45485032`，模式位图 `0xff` |
| 捕获时模式 | 3：高斯+CLAHE |
| JPEG / 输入 | QF90；60 FPS输入选择；三路PCIe JPEG |
| 显示 | connector188，1920×1080，RGBx，软件解码3 workers，时域affine |
| YOLO | 原6类YOLOv8n，640×640 INT8，interval2，阈值0.10，NMS0.45 |
| 叠加 | 白色粗框、类别/置信度；左上角静态FPS:60、QF、YOLO实时FPS及PREPROC |
| 状态图层 | 600×124，1Hz，25%背景不透明度；显示实际生效模式 |
| K1 | GPIO1_B7 / Linux47，低有效；短按松开切QF，长按约1.2秒切预处理，按住仅触发一次 |

模式循环：`GRAY→GAUSS→CLAHE→GAUSS+CLAHE→SOBEL→BLACKHAT→SOBEL+CLAHE→BLACKHAT+CLAHE→GRAY`。黑帽K3/gain1加四方向line5；Sobel T1/gain0.5。

模型SHA256：`ecdc6accd6558c3394d4a73eeb03b876f09d9e82ba11c2754869d8bb9add55ae`。

`board.tar.gz`大小 **5,712,628字节**，SHA256：`90968dc299d4918602060efd34d6a536a331794a9602b8f7e81d34ce019f357f`。COM12传输已核对分片CRC32和整包SHA256，另在PC校验内部47个文件。

## 验证记录与限制

K1软件回放及实际八模式PCIe切换/显示读回通过，切换时QF保持90，硬件fault为0；捕获时mode3/QF90、preproc/raw/JPEG fault均0。实物按键最终操作反馈在本次归档时尚未收到，不将逻辑回放表述为手指实按验收。

最近部署验证中HDMI程序累计速率约57.3FPS，YOLO约29.9FPS，取决于场景。静态FPS:60不能作为严格60FPS呈现证据。道路测试中增强后CLAHE可能增加JPEG负载和分片配对丢弃，详见 `evidence/road_SUMMARY.md`；本包不承诺零丢帧或裂缝召回率。

当前运行进程带有 `JPEG_PAIR_DIAG=1` 和 `RK_STATUS_SNAPSHOT`，这是最近验证使用的诊断开关，已记录在环境文件。`start.sh`默认关闭配对诊断且不生成状态图片；需要复现诊断时，可传 `JPEG_PAIR_DIAG=1 RK_STATUS_SNAPSHOT=/run/preproc_status.ppm`。

板端原始时间未同步，文件时间戳不作为归档日期。源代码副本与实际二进制均保留，但没有为此次归档重编译全部历史驱动、执行恢复或验证重新编译能逐字节生成相同二进制。

## 校验与恢复

先解开外层ZIP，在发布目录运行：

```sh
sha256sum -c SHA256SUMS
tar -tzf board.tar.gz
```

恢复到匹配RK3576系统前，停止现有HDMI/YOLO启动器、viewer、状态图层和按键控制器，并备份 `/root/jpeg_rk`、当前模型、归档涉及的 `/etc`、`/usr/local/sbin`、`/lib/librknnrt.so` 及PCIe内核模块。模型/运行库/驱动和系统配置会被下列提取覆盖。

确认内核及构建匹配后，以root运行：

```sh
test "$(uname -r)" = 6.1.99
tar -xzf board.tar.gz -C /
(cd / && sha256sum -c /path/to/release/PAYLOAD_SHA256SUMS)
depmod -a 6.1.99
systemctl daemon-reload
```

上面的 `/path/to/release` 替换成实际发布目录。不要将旧回滚插件目录添加到 `GST_PLUGIN_PATH`；原启动脚本仅使用 `active_ai_plugins`，避免GStreamer加载同名旧插件。

FPGA已烧录匹配EHP2、相机输入和HDMI连接可用后：

```sh
nohup sh ./start.sh > /root/road_damage_yolov8n/release_start.log 2>&1 < /dev/null &
```

此辅助脚本按需加载 `anlogic_pci` 与三路JPEG驱动，检查EHP2/FF，设置模式3、QF90和输入60，启动原fallback流程。它要求JPEG采集和旧显示进程已经停止，不会主动杀掉旧进程。使用该脚本后，短按/长按K1分别切QF/预处理。

```sh
python3 /root/jpeg_rk/preproc_mode.py status
ps -eo pid,args | grep -E 'jpeg_qf_button|rk_hdmi_status_plane|show_jpeg_hdmi_overlay'
tail -n 20 /root/road_damage_yolov8n/hdmi_ai_ui_fixed.log
tail -n 20 /root/road_damage_yolov8n/hdmi_status_plane.log
tail -n 20 /root/jpeg_rk/qf_button.log
```

`anlogic-sgdma.service` 的启用状态和active状态不等价，按捕获记录核对 `lsmod`、设备节点及 `pcie1-recover.service`。本版本的HDMI应用由root脚本启动，没有为此次归档新增开机自动运行服务。
