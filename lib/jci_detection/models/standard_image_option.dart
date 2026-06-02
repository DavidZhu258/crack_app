/// JCI 标准样图选项。
class JciStandardImageOption {
  /// 创建标准样图选项。
  const JciStandardImageOption({
    required this.label,
    required this.description,
    required this.assetPath,
  });

  /// 用户可见名称。
  final String label;

  /// 用户可见说明。
  final String description;

  /// assets 中的图片路径。
  final String assetPath;
}

/// JCI 检测流程内置标准样图。
const jciStandardImageOptions = <JciStandardImageOption>[
  JciStandardImageOption(
    label: '标准样图 1',
    description: '标准掌子面样图，适合快速验证识别流程',
    assetPath: 'assets/images/test/0_slide.jpg',
  ),
  JciStandardImageOption(
    label: '标准样图 2',
    description: '裂隙纹理较丰富，适合检查分窗识别效果',
    assetPath: 'assets/images/test/14.jpg',
  ),
  JciStandardImageOption(
    label: '标准样图 3',
    description: '真实 App ONNX 对比样本，适合联调验证',
    assetPath: 'assets/images/test/standard_03.jpg',
  ),
];
