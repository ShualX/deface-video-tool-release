# 本地视频人脸打码工具

当前版本：`v0.2.0-alpha`

一个面向 Windows 的本地视频人脸打码工具，基于 Python `deface` 实现人脸检测与匿名化处理，并提供中文 PowerShell GUI 界面。适合批量处理视频、保留原音频、生成抽帧复查报告，帮助快速检查是否存在漏打码画面。

## 功能特点

- 中文 GUI，双击 `启动人脸打码工具.bat` 即可打开。
- 支持单个视频处理和批量处理 `input_videos` 文件夹。
- 默认保留原视频音频。
- 默认使用马赛克模式，支持薄码、标准马赛克、强遮挡、速度优先等预设。
- 所有核心参数可调：检测阈值、遮罩放大、推理分辨率、马赛克块大小、替换模式等。
- 自动检测 NVIDIA GPU，可用时支持 CUDA 推理加速。
- 支持 NVIDIA NVENC 硬件编码：`h264_nvenc` / `hevc_nvenc`。
- 支持输出文件处理策略：跳过已处理、直接覆盖、自动改名、手动询问。
- 支持处理完成后每隔指定秒数抽帧复查。
- 自动生成 `review.html` 复查报告，方便快速浏览抽帧结果。
- 支持停止当前处理任务。
- 自动保存上次使用的 GUI 参数。

## 目录结构

```text
.
├─ input_videos/          # 放入待处理视频
├─ output_videos/         # 输出打码后的视频
├─ review_frames/         # 抽帧复查图片和 review.html
├─ scripts/
│  ├─ deface_gui.ps1      # 中文 GUI 主程序
│  ├─ deface_one.ps1      # 处理单个视频
│  ├─ deface_batch.ps1    # 批量处理视频
│  ├─ review_frames.ps1   # 抽帧复查
│  └─ deface_common.ps1   # 公共函数
├─ .venv/                 # Python 虚拟环境
├─ 启动人脸打码工具.bat
└─ 启动人脸打码工具.ps1
```

## 快速开始

1. 首次使用请先安装基础环境。可以双击打开 GUI 后点击“安装基础环境”，也可以在 PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

2. 把视频放入：

```text
input_videos
```

3. 双击启动：

```text
启动人脸打码工具.bat
```

4. 在 GUI 中选择处理模式、打码预设和输出策略。

5. 点击“开始处理”。

6. 处理完成后，结果会输出到：

```text
output_videos
```

7. 如果启用了抽帧复查，复查图片和 HTML 报告会生成在：

```text
review_frames
```

## 命令行用法

处理单个视频：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deface_one.ps1 .\input_videos\example.mp4
```

批量处理：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deface_batch.ps1
```

抽帧复查：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\review_frames.ps1
```

薄码示例：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deface_one.ps1 `
  .\input_videos\example.mp4 `
  -ReplaceWith mosaic `
  -MosaicSize 6 `
  -MaskScale 1.15
```

GPU 推理 + NVENC 编码示例：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deface_one.ps1 `
  .\input_videos\example.mp4 `
  -UseGpu True `
  -Encoder h264_nvenc
```

## 主要参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `Thresh` | `0.15` | 人脸检测阈值，越低越容易检出，但误检可能增加 |
| `MaskScale` | `1.45` | 遮罩放大比例，越大遮挡范围越大 |
| `Scale` | `1280x720` | 模型推理分辨率，越低越快，但小脸更容易漏检 |
| `ReplaceWith` | `mosaic` | 替换模式：`mosaic`、`blur`、`solid`、`none`、`img` |
| `MosaicSize` | `20` | 马赛克块大小，越小越细，越大遮挡越强 |
| `KeepAudio` | `True` | 保留原视频音频 |
| `UseGpu` | `False` | 启用 CUDA 推理加速 |
| `Encoder` | `libx264` | 视频编码器，可选 `libx264`、`h264_nvenc`、`hevc_nvenc` |
| `ExistingAction` | `skip` | 输出文件已存在时的行为：覆盖、跳过、自动改名 |

## 打码预设建议

- 薄码：`MosaicSize=6`，`MaskScale=1.15`，观感轻，但匿名强度较弱。
- 标准马赛克：`MosaicSize=20`，`MaskScale=1.45`，推荐日常使用。
- 强遮挡：更大的马赛克块和遮罩范围，适合隐私优先场景。
- 速度优先：降低推理分辨率，适合快速批量处理，但建议加强复查。

## GPU 与硬件编码

工具会自动检测 NVIDIA GPU、ONNX Runtime CUDA Provider 和 NVENC 编码器。

如果 CUDA 可用，GUI 中可以勾选“使用 GPU 加速”。这会加速人脸检测推理。

如果 NVENC 可用，可以选择：

- `h264_nvenc`
- `hevc_nvenc`

NVENC 主要加速视频输出编码，不等同于人脸检测加速。

## 复查报告

处理完成后可以自动抽帧，例如每 5 秒抽一帧。工具会生成：

```text
review_frames/review.html
```

打开该 HTML 文件即可快速检查打码效果，确认是否存在漏打码画面。

## 注意事项

- 薄码更美观，但遮挡更弱，不适合高隐私要求场景。
- 自动人脸检测不保证 100% 无漏检，建议开启抽帧复查。
- GPU 推理依赖 NVIDIA 驱动、`onnxruntime-gpu`、CUDA/cuDNN 相关运行库。
- 某些视频编码格式可能需要重新编码或更换输出编码器。
- 本工具只在本地处理视频，不会主动上传视频文件。

## 依赖

- Windows PowerShell
- Python 虚拟环境 `.venv`
- `deface`
- `imageio-ffmpeg`
- 可选：`onnxruntime-gpu`、`onnx`、NVIDIA CUDA/cuDNN Python runtime packages

## 致谢

核心人脸匿名化能力基于开源项目 `deface`。本项目主要提供 Windows 本地化脚本、中文 GUI、批量处理、GPU/NVENC 检测、复查报告和易用工作流封装。
