import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:crack_app/crack_detection/cubit/crack_detection_cubit.dart';
import 'package:crack_app/crack_detection/cubit/crack_detection_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

void _log(Object? message) {
  developer.log('$message', name: 'CrackDetectionPage');
}

/// 裂缝检测页面
///
/// 功能：
/// ✅ 完全离线运行 - 无需网络
/// ✅ 拍照检测
/// ✅ 相册选择检测
/// ✅ 实时显示检测结果
class CrackDetectionPage extends StatelessWidget {
  const CrackDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = CrackDetectionCubit();
        // 自动加载模型
        unawaited(cubit.initializeModel());
        return cubit;
      },
      child: const CrackDetectionView(),
    );
  }
}

class CrackDetectionView extends StatelessWidget {
  const CrackDetectionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('裂缝检测 (离线)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<CrackDetectionCubit>().reset(),
            tooltip: '重置',
          ),
        ],
      ),
      body: BlocBuilder<CrackDetectionCubit, CrackDetectionState>(
        builder: (context, state) {
          return Column(
            children: [
              // 状态指示器
              _buildStatusBar(state),

              // 主内容区域
              Expanded(
                child: _buildContent(context, state),
              ),

              // 底部操作按钮
              _buildActionButtons(context, state),
            ],
          );
        },
      ),
    );
  }

  /// 状态栏
  Widget _buildStatusBar(CrackDetectionState state) {
    String statusText;
    Color statusColor;

    switch (state) {
      case CrackDetectionModelLoading():
        statusText = '📦 正在加载模型...';
        statusColor = Colors.orange;
      case CrackDetectionModelLoaded():
        statusText = '✅ 模型已就绪 (离线模式)';
        statusColor = Colors.green;
      case CrackDetectionInProgress(statusText: final progressText):
        statusText = '🔍 $progressText';
        statusColor = Colors.blue;
      case CrackDetectionSuccess():
        statusText = '✅ 检测完成';
        statusColor = Colors.green;
      case CrackDetectionModelLoadError():
        statusText = '❌ 模型加载失败';
        statusColor = Colors.red;
      case CrackDetectionError():
        statusText = '❌ 检测失败';
        statusColor = Colors.red;
      default:
        statusText = '📱 离线裂缝检测系统';
        statusColor = Colors.grey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: statusColor.withValues(alpha: 0.1),
      child: Text(
        statusText,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: statusColor,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 窗口数量选择器
  Widget _buildWindowsSelector(BuildContext context) {
    final cubit = context.read<CrackDetectionCubit>();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '检测精度设置',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '窗口数: ${cubit.maxWindows}',
                  style: const TextStyle(color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('快速', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: cubit.maxWindows.toDouble(),
                    min: 1,
                    max: 64,
                    divisions: 63,
                    label: '${cubit.maxWindows}',
                    onChanged: (value) {
                      cubit.setMaxWindows(value.toInt());
                      // 触发重建
                      (context as Element).markNeedsBuild();
                    },
                  ),
                ),
                const Text('精确', style: TextStyle(fontSize: 12)),
              ],
            ),
            Text(
              '窗口数越多精度越高，但耗时更长',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  /// 主内容区域
  Widget _buildContent(BuildContext context, CrackDetectionState state) {
    return switch (state) {
      CrackDetectionModelLoading() => const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载离线模型...'),
          ],
        ),
      ),
      CrackDetectionModelLoaded() => SingleChildScrollView(
        child: Column(
          children: [
            _buildWindowsSelector(context),
            const SizedBox(height: 40),
            const Icon(Icons.camera_alt, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '选择图片开始检测',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '✅ 完全离线 - 无需网络',
              style: TextStyle(color: Colors.green),
            ),
          ],
        ),
      ),
      CrackDetectionInProgress(
        imagePath: final path,
        progress: final progress,
        currentWindow: final current,
        totalWindows: final total,
        statusText: final status,
      ) =>
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.file(File(path), height: 150),
              const SizedBox(height: 16),
              // 进度条
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: total > 0 ? progress : null,
                      minHeight: 8,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (total > 0)
                      Text(
                        '窗口 $current / $total',
                        style: const TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '请耐心等待，AI正在分析图像...',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      CrackDetectionSuccess() => _buildSuccessView(context, state),
      CrackDetectionModelLoadError(error: final error) => _buildErrorView(
        error,
      ),
      CrackDetectionError(error: final error) => _buildErrorView(error),
      _ => const Center(child: Text('未知状态')),
    };
  }

  /// 成功视图
  Widget _buildSuccessView(BuildContext context, CrackDetectionSuccess state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 窗口选择器（方便再次检测时调整）
          _buildWindowsSelector(context),
          const SizedBox(height: 16),

          // 原始图片
          _buildImageCard('原始图片', File(state.originalImagePath)),
          const SizedBox(height: 16),

          // 检测结果图
          _buildResultImageCard('检测结果', state.resultImage),
          const SizedBox(height: 16),

          // 统计信息
          _buildStatsCard(state),
          const SizedBox(height: 16),

          // 保存按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _saveResult(context),
              icon: const Icon(Icons.save),
              label: const Text('保存检测结果'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // JCI 分析按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.binaryMask != null
                  ? () => _showJciAnalysisDialog(context)
                  : null,
              icon: const Icon(Icons.analytics),
              label: const Text('JCI 分析'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
            ),
          ),

          // JCI 结果展示
          if (state.jciResult != null) ...[
            const SizedBox(height: 16),
            _buildJciResultCard(state.jciResult!),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _saveResult(BuildContext context) async {
    final cubit = context.read<CrackDetectionCubit>();
    final path = await cubit.saveResultImage();
    if (!context.mounted) return;
    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存到: $path'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存失败，请重试'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// JCI 分析参数输入对话框
  void _showJciAnalysisDialog(BuildContext context) {
    final cubit = context.read<CrackDetectionCubit>();
    final depthController = TextEditingController(text: '300');
    final pixelRatioController = TextEditingController(text: '0.24');
    var hasSeepage = false;

    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              return AlertDialog(
                title: const Text('JCI 分析参数'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: depthController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '工程埋深 (m)',
                          hintText: '例如: 300',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: pixelRatioController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '像素比例 (cm/像素)',
                          hintText: '例如: 0.05',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('是否渗水'),
                        subtitle: const Text('渗水会导致围岩等级降级'),
                        value: hasSeepage,
                        onChanged: (v) => setState(() => hasSeepage = v),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final depth =
                          double.tryParse(depthController.text) ?? 300;
                      final pixelRatio =
                          double.tryParse(pixelRatioController.text) ?? 0.24;
                      Navigator.pop(dialogContext);
                      unawaited(
                        cubit.runJciAnalysis(
                          depth: depth,
                          pixelRatio: pixelRatio,
                          hasSeepage: hasSeepage,
                        ),
                      );
                    },
                    child: const Text('开始分析'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// JCI 分析结果卡片
  Widget _buildJciResultCard(CrackDetectionJciResult jciResult) {
    return Card(
      color: Colors.deepPurple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'JCI 分析结果',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),

            // 核心指标
            _buildStatRow('JCI 值', jciResult.jciValue.toStringAsFixed(2)),
            _buildStatRow('围岩等级', jciResult.rockGrade),
            _buildStatRow('等级描述', jciResult.rockGradeDescription),
            if (jciResult.wasDowngraded && jciResult.finalGrade != null)
              _buildStatRow('降级详情', jciResult.finalGrade!),
            const Divider(),

            // 中间计算值
            const Text(
              '计算参数',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            _buildStatRow('RMR', jciResult.rmr.toStringAsFixed(2)),
            _buildStatRow('Q 值', jciResult.qValue.toStringAsFixed(4)),
            _buildStatRow('g(Q)', jciResult.gQ.toStringAsFixed(2)),
            _buildStatRow('h(S)', jciResult.hS.toStringAsFixed(2)),
            const Divider(),

            // 三大指标
            const Text(
              '三大指标',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            _buildStatRow(
              '指标1 (条/m²)',
              jciResult.indicator1.toStringAsFixed(4),
            ),
            _buildStatRow(
              '指标2 (cm)',
              jciResult.indicator2.toStringAsFixed(2),
            ),
            _buildStatRow(
              '指标3 (%)',
              jciResult.indicator3.toStringAsFixed(2),
            ),
            const Divider(),

            // 裂缝统计
            _buildStatRow('裂缝数量', '${jciResult.crackCount} 条'),
            _buildStatRow(
              '裂缝总长',
              '${jciResult.totalCrackLengthCm.toStringAsFixed(1)} cm',
            ),
            const Divider(),

            // 支护方案
            const Text(
              '支护方案',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              jciResult.supportSummary,
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (jciResult.supportMethods.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...jciResult.supportMethods.map(
                (m) {
                  final parameterText = m.parameters.entries
                      .map((e) => '${e.key} ${e.value}')
                      .join(', ');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${m.name}: $parameterText',
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageCard(String title, File imageFile) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Image.file(imageFile),
        ],
      ),
    );
  }

  Widget _buildResultImageCard(String title, Uint8List imageData) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Image.memory(imageData),
        ],
      ),
    );
  }

  Widget _buildStatsCard(CrackDetectionSuccess state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              '检测统计',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildStatRow('裂缝占比', '${state.crackRatio.toStringAsFixed(2)}%'),
            _buildStatRow('检测耗时', '${state.inferenceTime} ms'),
            _buildStatRow('检测数量', '${state.detectionCount} 处'),
            _buildStatRow('窗口数量', '${state.maxWindowsUsed}'),
            const SizedBox(height: 8),
            const Text(
              '✅ 完全离线检测',
              style: TextStyle(color: Colors.green, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 80, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              '错误',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部操作按钮
  Widget _buildActionButtons(BuildContext context, CrackDetectionState state) {
    final cubit = context.read<CrackDetectionCubit>();
    final isReady =
        state is CrackDetectionModelLoaded || state is CrackDetectionSuccess;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isReady ? cubit.detectFromCamera : null,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('拍照检测'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isReady ? cubit.detectFromGallery : null,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('相册选择'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isReady ? () => _showTestImagePicker(context) : null,
              icon: const Icon(Icons.image),
              label: const Text('使用测试图片'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTestImagePicker(BuildContext context) {
    _log('📋 显示测试图片选择器');
    final cubit = context.read<CrackDetectionCubit>();
    final testImages = [
      {'name': '测试图片 3 (14.jpg) - 先测试这个', 'path': 'assets/images/test/14.jpg'},
      {
        'name': '测试图片 1 (0_slide.jpg)',
        'path': 'assets/images/test/0_slide.jpg',
      },
      {'name': '测试图片 2 (1.jpg)', 'path': 'assets/images/test/1.jpg'},
    ];

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (BuildContext context) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择测试图片',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...testImages.map((image) {
                  return ListTile(
                    leading: const Icon(Icons.image, color: Colors.orange),
                    title: Text(image['name']!),
                    onTap: () {
                      _log('👆 点击了: ${image['name']}');
                      Navigator.pop(context);
                      // 使用外部保存的cubit引用
                      unawaited(cubit.detectWithTestImage(image['path']!));
                    },
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
