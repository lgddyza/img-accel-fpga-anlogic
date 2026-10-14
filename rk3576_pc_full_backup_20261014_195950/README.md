# RK3576 与 PC 上位机完整部署存档

存档时间：2026-10-14T19:59:57，Asia/Shanghai。
版本：HDMI 同源 MJPEG 预览；YOLOv8n 灰度 640×640 INT8；RK3576 / 2GB。

## 内容与打开方式

- `board.tar.gz`：从板端实际文件只读取回，包含模型、HDMI/YOLO/K1/预处理控制、PCIe/JPEG 驱动、RKNN运行库、GStreamer插件、预览模块及原路径/权限/时间戳。
- `pc/RKVisionHost/`：当前完整 Windows 可执行程序及依赖。双击 `pc/launch.cmd` 或其中的 `RKVisionHost.exe`；须保留整个目录。
- `source/board/`、`source/pc/`：板端与上位机源码；PC源码构建用 `build_hdmi_preview.ps1`，需先建立 `.venv` 并安装requirements及PyInstaller。
- `environment.json`：内核、系统包、依赖、服务、运行进程与项目库清单。`runtime_before.json`/`runtime_after.json`为此次只读归档的实机快照。
- `manifest.json` / `PAYLOAD_SHA256SUMS` / `SHA256SUMS` / `verification.json`：文件校验及验证记录。
- `evidence/`：之前预览修复测试记录；其中参数和网速是历史数据，当前参数以 `RESTORE_SETTINGS.json` 为准。
- `rollback/before_network_preview.py`：预览修改前文件；不会自动回退。

本包不包含SSH私钥、登录密码、WiFi配置、系统镜像、训练数据或FPGA工程/bit。
运行库和驱动匹配当前aarch64 Debian12 / Linux6.1.99环境；系统动态依赖由原系统提供，并在环境清单中记录。

## 此次实机参数

| 项目 | 存档值 |
| --- | --- |
| HDMI connector | 188 |
| 视频输入标称FPS | 60 |
| YOLO输入 | 640×640，当前部署模型未变化 |
| 每N帧推理 | 1 |
| 置信度阈值 | 0.5 |
| 预处理模式 | 0 / gray |
| JPEG QF | 80 |
| HDMI | KMS，RGBx，软件解码3线程，normalize，实测FPS文字 |
| 网口预览 | HDMI最终sink输入帧，960×540，MJPEG quality80，约15 FPS上限 |
| RK地址 / PC地址 | 169.254.53.76 / 169.254.53.75，掩码255.255.0.0 |
| SSH / 备用串口 | root:22 / COM12:1500000 |

存档瞬时HDMI FPS：57.0；运行以来YOLO平均FPS：39.4。
当前协商网速实测记录：[{"name": "end0", "speed_mbps": 100}]。历史曾到千兆，不将历史网速当作当前网速。
上位机界面默认值可能不同，复现时按上表设置。`start.sh`默认值已按本次实机参数生成。
灰度模式0表示不启用高斯、CLAHE、Sobel、黑帽；原灰度通路及RK normalize仍保留。
该预览读取HDMI显示器输入端同一份像素，再缩放编码；不是物理屏幕截图。
历史静止场景测试背景明暗跳变明显降低；尚未收到用户对所有场景闪烁消失的最终确认。

## 恢复到同一板卡或同版本系统

当前正在运行，无需执行恢复。下列步骤仅供未来主动恢复使用，会覆盖包中同名部署文件。
先确认FPGA已加载八种模式EHP2位流，系统内核为6.1.99；先备份目标板上现有部署。
通过上位机“停止输出”停止查看器/K1，关闭预览。已加载的驱动如需替换，须在无采集进程时卸载，或恢复文件后重启板卡。
将存档目录传到板卡并进入该目录，以root执行：

```sh
sha256sum -c SHA256SUMS
tar -tzf board.tar.gz
tar -xzpf board.tar.gz -C /
cd /
sha256sum -c /path/to/backup/PAYLOAD_SHA256SUMS
depmod -a
systemctl daemon-reload
```

把 `/path/to/backup` 换成板卡实际存档目录。包保留两个PCIe服务的unit文件，原启用状态见environment.json；不会自动替换整套开机配置。
恢复驱动后重启可确保加载的模块和磁盘文件一致。确认PC与RK的直连IP后，可从存档目录运行：

```sh
nohup sh ./start.sh > /root/road_damage_yolov8n/hdmi_ai_ui_fixed.log 2>&1 < /dev/null &
```

也可通过PC上位机初始化PCIe，按上表设置模式/QF/interval/confidence再启动“显示 + YOLO”。
新电脑需自行配置登录：可通过已进入root shell的串口使用上位机“串口配置SSH密钥”，或使用已有合法登录方式。
预览令牌由运行进程生成，上位机连接后获取，不在存档中保存。
`build_runtime.sh`仅供有匹配开发依赖的SDK重编译用户态组件；驱动重编译另需匹配内核构建环境。

本次已核对板端文件读取前后SHA256、tar内文件大小/权限/内容、PC发布清单及整包ZIP内容。
没有停止或重新配置生产程序；是否有用户操作改变参数见verification.json。
没有在新系统上执行覆盖恢复测试，本包是部署备份，不能替代完整系统镜像。
