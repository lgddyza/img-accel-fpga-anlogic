# RK HDMI 修复记录

日期：2026-10-13（按 PC 日期）。板卡时钟与 PC 日期不同，帧率统计使用单调时钟。

## 后续更新：HDMI 实测 FPS

同日按用户要求，已将左上角固定 `FPS:60` 改为实时 `FPS:xx.x`，约一秒刷新一次。
两种默认运行模式（纯视频、YOLO）均使用 HDMI 管线末端 `fpsdisplaysink` 的同一测量值，通过线程安全的 `display-fps` 属性送到灰度状态栏；不会把队列前的处理速率误当显示速率。
启动尚无统计时显示 `FPS:--.-`。字体、背景、YOLO FPS、QF、PREPROC 保持原样。
运行日志已验证 57.5、59.0、60.1 等统计值传入状态栏；隔离渲染验证 23.4 与 47.8 产生不同 FPS 数字像素。
当前板卡程序和 `source/` 已更新。`rk_hdmi_live_fps_20261013.tar.gz` 是这次四文件增量包，应用于前面的修复版本；原修复 tar 保留旧版固定标识以供回退。
验证数据保存为 `live_fps_verification.json`，此次变更前备份在板卡 `/root/jpeg_rk/hdmi_fix_20261013/live_fps/before.tar.gz`。
下文描述的是首次修复与对照实验，其中“静态 FPS:60”是更新前的行为。

## 结果

已部署到 RK 的 `/root/jpeg_rk`，目前运行 YOLO、推理间隔 1、置信度 0.10。
FPGA RTL、位流、模型、640x640 推理输入均未改变。保留 K1、QF、八种预处理模式和上位机控制。
用户实机移动相机观察反馈：“波浪消失，文字和框正常”。这一反馈发生在分片配对、取消混帧及灰度 OSD 上板后；后续解码优化保持同样的配对和显示策略。

相邻对照窗口均为 BLACKHAT+CLAHE（mode 7）、QF90、1080p、输入选择 60、软件解码、RGBx、KMS auto、相同 CPU 亲和性。每个窗口约 35 秒。
相机是实时输入，不是固定录像重放，JPEG 大小仍随画面/曝光变化。因此结果不是逐帧相同输入的基准测试。

| 状态 | 旧版 HDMI 整段平均 | 修复版 HDMI 整段平均 |
| --- | ---: | ---: |
| 仅视频，含状态栏 | 55.4 FPS | 59.9 FPS |
| YOLO interval=1，含状态栏与检测框 | 51.1 FPS | 59.7 FPS |

修复版纯视频末段连续读数为 60.0 FPS；AI 末段为 59.0～60.0 FPS。
AI 对照窗口累计推理约 33 FPS；恢复常驻运行后的七次采样累计约 36.2～36.4 FPS，单次推理平均约 19.4 ms。
常驻运行采样的 HDMI 瞬时读数为 59.7～60.4 FPS，之后更长运行的累计平均约 59.6 FPS。超过 60 的短窗读数来自计数窗口与提交抖动，不代表 HDMI 刷新率超过 60 Hz。

## 修改

1. 分片配对使用 `v4l2src` 的 PTS 加各管线 base_time，还原驱动 DMA 完成时间；替换 Python 回调到达时间。
2. 配对容限从 25 ms 降至 6 ms；超出容限时丢弃最旧分片并重新对齐，不强行拼接。实际对照中的最大配对时间差为纯视频 0.98 ms、AI 2.23 ms。
3. 记录无效 JPEG、元数据缺失、采集队列丢弃和 V4L2 sequence 间隔。分通道 sequence 是完成计数，不能当作相机源帧编号。
4. 新默认 `normalize` 模式保留单帧亮度/对比度稳定，设置 `mix-previous=false`，取消前后两帧 50% 混合。旧 blend/affine/tone 模式仍可用于对照。
5. 状态栏在 GRAY8 上绘制，然后转换 RGBx。半透明暗背景、放大字体、静态 FPS:60、动态 YOLO FPS、QF 和 PREPROC 都保留。移除默认独立状态平面提交，避免它与视频提交竞争。
6. 在图像处理/转换和 KMS 呈现之间增加独立有界队列，使处理下一帧与呈现上一帧并行。保留 KMS auto 和原 skip-vsync 设置；没有通过关闭同步来追求帧率。
7. 三路软件 JPEG 解码使用系统 libjpeg-turbo 2.1.5 的原生接口，仍采用与 GStreamer jpegdec 相同的 IFAST IDCT。省去解码管线数据往返。损坏输入通过 libjpeg 的错误处理返回，尺寸在输出前验证。
8. C memcpy 重建 8 行交错条带；以原生 GStreamer buffer API 提交独立拥有像素存储的整帧，降低 GI 数据转换开销。推理仍异步读取原始重建灰度，显示写入不会修改推理输入。
9. 上位机 agent 默认改为 inframe 状态栏，并把处理队列和呈现队列的拥塞计数合计显示。源码、当前 EXE 的外置 agent 文件和板卡 agent 的 SHA256 已核对一致。

