# 配套RK版本

配套部署包存储于：

`E:\FPGA\workspace\road_damage_yolov8n\releases\rk3576_yolov8n_ehp2_k1_20261010.zip`

ZIP SHA256：`0d8c4753aff5134bdc2ed04e94ee6484451da5593ae1310f2e9c98d0450debe3`。

包内包含RK3576/Linux6.1.99对应的模型、NPU运行库、PCIe/JPEG驱动、HDMI/YOLO程序、源码、恢复脚本及逐文件校验。当前模型为原六类YOLOv8n灰度640×640 INT8，interval2，置信度0.10。

K1位于RK GPIO1_B7 / Linux47、低有效：短按松开循环QF30..90，长按约1.2秒循环八种预处理，一次按住只切一次。左上角第三行PREPROC读取0x100实际生效模式，状态图层600×124、1Hz刷新。

本工程 `deploy` 提供最新版三个PCIe/K1控制脚本；完整RK部署以独立ZIP及其README为准。FPGA综合不读取这个外部目录。保存 `reports/board` 中的K1软件回放、实际PCIe切换及状态图层证据；物理按键最终用户反馈在整理时尚未收到。

默认推荐恢复到高斯+CLAHE、QF90、60FPS输入选择后启动原HDMI+YOLO。重新烧录可能使PCIe BAR/Mem/BusMaster配置失效，按部署包说明恢复endpoint和原驱动后再启动，避免重复启动占用同一视频设备。
