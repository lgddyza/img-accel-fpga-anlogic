# RK3576 完整部署包：HDMI修复 + 真实FPS

版本日期：2026-10-13，Asia/Shanghai。从当前运行板卡采集，未停止显示、未改FPGA RTL/位流/模型。板端时钟未同步，性能按单调时钟统计。

## 内容与配置

- `board.tar.gz`：55个实际部署文件，保留安装路径和Linux权限。含YOLOv8n 640×640 INT8模型、推理库/NPU运行库、三路PCIe/JPEG驱动、视频/推理/OSD程序、原生解码与重建库、控制脚本、K1、上位机agent、PCIe恢复服务及配置。
- `source/board/`：上述实际部署源码/配置副本。`source/pc/`：兼容上位机源码。安装程序以tar内文件为准。
- `pc/RKVisionHost_20261013_hdmi_fix.zip`：兼容Windows上位机，外置agent与板端逐字节一致。解压后保留整个RKVisionHost目录。
- `manifest.json`、`PAYLOAD_SHA256SUMS`：板端文件大小、权限、SHA256及捕获时寄存器。`environment.json`：系统包版本、动态库依赖、进程参数、映射库、状态采样和有限日志。
- `evidence/`：修复报告、对照实验、动态FPS验证和原始测试数据；`osd_23.4.png`是隔离字形测试图，不是实际HDMI截图。
- `rollback/before_hdmi_fix.tar.gz`：本次优化前的板端程序备份。`tooling/`：采集及打包工具。`verification.json`记录包校验结果。

当前运行：RK3576/2GB、aarch64、Linux6.1.99、connector188、1080p RGBx/KMS、软件JPEG三线程、normalize、YOLO interval1/conf0.10、mode7 BLACKHAT+CLAHE、QF90、输入选择60。
模型SHA256：`ecdc6accd6558c3394d4a73eeb03b876f09d9e82ba11c2754869d8bb9add55ae`。

保留白色粗框、标签/置信度、放大字符与半透明背景、QF/PREPROC/YOLO实时FPS、K1短按切QF/长按切预处理。HDMI `FPS:xx.x`来自末端fpsdisplaysink，约1秒更新，启动无统计时为`FPS:--.-`。

FPGA要求EHP2 ABI `0x45485032`、模式位图`0xff`。八模式为GRAY、GAUSS、CLAHE、GAUSS+CLAHE、SOBEL、BLACKHAT、SOBEL+CLAHE、BLACKHAT+CLAHE。黑帽K3/gain1/方向line5，Sobel K3/gain0.5；核与gain由已有bit决定，RK可切模式/QF，不能动态改这些固化参数。

## 为什么提升

三路JPEG由libjpeg-turbo原生接口解码；C memcpy重建条带、原生GStreamer buffer提交，减少Python/GI转换与内存搬运。状态栏先画在GRAY8，再转RGBx；默认取消独立状态平面提交。处理与KMS呈现使用独立队列，可同时处理下一帧和呈现上一帧。normalize保留单帧亮度/对比度稳定，取消前后帧50%混合，降低带宽并消除移动重影。

YOLO仍异步运行，但取图、缩放、调度、结果发布共享CPU/内存资源，因此视频链路优化也使推理线程得到更多运行时间。配对使用DMA完成时间、容限25ms缩至6ms，减少相邻帧条带混拼；用户移动相机确认波浪消失。组合修复已验证，未单独量化每项贡献。

| 相邻约35秒实机窗口 | 旧HDMI平均 | 新HDMI平均 |
| --- | ---: | ---: |
| 仅视频，含状态栏 | 55.4 FPS | 59.9 FPS |
| YOLO interval1，含状态栏/框 | 51.1 FPS | 59.7 FPS |

此AI对照窗口YOLO约31.63→32.97 FPS；后续稳定常驻累计约36～37 FPS、推理平均19.4ms。实时相机画面/JPEG负载随场景变化，后续窗口不能视为固定输入对照。瞬时YOLO读数可能高于长期平均；19.4ms的倒数也不等于整个程序实得FPS。

新旧解码对九个真实JPEG分片逐像素一致，最大差0；损坏JPEG/尺寸、135条带顺序、脚本语法均已验证。接近60 FPS不代表严格60张新画面/秒或零丢帧；上游队列仍有少量拥塞，末端dropped=0不包含它们。详见evidence/REPORT.md；其中固定FPS:60的段落描述首次修复，顶部动态FPS补充为最新行为。

