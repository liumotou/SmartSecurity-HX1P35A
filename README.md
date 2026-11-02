# 智能安防 完整提交工程

本目录为20261027-scene-metrics原字号版的独立提交工程，适用于HX1P35A开发板、SC500CS摄像头和HDMI显示设备。FPGA器件为PH1P35MDG324，速度等级-3，有效输出1280×720。保留原字号OSD，未采用20261102小字版。

## 目录

```text
lab_ex3_osd/
  td_project/               TD工程与顶层时钟约束
  user_source/
    hdl_source/             Verilog/SystemVerilog、厂商加密核和ROM数据
    ip_source/              PLL、DDR接口配套FIFO等厂商IP及配置
    constraints_source/     原版引脚约束
scripts/                    完整构建脚本
config/                     引脚映射依据与原版构建输入哈希
su03t/                      SU-03T配套配置、固件与厂商烧录说明
bitstream/                  SMART_SECURITY_HX1P35A.bit及本次构建结果摘要
README.md                   本说明
```

工程入口：`lab_ex3_osd/td_project/camera_to_dsi_display.al`。顶层：`design_top_wrapper`。

提交包不包含testbench、tests、仿真脚本、历史版本、备份、报告制作工具或调试截图。`raw_pattern_gen.v`为板上K3切换的内置图源功能，属于实际工程，不是testbench。厂商IP的RTL、头文件、配置和初始化数据必须随工程保留。

## 编译环境

- Windows，安路Tang Dynasty TD 6.2，器件库需包含PH1P35MDG324，并配置有效许可证。原工程记录版本为6.2.168116。
- Python 3.9或更新版本，仅使用标准库，不需要安装Python第三方包。
- 推荐将完整文件夹放在无空格、无中文的路径，保留内部层级。

## 从源码完整编译

在本目录打开PowerShell，执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_td.ps1 -Stage full -TdRoot D:\arch
```

将`D:\arch`换成TD实际安装根目录，该目录下应有`bin\run.exe`。如果Python未在PATH中，显式提供解释器路径：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_td.ps1 -Stage full -TdRoot D:\arch -PythonExe "D:\Python\python.exe"
```

脚本相对自身定位工程，生成仅供当前构建使用的绝对路径工程，执行综合、优化、布局、布线、最终时序检查和bit生成。DDR2专用ADC/SDC及FIFO约束在Tcl中加载，不要只导入顶层Verilog另建一个空工程。脚本同时检查语音GPIO映射与源文件在构建期间是否变化。

产物：

- `build/td/video_tracking.bit`：此次重新编译生成的FPGA配置文件。
- `build/td/console.log`：完整TD日志。
- `build/td/video_tracking_phy.area`：物理资源报告。
- `build/td/video_tracking_pr.timing`：最终时序报告。
- `build/td/build_manifest.json`：构建完成、时序通过及输入文件哈希记录。

完整编译以日志中的`HX_BUILD_PASS`及清单中的`download_ready: true`共同判断成功。仅执行`-Stage syn`只完成综合，不产生可下板结果。TD GUI可打开上述`.al`查看工程、源码和约束；提交包的完整复现方式以上述构建脚本为准。

## 下板

1. 给HX1P35A正确供电，连接板卡支持的JTAG下载器、SC500CS与HDMI显示设备。
2. 在TD配套配置/下载工具中识别JTAG链，选择PH1P35MDG324及`bitstream`中的交付`.bit`；也可选择自己完整编译得到的`build/td/video_tracking.bit`。
3. 执行FPGA配置，完成后复位并观察摄像头画面及左上角状态字段。直接配置FPGA的SRAM为易失下载；掉电保持应使用板卡配套的Flash配置流程及正确Flash型号。
4. 语音模块使用独立SU-03T固件，不通过FPGA的JTAG烧录。详见下节。

本次为工程编译验证，没有通过远程工具执行实际JTAG下载。

## 操作与引脚

| 输入 | 功能 | FPGA封装管脚 |
|---|---|---|
| K1短按 | COL→GRY→BIN→EDG→OVL→MOT→TRK循环 | D5 |
| K1长按约1秒 | CENTER→LEFT→RIGHT→FULL警戒区循环 | D5 |
| K2短按 | TH按1→2→0循环 | A9 |
| K2长按约1秒 | 数字白平衡开关 | A9 |
| K3 | 摄像头/内置图源切换 | B9 |
| 布防输入I_arm | 允许/禁止运动报警 | A4 |
| 语音事件I_voice_next | 稳定高脉冲触发下一模式 | V2 |
| 蜂鸣器O_buzzer_n | 低有效报警输出 | C12 |
| LED O_led | 报警反馈 | D10 |

表中是FPGA封装管脚，不是排针序号。原引脚与时钟约束保持不变。语音GPIO采用LVCMOS33电平，与FPGA共地，不能将5V信号直接送入FPGA输入。依据原理图，V2对应J1 pin1/GPIOA0；连接时按实际板卡版本核对接口。

MOT为运动区域联合框，不是人体类别识别；TRK为单红色标记跟踪。运动区域检测驱动报警，红色坐标用于屏幕显示。LAT为内部缓存与处理链路延迟，不包含曝光与显示器扫描；FPS包含重复刷新，NEW为有效送显ID更新计数。

## SU-03T语音固件

`su03t/firmware_20261017002/`同时提供平台导出JSON与两个厂商固件：

- `jx_su_03t_release_update.bin`：SU-03T串口升级固件。
- `jx_su_03t_release.bin`：SU-03T专用烧录器固件。
- `readme.txt`：厂商原始说明，明确区分串口升级与烧录器文件。

唤醒词“你好安防”；命令词“下一个模式”和“切换模式”。GPIO_B2空闲低、识别后高约100ms，接至FPGA的I_voice_next并正确共地。配置内容见`command_words.txt`及同目录的平台导出JSON。语音模块的识别在SU-03T侧执行，FPGA只接收模式切换GPIO事件。请使用与烧录方式对应的固件，不互换两种bin。

## 整理范围

原始工程、原字号版交付目录和小字版均保持原样。本提交工程只作路径适配：TD工程根路径使用相对定位，Logo初始化文件随工程提供，构建脚本允许指定TD和Python位置。未改变算法、字符尺寸、按键、管脚约束和时钟约束。原版输入文件哈希保存在`config/original_build_inputs.json`，交付文件哈希见`FILES.sha256`。重新构建后产生的build目录是可再生的中间产物，无需作为源代码提交。


## 提交目录完整编译验证

2026-11-03已从本提交目录完成一次完整TD构建，日志标记为`HX_BUILD_PASS`，构建清单`download_ready=true`。本节记录是软件构建验证，不表示执行了实际JTAG下载。

- 建立余量SWNS：1.139ns；保持余量HWNS：0.02ns。
- Slice：15154；LUT6：13651；寄存器：13246；ERAM：69；DSP：14。
- 交付bit：`bitstream/SMART_SECURITY_HX1P35A.bit`，1789539字节。
- SHA256：`27566cc8489f92325bd782be9d816d8a481037d562f4ef70bf848c89863fb8f7`。
- 本次bit与10月27日原始交付bit哈希不同；以上述本次完整构建记录为准。
- 整理前171项原始构建输入重新核对一致；提交包仅两项路径适配，其余原始构建输入保持逐字节一致。
