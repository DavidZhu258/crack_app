# 离线模型准备指南

本项目开源仓库不包含我们的预训练模型。代码保留手机端离线 ONNX 推理能力，
但模型权重需要使用者自行准备。

## 模型放置位置

App 默认离线模型路径为：

```text
assets/models/savss_256.onnx
```

开源仓库只保留 `assets/models/README.md`、`.gitkeep` 和标签占位文件，不提交
`.onnx`、`.pt`、`.ptl`、`.pth`、`.om` 等模型或转换产物。

## 模型接口要求

当前离线推理服务按以下接口加载 ONNX：

```text
input:  [1, 3, 256, 256]
output: [1, 1, 512, 512]
```

预处理采用 ImageNet 均值和方差归一化。输出经 sigmoid 后用于裂隙掩膜和
结果图生成。

## 使用自己的模型

1. 导出兼容 ONNX 模型。
2. 将文件命名为 `savss_256.onnx`。
3. 放入 `assets/models/`。
4. 执行：

```powershell
flutter pub get
flutter run --flavor production -t lib/main_production.dart
```

## 开源发布注意事项

- 不要提交任何预训练权重、转换模型、校准数据或 APK 构建产物。
- `.gitignore` 已经显式排除常见模型格式和 `artifacts/`。
- 成果展示可使用 `docs/showcase/` 下的界面截图、测试样图和图标。
- 没有本地模型时，请使用 App 中的服务器推理入口，或自行配置可访问的推理服务。

## 服务器推理

服务器推理入口由 API 提供，不依赖公开仓库中的本地 ONNX 文件。开发环境可以通过：

```powershell
flutter run --flavor production -t lib/main_production.dart `
  --dart-define=CRACK_API_BASE_URL=https://api.example.com
```

将 `CRACK_API_BASE_URL` 替换为自己的后端地址。