## 校验与安装

这是匹配现有RK系统的完整应用部署包，不是系统镜像。系统通用Python/GI、GStreamer、OpenCV、libdrm、libjpeg-turbo、RGA及内核/设备树仍由原SDK提供；完整版本和ldd清单见environment.json。NPU运行库单独包含。JPEG/anlogic模块必须匹配内核构建与vermagic，仅版本号一致不足以保证可加载。FPGA工程与训练集另存原项目。

解压ZIP后在RK发布目录校验：

```sh
sha256sum -c SHA256SUMS
tar -tzf board.tar.gz
uname -a
modinfo -F vermagic /root/jpeg_rk/milianke_jpeg_a.ko
```

用上位机停止输出并确认viewer、启动器、K1助手退出。先备份将被覆盖的文件；空缺文件警告应逐项核对：

```sh
tar -tzf board.tar.gz > payload-paths.txt
tar -czf before-install.tar.gz --ignore-failed-read -C / -T payload-paths.txt
test "$(uname -r)" = 6.1.99
tar -xzf board.tar.gz -C /
(cd / && sha256sum -c /实际发布目录/PAYLOAD_SHA256SUMS)
depmod -a 6.1.99
systemctl daemon-reload
rm -f /run/jpeg-rk-gst-registry.bin /run/jpeg-rk-ai-gst-registry.bin
```

替换`/实际发布目录`为RK上的真实路径。只删除上述可重建的插件缓存；不要把历史备份目录加入GST_PLUGIN_PATH。未为此版本新增HDMI开机自启服务，现有rc.local仅供environment.json参考。

## 启动与控制

FPGA已烧录现有EHP2 bit、PCIe及HDMI连接正常后，在发布目录执行：

```sh
nohup sh ./start.sh 188 > /root/road_damage_yolov8n/release_start.log 2>&1 < /dev/null &
```

start.sh按需恢复PCIe/加载驱动，默认设BLACKHAT+CLAHE/QF90、interval1/conf0.10，然后调用原AI失败回退流程。可用`PREPROC_MODE=gauss-clahe JPEG_AI_INTERVAL=2 sh ./start.sh 188`选择其他配置；性能窗口需固定模式/画面才能比较。

已有板端文件安装好后，也可用PC包经SSH启动/停止、切模式/QF、查看帧率/框/温度。现场网口RK169.254.53.76、PC169.254.53.75/16；备用COM12/1500000。PC启动界面默认interval2，复现本次吞吐请设为1。包内不含SSH私钥、登录凭据或本机连接配置；新电脑按pc/README.md配置自己的登录。

仅视频调用`sh /root/jpeg_rk/start_jpeg_hdmi_60.sh 188`，须先停止AI启动器及子进程。状态查看：

```sh
python3 /root/jpeg_rk/preproc_mode.py status
tail -n 30 /root/road_damage_yolov8n/hdmi_ai_ui_fixed.log
```

## 重编译与回退

`sh ./build_runtime.sh`可在匹配RK SDK上重编译用户态库；需C/C++编译器、pkg-config、libjpeg/OpenCV/GStreamer/libdrm开发包和rknn_api.h。它不编译内核驱动。JPEG驱动源码/Makefile已包含，驱动编译需要原内核构建树；anlogic仅归档当前二进制，未证明本地供应商参考源码与此二进制完全对应。

捕获时顶层与active_ai_plugins中的temporalgray二进制哈希不同：顶层由带`-march=armv8-a+simd`的既有build脚本生成，活动目录保留首次修复构建。两份忠实归档；当前AI使用temporalai，且AI/status活动副本与顶层完全一致。纯视频启动脚本会复制顶层temporalgray；该纯视频路径已在本次修复对照中验证。

恢复安装前备份：先停止输出，再`tar -xzf before-install.tar.gz -C /`，清理上述两份插件缓存，`depmod -a`/`systemctl daemon-reload`，使用对应版本启动。
回退本次性能修复：按evidence/REPORT.md的方法将rollback/before_hdmi_fix.tar.gz提取到/root/jpeg_rk，移除新增的活动temporalgray插件、清理缓存，并使用原版上位机/旧启动配置。回退会恢复旧混帧/固定字符等行为。

此次只采集运行文件及校验归档，没有执行整包覆盖安装、全量重编译或重启复验；当前RK正常运行的文件就是board.tar.gz的来源。
