# HDMI同源预览修复记录

日期：2026-10-14。首次视频版回退后用户仍报告预览明显闪烁，并明确HDMI正常，要求使用与HDMI相同的视频流。当前已按该要求部署新的RK预览模块。

## 实际通路

旧预览并非直接转发PCIe数据。原HDMI通路先重建三路JPEG、进行normalize时域处理、叠加文字及检测框，然后分出GRAY8预览支路。该支路独立排队，使用identity sleep-time=66667节流，再缩放、JPEG编码；HDMI继续转换RGBx、经过呈现队列、送入KMS显示。

新预览取消该支路，在实际HDMI视频sink的输入pad处保留最终帧引用。预览因此读取HDMI显示器输入端收到的同一份RGBx像素，包含原时域处理、OSD、格式转换及主呈现队列筛选的结果。固定每四个60 FPS输入帧选一个；将选中帧交给独立管线缩放至960×540、转灰度、JPEG quality80编码后发送。源为30 FPS时每两帧选一个。

这保证预览来自最终HDMI输入数据，但不是外部仪器测量的显示器scanout记录，也不是物理屏幕截图。取帧位置与节流方式同时调整；没有隔离它们各自对主观闪烁的贡献，不能将唯一原因确定为PCIe错误。

## 边界与资源

- 仅替换 `/root/jpeg_rk/network_preview.py`。两份HDMI查看器、PCIe采集、控制agent及原生提交程序的部署前后SHA256一致，见 `deployment.json`。
- 未修改时域插件、模型、FPGA RTL/bit、驱动或JPEG重建方式；PC不使用亮度LUT补偿或跨帧混合。
- 保留首次版PC界面和控制程序，仅增加“HDMI 同源预览”标题用于区分窗口。
- HDMI回调仅保留独立帧元数据及像素内存引用；缩放、编码和网络发送不在HDMI回调中执行。输入队列和应用mailbox有界，慢客户端跳过旧帧。
- 使用 `gst_buffer_copy_region`复制帧元数据并引用受GStreamer生命周期管理的像素存储；不使用PyGObject通用boxed copy改写原帧PTS。
- 部署重启viewer一次，重启期间HDMI短暂停顿。保留当时Sobel模式4、QF80、输入60 FPS、interval2、confidence0.1、connector188；现场用户后续设置由用户控制。

## 验证

板卡隔离GStreamer管线用120个交替明暗RGBx帧验证，检查了30个编码帧：最终sink像素、原HDMI缓冲PTS保持不变；每四帧选一帧且源PTS对应；黑色细线和纯白区域保持；停止输入后不会伪造重复实时帧。测试脚本为 `test_hdmi_preview_pipeline.py`，测试未使用生产PCIe采集器。

相邻现场采样见 `before_current/analysis.json` 与 `after_final_hdmi/analysis.json`：旧版133帧平均间隔74.69毫秒，新版299帧平均间隔66.54毫秒。两段末次HDMI均为60 FPS。中心平均灰度仍会受文字和白框出现/消失影响，不将中心均值跳变直接当作背景闪烁。

排除近黑/近白像素及两端各10%差值后，固定区域背景亮度相邻跳变RMS从0.6159降至0.0236，降低约96.2%；相邻像素差的中位数RMS由0.7124降至0。方法与数据在 `background_comparison.json`，可用 `analyze_preview_background.py`复算。这是相邻时间窗口、当前静止场景的结果，不是同一录像逐帧对照，也不能代替用户对原道路拍屏场景的肉眼验收。

正式EXE连接和连续预览测试退出码0，见 `exe_check/`。末次预览14.55 FPS、HDMI60.0 FPS、YOLO30.35 FPS。短窗HDMI读数出现58.5～60.6 FPS，因此不宣称全时段严格60个独立画面，也不将超过60的短窗计数视作显示器刷新率提升。

已打开带“HDMI 同源预览”标题的窗口接收新通路，正在等待用户确认主观闪烁是否消失。没有收到该确认前，不宣称所有场景已消除闪烁。

## 使用与回退

本机 `launch.cmd`默认打开 `dist_hdmi_preview/RKVisionHost/RKVisionHost.exe`。正式发布包为 `releases/RKVisionHost_20261014_hdmi_source_mjpeg.zip`，含PC程序、源码、RK预览模块、校验表及验证报告。该包依赖既有完整RK环境，不包含模型和内核驱动。

如需回退本次板端变更，保留现场运行参数、停止viewer，恢复 `before_network_preview.py` 为 `/root/jpeg_rk/network_preview.py` 后按原参数启动。仅使用首次视频版PC程序不会自动回退RK预览模块。首次发布包及回退记录仍保留。