## 验证

- 从板卡取得三个真实完整帧，共九个 JPEG 分片。新原生解码与原 GStreamer 解码逐像素一致，最大差值均为 0。
- 损坏 JPEG 和尺寸不匹配被正确拒绝。
- 用分片/条带编号构造的数据验证完整 135 条带顺序及内容。
- 修改后的 Python 文件通过语法编译；启动 shell 通过 `sh -n`。
- 对照测试四个进程均正常退出，最后恢复常驻 AI 程序。PCIe 预处理及 JPEG 故障寄存器为 0。
- 修复版四十秒以上采集及最终 AI 对照没有软件采集队列丢弃，没有时间戳元数据丢弃。纯视频 unpaired=0，AI 对照 unpaired=2；后续七次常驻采样 unpaired=0。
- 最终模式和 QF 未被测试脚本改写；相邻四窗口始终为 mode 7、QF90。之前阶段性测试期间用户曾通过控制端更换模式，不将这些窗口视作固定配置对照。

## 仍有边界

- 呈现队列仍出现少量拥塞事件。AI 对照累计 11 次，恢复常驻后的一个约 30 秒采样窗口从 16 增至 30。拥塞事件不应直接当作精确丢帧数；也不能据此宣称完全零丢帧。
- `fpsdisplaysink dropped=0` 不包含上游 leaky 队列丢弃。状态栏 FPS:60 是用户要求的静态标识，实际帧率看日志/上位机。
- 当前改善为稳定阶段接近 60 FPS，不是全时段严格 60 张独立画面、绝对零丢帧的保证。
- 驱动 DMA 完成时间仍不是源帧 SOF 时间。6 ms 配对依赖正常传输完成时间差较小；极端的整帧 DMA 延迟仍可能造成歧义。完全无歧义配对最终需要源帧编号，本次按要求没有修改 FPGA RTL，也没有修改内核驱动。
- 波浪消失的实机反馈支持本次组合修复有效，但没有单独证明“配对”与“取消混帧”各自贡献多少。

## 文件

- `source/`：本次完整工作源码快照。后续 RK 修复应以这里或修复 tar 为准，历史根目录脚本/旧发布包未全部覆盖。
- `rk_hdmi_fix_20261013.tar.gz`：已在板卡编译的修复文件与动态库，覆盖安装路径 `/root/jpeg_rk`；这是增量修复包，依赖原有模型、驱动及系统库。
- `rollback.tar.gz`：修改前板卡顶层源码、相关动态库、状态平面程序和原 active_ai_plugins 快照。
- `evidence.tar.gz`：所有阶段及最终对照日志、采样 JSON、九个 JPEG 分片和三个重建 PGM。
- `regression_summary.json`：四个相邻对照窗口的日志与前后寄存器状态。
- PC 兼容包：`E:/FPGA/workspace/rk_serial_host/releases/RKVisionHost_20261013_hdmi_fix.zip`。EXE 主体未变化，更新其外置 board_agent.py，避免重连时恢复旧的状态平面启动配置。

板卡上同时保存了 `/root/jpeg_rk/hdmi_fix_20261013/` 的回退包和证据。

## 回退方法

先用上位机停止 RK 显示/推理，确认没有 viewer。然后在 RK shell 执行：

```sh
tar -xzf /root/jpeg_rk/hdmi_fix_20261013/rollback.tar.gz -C /root/jpeg_rk
rm -f /root/jpeg_rk/active_ai_plugins/libgstrktemporalgray.so
rm -f /run/jpeg-rk-gst-registry.bin /run/jpeg-rk-ai-gst-registry.bin
```

上面的第一个删除项是本次新加到 active_ai_plugins 的库；原快照只有 AI temporal/status 两个库。
随后使用原 `RKVisionHost_20261013.zip` 中的上位机启动，或通过原有 shell 启动脚本运行旧版。
无需重烧 FPGA 或模型。

## SHA256

- 修复 tar：`172204ff4b579618096eb1d15ab1d83b6f86d5e53fdbba633842b84259e333fb`
- 回退 tar：`b6e6117b09df3d2874e2f35333988685682424d24acba5fe59060c7feb72f7c2`
- 三处一致的 board_agent.py：`fd8aa7790a6f8790fb70137b8bcc31038af4c730d9c0ca990f0f3e238cc6b9b1`
