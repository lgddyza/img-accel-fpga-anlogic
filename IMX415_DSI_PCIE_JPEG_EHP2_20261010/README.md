# 最新FPGA工程：EHP2 / 1080P JPEG / PCIe

整理日期：**2026-10-10**。入口为本目录 [fpga_prj_jpeg.al](fpga_prj_jpeg.al)。当前设计为已经烧录并完成RK通路测试的EHP2：共享3×3窗口、黑帽K3 gain1、增强后可选CLAHE、八模式动态选择。

## 在TD中打开

1. 关闭或切离旧工程，在TD选择本目录的 `fpga_prj_jpeg.al`。
2. 顶层保持 `system_top`，器件 **PH1A90SEG324-2**，工具为TD **Release_2026.1_SP2 / 6.2.2.200067**。
3. 后续修改直接在本目录进行。从Synthesis开始运行，随后布局布线、检查setup/hold、生成bit。
4. 新运行结果会出现在TD创建的 `fpga_prj_jpeg_Runs`；本次固定版本的烧录文件保存在 `output`，两者用途不同。

工程保留原相对路径和编译顺序，`.al`工程根路径已改为本目录。143个RTL/IP/约束及配套数据依赖从最新工程复制，设计源码未修改。106个项目登记引用与最终物理Run的登记清单一致。

## 当前可烧录文件

- [标准bit](output/fpga_prj_jpeg.bit)：4,850,318字节。
- [压缩bit](output/fpga_prj_jpeg_compress.bit)：4,632,896字节。

来自旧工程 `fpga_prj_jpeg_Runs/phy_1`，生成时间2026-10-10 00:41；与该工程 `best_result` 的文件SHA256一致。这里的bit是原已生成版本的复制，没有为整理重新生成。

标准bit SHA256：`f961fd58ddcb4fbfee03d2f5913d9ff8f7c64745df49b2c02fec32bec16ffdc4`。压缩bit校验值及所有文件见 [CHECKSUMS.sha256](CHECKSUMS.sha256)。

FPGA回读应为 `0xAC=0x45485032`（EHP2），`0x104=0xff`（八模式）。这用于确认功能版本；没有从板卡JTAG读回bit做逐字节比对。

## 目录用途

| 目录/文件 | 内容 |
| --- | --- |
| `fpga_prj_jpeg.al` | 唯一TD工程入口 |
| `uisrc/01_rtl` | 本项目RTL，主要修改入口是system_top和gray_preprocess4 |
| `uisrc/03_ip`、`al_ip` | 工程引用的厂商IP、生成文件及初始化数据 |
| `uisrc/04_pin` | 引脚与时序约束 |
| `third_party/mjpegZero` | 当前JPEG编码核、上游说明和许可证 |
| `output` | 本次EHP2标准/压缩bit |
| `reports/final` | 对应bit的最终面积、时序和运行报告，原构建清单 |
| `reports/simulation` | 原版完整1080p像素/JPEG和小帧仿真证据 |
| `reports/verification` | 整理后新目录的检查、回归和TD展开结果 |
| `reports/board` | 道路测试量化数据、K1软件/PCIe切换和状态图层证据 |
| `sim` | 当前EHP2三套测试台和小帧参考向量 |
| `tools` | 项目校验、八模式回归、完整1080p仿真、TD载入检查 |
| `deploy` | 最新RK预处理、QF及K1控制脚本 |
| `docs` | 当前结构、寄存器、资源和配套RK版本说明 |
| `manifest.json` | 每个复制文件的来源、角色、SHA256及bit版本 |
| `build` | 本目录验证产生的临时文件；不是工程源文件 |

TD仍登记了部分自动排除的兼容模块；为保持项目清单和编译语义，保留这些登记文件。算法主体集中在已登记的 `gray_preprocess4.v`，不需要再登记旧独立增强模块。

## 功能与资源

共享原灰度3×3窗口并行产生灰度、高斯、Sobel和黑帽首级膨胀。黑帽第二级腐蚀及四方向line5响应滤波有独立缓存。按输入帧SOF选中一支，再经过共享CLAHE或直通，最终单路视频送三路交织JPEG编码/PCIe。

模式：0灰度、1高斯、2CLAHE、3高斯+CLAHE、4Sobel、5黑帽、6Sobel+CLAHE、7黑帽+CLAHE。Sobel T1 gain0.5；黑帽K3 gain1 +四方向line5。详情见 [当前设计说明](docs/EHP2_DESIGN.md)。

| 最终物理资源 | 使用 / 容量 |
| --- | --- |
| Slice | 51,792 / 64,320（80.52%） |
| ERAM20K | 259 / 272（95.22%） |
| DSP | 122 / 240（50.83%） |
| setup WNS / hold WNS | +0.093 ns / +0.020 ns，STNS/HTNS均0 |

资源和时序是复制的最新已完成物理报告，不是本次整理重新布局布线的结果。ERAM余量13块，时序裕量较小。

## 已完成的整理验证

- 106个项目登记引用、生成IP和初始化数据存在；143个设计依赖及所有复制文件的SHA256与来源一致。
- 标准/压缩bit与原 `phy_1`、`best_result` 一致，设计依赖没有比bit生成时间更晚的修改。
- TD从本工程根目录载入并完整展开 `system_top` 成功，DDR/MIPI等厂商模块正常载入。工具仍报告原设计/厂商代码中的警告；没有缺失模块黑盒错误。
- 新目录八模式17帧回归通过，覆盖像素参考、CLAHE、边界、valid空隙与SOF模式锁存。
- RK控制脚本模式兼容/非法组合检查通过。

本次没有重跑完整综合、布局布线、生成bit或再次烧录。验证证据见 `reports/verification`。

## 可重复检查

在本工程根目录运行，Python环境需安装NumPy和OpenCV。当前使用原训练虚拟环境，也可使用自己的Python环境。

```powershell
python tools/validate_project.py
python tools/check_enhance_control.py
python tools/run_small_regression.py
python tools/run_td_check.py
```

Icarus默认从相邻 `.tools/iverilog/bin` 查找，也可用 `--iverilog` 指定。TD默认路径 `F:/FPGA/AnLu/bin/td_commands_prompt.exe`，可通过 `--td` 指定。TD需要从工程根目录载入；从子目录直接调用绝对路径工程可能漏读SystemVerilog源。

`validate_project.py`是此固定版本的完整性检查；后续有意编辑源码后，出现SHA不匹配是预期结果，应为新版本生成新的清单，而不是继续声称与此次版本相同。

可选完整1080p仿真（耗时较长，使用Vivado2018.3 xsim）：

```powershell
python tools/run_ehp2_sim.py pixels
python tools/run_ehp2_sim.py jpeg
python tools/verify_ehp2_jpeg.py
```

## 配套RK部署包

同一版本RK程序已存储在相邻视觉项目的 `releases/rk3576_yolov8n_ehp2_k1_20261010.zip`，约5.9MB，含模型、NPU运行库、驱动、HDMI/YOLO和K1/状态显示程序。详见 [RK配套说明](docs/RK_COMPANION.md)。FPGA综合不依赖这个包，也不依赖旧FPGA工程或训练工程目录。
