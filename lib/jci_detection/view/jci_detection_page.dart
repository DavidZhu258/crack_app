/// JCI 检测页面
///
/// 实现先图像识别、后工程信息输入的 JCI 检测流程。
///
/// 需求:
/// - 1.1-1.5: 图像采集与管理
/// - 3.1-3.8: 工程信息输入与验证
/// - 4.3, 4.4: 显示 JCI 值和计算明细
/// - 5.8: 以醒目的颜色和图标显示围岩等级
/// - 6.4, 6.5: 显示渗水调整说明
/// - 7.1-7.3: 显示支护方案建议
/// - 8.1: 提供保存结果按钮
library;

import 'dart:async';
import 'dart:io';

import 'package:crack_app/core/api/api_client.dart';
import 'package:crack_app/core/network/network_status_service.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';
import 'package:crack_app/crack_detection/services/inference_router.dart';
import 'package:crack_app/crack_detection/services/local_inference_client.dart';
import 'package:crack_app/crack_detection/services/remote_inference_client.dart';
import 'package:crack_app/jci_detection/cubit/jci_detection_cubit.dart';
import 'package:crack_app/jci_detection/cubit/jci_detection_state.dart';
import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/form_validation_state.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/services/crack_identifier_service.dart';
import 'package:crack_app/jci_detection/services/image_analyzer_service.dart';
import 'package:crack_app/jci_detection/services/scanline_analyzer_service.dart';
import 'package:crack_app/jci_detection/services/support_advisor_service.dart';
import 'package:crack_app/jci_detection/view/jci_precision_selector.dart';
import 'package:crack_app/jci_detection/view/jci_result_images_section.dart';
import 'package:crack_app/jci_detection/view/jci_result_notice.dart';
import 'package:crack_app/jci_detection/view/jci_standard_image_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

/// JCI 检测页面
///
/// 提供 BlocProvider 包装的 JCI 检测视图。
class JciDetectionPage extends StatelessWidget {
  /// 创建 JCI 检测页面
  const JciDetectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    const maxInferenceWindows = int.fromEnvironment(
      'CRACK_JCI_MAX_WINDOWS',
      defaultValue: 4,
    );
    const serverBaseUrl = EnterpriseApiDefaults.baseUrl;
    final crackService = CrackDetectionService();
    final inferenceRouter = InferenceRouter(
      localClient: LocalInferenceClient(crackService),
      remoteClient: RemoteInferenceClient(
        dio: ApiClient(baseUrl: serverBaseUrl).dio,
      ),
      networkStatusService: ConnectivityNetworkStatusService(
        healthUrl: '$serverBaseUrl/health',
      ),
    );
    return BlocProvider(
      create: (_) {
        final cubit = JciDetectionCubit(
          imageAnalyzerService: ImageAnalyzerService(
            crackService: crackService,
            crackIdentifierService: const CrackIdentifierService(),
            scanlineAnalyzerService: const ScanlineAnalyzerService(),
            inferenceRouter: inferenceRouter,
            maxInferenceWindows: maxInferenceWindows,
          ),
          crackService: crackService,
        );
        // 自动加载模型
        unawaited(cubit.loadModel());
        return cubit;
      },
      child: const JciDetectionView(),
    );
  }
}

/// JCI 检测视图
///
/// 包含图像采集区域、工程信息表单和操作按钮。
class JciDetectionView extends StatefulWidget {
  /// 创建 JCI 检测视图
  const JciDetectionView({super.key});

  @override
  State<JciDetectionView> createState() => _JciDetectionViewState();
}

class _JciDetectionViewState extends State<JciDetectionView> {
  final _formKey = GlobalKey<FormState>();
  static const int _defaultMaxInferenceWindows = int.fromEnvironment(
    'CRACK_JCI_MAX_WINDOWS',
    defaultValue: 4,
  );

  // 表单字段控制器
  final _depthController = TextEditingController();
  final _locationController = TextEditingController();
  final _projectNameController = TextEditingController();
  final _inspectorController = TextEditingController();

  // 表单字段值
  RockType? _selectedRockType;
  WaterCondition _selectedWaterCondition = WaterCondition.dry;
  bool _hasSeepage = false;
  int _selectedMaxInferenceWindows = _defaultMaxInferenceWindows;
  bool _useServerHighestPrecision = true;

  @override
  void dispose() {
    _depthController.dispose();
    _locationController.dispose();
    _projectNameController.dispose();
    _inspectorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JCI 检测'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetForm,
            tooltip: '重置',
          ),
        ],
      ),
      body: BlocConsumer<JciDetectionCubit, JciDetectionState>(
        listener: (context, state) {
          if (state is JciDetectionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          // 需求 4.3, 5.8, 7.1: 检测成功时显示结果
          if (state is JciDetectionSuccess) {
            return _JciResultView(
              result: state.result,
              onSave: () => context.read<JciDetectionCubit>().saveResult(),
              onManualReview: (review) =>
                  context.read<JciDetectionCubit>().submitManualReview(review),
              onReset: _resetForm,
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 图像采集区域
                  _buildImageSection(context, state),
                  const SizedBox(height: 24),

                  if (state is JciDetectionParametersReady) ...[
                    _buildRecognitionParametersSection(state),
                    const SizedBox(height: 24),

                    // 工程信息表单
                    _buildEngineeringInfoForm(),
                    const SizedBox(height: 24),

                    // 计算分析按钮
                    _buildAnalyzeButton(context, state),
                  ] else if (_hasRecognitionImage(state)) ...[
                    _buildRecognizeButton(context, state),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建图像采集区域
  ///
  /// 需求 1.1: 显示识别图像采集区域
  Widget _buildImageSection(BuildContext context, JciDetectionState state) {
    String? image1Path;

    if (state is JciDetectionImagesSelected) {
      image1Path = state.image1Path;
    } else if (state is JciDetectionParametersReady) {
      image1Path = state.image1Path;
    } else if (state is JciDetectionError) {
      image1Path = state.image1Path;
    } else if (state is JciDetectionAnalyzing) {
      image1Path = state.image1Path;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '掌子面图像采集',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // 需求 1.4: 未选择识别图像时显示提示
        if (image1Path == null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '请先选择掌子面图像，完成识别后再填写工程信息',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _buildImageCaptureArea(
          context: context,
          index: 1,
          label: '掌子面识别图像',
          imagePath: image1Path,
        ),
        const SizedBox(height: 12),
        JciStandardImageSelector(
          enabled: state is! JciDetectionAnalyzing,
          onSelected: (option) {
            unawaited(
              context.read<JciDetectionCubit>().loadStandardImage(option),
            );
          },
        ),
        const SizedBox(height: 12),
        JciPrecisionSelector(
          selectedMaxWindows: _selectedMaxInferenceWindows,
          onChanged: state is JciDetectionAnalyzing
              ? null
              : (value) {
                  setState(() {
                    _selectedMaxInferenceWindows = value;
                    _useServerHighestPrecision = false;
                  });
                },
        ),
        const SizedBox(height: 12),
        _buildServerInferenceSelector(enabled: state is! JciDetectionAnalyzing),
      ],
    );
  }

  /// 构建单个图像采集区域
  ///
  /// 需求 1.2: 提供"拍照"和"从相册选择"两种方式
  /// 需求 1.3: 显示图像预览并提供"重新选择"选项
  Widget _buildImageCaptureArea({
    required BuildContext context,
    required int index,
    required String label,
    String? imagePath,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _showImageSourceDialog(context, index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 180,
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: imagePath != null
                    ? _buildImagePreview(context, index, imagePath)
                    : _buildImagePlaceholder(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建图像预览
  ///
  /// 需求 1.3: 显示图像预览并提供"重新选择"选项
  Widget _buildImagePreview(
    BuildContext context,
    int index,
    String imagePath,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(imagePath),
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => context.read<JciDetectionCubit>().clearImage(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '点击重新选择',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建图像占位符
  Widget _buildImagePlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo, size: 40, color: Colors.grey),
          SizedBox(height: 8),
          Text(
            '点击添加图像',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// 显示图像来源选择对话框
  ///
  /// 需求 1.2: 提供"拍照"和"从相册选择"两种方式
  void _showImageSourceDialog(BuildContext context, int index) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '选择图像来源',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.camera_alt, color: Colors.blue),
                    title: const Text('拍照'),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      unawaited(
                        context.read<JciDetectionCubit>().selectImage(
                          index,
                          ImageSource.camera,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.photo_library,
                      color: Colors.green,
                    ),
                    title: const Text('从相册选择'),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      unawaited(
                        context.read<JciDetectionCubit>().selectImage(
                          index,
                          ImageSource.gallery,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecognizeButton(BuildContext context, JciDetectionState state) {
    final canRecognize = _canRecognize(state);
    final analyzingState = state is JciDetectionAnalyzing ? state : null;
    final isAnalyzing = analyzingState != null;
    final modelLoaded = context.read<JciDetectionCubit>().isModelLoaded;
    final canRunSelectedMode = _useServerHighestPrecision || modelLoaded;
    final selectedPrecision = jciPrecisionOptionForWindows(
      _selectedMaxInferenceWindows,
    );

    return Column(
      children: [
        if (!modelLoaded)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '正在加载裂缝检测模型...',
                    style: TextStyle(color: Colors.blue, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        if (analyzingState != null) ...[
          _buildRecognitionWaitingPanel(analyzingState, selectedPrecision),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: canRecognize && !isAnalyzing && canRunSelectedMode
                ? () => unawaited(
                    context.read<JciDetectionCubit>().recognizeImages(
                      inferenceMode: _useServerHighestPrecision
                          ? InferenceMode.onlineOnly
                          : InferenceMode.offlineOnly,
                      maxInferenceWindows: _useServerHighestPrecision
                          ? 20
                          : _selectedMaxInferenceWindows,
                    ),
                  )
                : null,
            icon: isAnalyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.visibility),
            label: Text(
              isAnalyzing
                  ? (_useServerHighestPrecision ? '服务器推理中...' : '离线识别中...')
                  : (_useServerHighestPrecision ? '服务器最高精度识别' : '开始离线识别'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServerInferenceSelector({required bool enabled}) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _useServerHighestPrecision;
    return InkWell(
      onTap: enabled
          ? () => setState(() => _useServerHighestPrecision = true)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer.withValues(alpha: 0.45)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? colorScheme.primary : colorScheme.onSurface,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '服务器推理（最高精度）',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'onlineOnly · 20 窗口 · threshold 0.3',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecognitionWaitingPanel(
    JciDetectionAnalyzing state,
    JciPrecisionOption precision,
  ) {
    final progress = state.progress.clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state.currentStepDescription,
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${state.progressPercent}%',
                style: const TextStyle(color: Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(
            _recognitionWaitingHint(state, precision),
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _recognitionWaitingHint(
    JciDetectionAnalyzing state,
    JciPrecisionOption precision,
  ) {
    return switch (state.currentStep) {
      'preparing_offline_detection' => '正在初始化端侧模型任务，请保持页面开启，识别会自动开始。',
      'online_detecting' => '正在把图像发送到服务器并等待在线识别结果，请保持网络连接。',
      'online_fallback' => '服务器识别未完成，正在切换到端侧离线模型继续处理。',
      'offline_detecting' =>
        '正在使用手机端离线模型识别裂隙 · ${precision.label}，高窗口数量会更慢、更占内存。',
      'extracting' => '正在从识别结果中提取 RQD、裂隙间距和裂隙密度。',
      'calculating' => '正在按金川 JCI 公式计算分级和支护建议。',
      'generating_report' => '正在整理检测结果和报告文件。',
      _ => '当前任务仍在执行，请保持页面开启。',
    };
  }

  Widget _buildRecognitionParametersSection(
    JciDetectionParametersReady state,
  ) {
    final indicators = state.scanlineResult?.indicators;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.fact_check, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  '识别结果确认',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (indicators == null)
              const Text('未获得测线三大指标，请重新识别或检查图像质量。')
            else ...[
              _buildRecognitionParamRow(
                '指标1：裂隙条数/面积',
                '${indicators.indicator1.toStringAsFixed(2)} 条/m²',
              ),
              _buildRecognitionParamRow(
                '指标2：平均节理间距',
                '${indicators.indicator2.toStringAsFixed(2)} cm',
              ),
              _buildRecognitionParamRow(
                '指标3：节理密度',
                '${indicators.indicator3.toStringAsFixed(2)} m/m²',
              ),
              const SizedBox(height: 8),
              Text(
                _recognitionStatsText(indicators),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecognitionParamRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _recognitionStatsText(ThreeIndicators indicators) {
    return [
      '裂隙总数 ${indicators.totalCracks} 条',
      '≥25cm 裂隙 ${indicators.cracksAbove25cm} 条',
      '裂隙总长度 ${indicators.totalCrackLength.toStringAsFixed(1)} cm',
    ].join('，');
  }

  /// 构建工程信息表单
  ///
  /// 需求 3.1-3.6: 工程信息输入
  Widget _buildEngineeringInfoForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '工程信息',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // 需求 3.1: 金川岩性选择
        DropdownButtonFormField<RockType>(
          initialValue: _selectedRockType,
          decoration: const InputDecoration(
            labelText: '岩性 *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.terrain),
          ),
          items: RockType.values.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(type.displayName),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedRockType = value;
            });
          },
          validator: (value) {
            if (value == null) {
              return '请选择岩石种类';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),

        // 需求 3.2: 工程地点输入
        TextFormField(
          controller: _locationController,
          decoration: const InputDecoration(
            labelText: '工程地点',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on),
            hintText: '例：二矿598',
          ),
        ),
        const SizedBox(height: 16),

        // 需求 3.3: 工程名称输入
        TextFormField(
          controller: _projectNameController,
          decoration: const InputDecoration(
            labelText: '工程名称',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.assignment),
            hintText: '例：水泵房',
          ),
        ),
        const SizedBox(height: 16),

        // 需求 3.4: 施工人员输入
        TextFormField(
          controller: _inspectorController,
          decoration: const InputDecoration(
            labelText: '施工人员',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
            hintText: '例：张三',
          ),
        ),
        const SizedBox(height: 16),

        // 需求 3.5: 工程所在中段标高输入
        TextFormField(
          controller: _depthController,
          decoration: const InputDecoration(
            labelText: '工程所在中段标高 (m) *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.height),
            hintText: '例：598',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: _validateDepth,
        ),
        const SizedBox(height: 16),

        // 需求 6.1: 是否渗水开关
        SwitchListTile(
          title: const Text('掌子面是否渗水'),
          subtitle: const Text('渗水会导致围岩等级降低一级'),
          value: _hasSeepage,
          onChanged: (value) {
            setState(() {
              _hasSeepage = value;
            });
          },
          secondary: const Icon(Icons.water),
        ),
      ],
    );
  }

  /// 验证埋深输入
  ///
  /// 需求 3.8: 埋深值为非正数时显示验证错误
  String? _validateDepth(String? value) {
    return FormValidationState.validateDepth(value);
  }

  /// 构建 JCI 计算按钮
  ///
  /// 图像识别完成后启用“计算 JCI 并匹配支护”按钮。
  Widget _buildAnalyzeButton(BuildContext context, JciDetectionState state) {
    final canStartAnalysis = _canStartAnalysis(state);
    final isAnalyzing = state is JciDetectionAnalyzing;
    final modelLoaded = context.read<JciDetectionCubit>().isModelLoaded;

    return Column(
      children: [
        // 模型加载状态提示
        if (!modelLoaded)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '正在加载裂缝检测模型...',
                    style: TextStyle(color: Colors.blue, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        if (state is JciDetectionAnalyzing) ...[
          LinearProgressIndicator(
            value: state.progress,
          ),
          const SizedBox(height: 8),
          Text(
            state.currentStepDescription,
            style: const TextStyle(color: Colors.blue),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: canStartAnalysis && !isAnalyzing && modelLoaded
                ? () => _startAnalysis(context)
                : null,
            icon: isAnalyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.analytics),
            label: Text(isAnalyzing ? '计算中...' : '计算 JCI 并匹配支护'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// 检查是否可以开始计算
  ///
  /// 只有图像识别结果就绪后，工程信息计算按钮才启用。
  bool _canStartAnalysis(JciDetectionState state) {
    return state is JciDetectionParametersReady;
  }

  bool _canRecognize(JciDetectionState state) {
    if (state is JciDetectionImagesSelected) {
      return state.canStartAnalysis;
    }
    if (state is JciDetectionError) {
      return state.image1Path != null;
    }
    return false;
  }

  bool _hasRecognitionImage(JciDetectionState state) {
    if (state is JciDetectionImagesSelected) {
      return state.image1Path != null;
    }
    if (state is JciDetectionParametersReady) {
      return state.image1Path.isNotEmpty;
    }
    if (state is JciDetectionAnalyzing) {
      return state.image1Path != null;
    }
    if (state is JciDetectionError) {
      return state.image1Path != null;
    }
    return false;
  }

  /// 根据已识别参数和工程信息计算 JCI
  void _startAnalysis(BuildContext context) {
    // 需求 3.7: 验证表单
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写所有必填项'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final engineeringInfo = EngineeringInfo(
      rockType: _selectedRockType!,
      depth: double.parse(_depthController.text),
      waterCondition: _selectedWaterCondition,
      location: _locationController.text,
      projectName: _projectNameController.text,
      inspector: _inspectorController.text,
      hasSeepage: _hasSeepage,
    );

    unawaited(
      context.read<JciDetectionCubit>().calculateWithEngineeringInfo(
        engineeringInfo,
      ),
    );
  }

  /// 重置表单
  void _resetForm() {
    setState(() {
      _selectedRockType = null;
      _selectedWaterCondition = WaterCondition.dry;
      _hasSeepage = false;
      _depthController.clear();
      _locationController.clear();
      _projectNameController.clear();
      _inspectorController.clear();
    });
    _formKey.currentState?.reset();
    context.read<JciDetectionCubit>().reset();
  }
}

/// JCI 检测结果展示视图
///
/// 显示完整的检测结果，包括 JCI 值、围岩等级、支护方案等。
///
/// 需求:
/// - 4.3: 显示计算得到的 JCI 数值
/// - 4.4: 显示参与计算的各项参数及其权重
/// - 5.8: 以醒目的颜色和图标显示等级结果
/// - 6.4: 同时显示调整前和调整后的等级
/// - 6.5: 明确标注"因渗水降级"的说明
/// - 7.1-7.3: 显示支护方案建议
/// - 8.1: 提供"保存结果"按钮
class _JciResultView extends StatelessWidget {
  const _JciResultView({
    required this.result,
    required this.onSave,
    required this.onManualReview,
    required this.onReset,
  });

  final JciDetectionResult result;
  final VoidCallback onSave;
  final Future<void> Function(ManualReview review) onManualReview;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const JciResultNotice(),
          const SizedBox(height: 12),

          // 检测结果图像
          JciResultImagesSection(result: result),
          const SizedBox(height: 24),

          // JCI 值和计算明细（需求 4.3, 4.4）
          _buildJciSection(),
          const SizedBox(height: 24),

          // 围岩等级（需求 5.8, 6.4, 6.5）
          _buildRockGradeSection(),
          const SizedBox(height: 24),

          // 支护方案建议（需求 7.1-7.3）
          _buildSupportPlanSection(),
          const SizedBox(height: 24),

          // 人工复核
          _buildManualReviewSection(context),
          const SizedBox(height: 24),

          // 提取的参数
          _buildExtractedParamsSection(),
          const SizedBox(height: 24),

          // 三大指标汇总（需求 10.6-10.8）
          if (result.scanlineResult != null) _buildThreeIndicatorsSection(),
          if (result.scanlineResult != null) const SizedBox(height: 24),

          // 报告状态（需求 11.1）
          _buildReportSection(context),
          const SizedBox(height: 24),

          // 操作按钮（需求 8.1）
          _buildActionButtons(context),
        ],
      ),
    );
  }

  /// 构建 JCI 值和计算明细区域
  ///
  /// 需求 4.3: 显示计算得到的 JCI 数值
  /// 需求 4.4: 显示参与计算的各项参数及其权重
  Widget _buildJciSection() {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calculate, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'JCI 计算结果',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // JCI 值显示
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue),
                ),
                child: Column(
                  children: [
                    const Text(
                      'JCI 值',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.jciResult.jciValue.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // 计算公式（需求 4.13）
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: const Text(
                'JCI = 0.0454 × RMR + 0.6586 × g(Q) + 0.2960 × h(S)',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            // 中间计算结果（需求 4.13）
            const Text(
              '中间计算结果',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            // RMR 值及分项
            _buildCalcDetailRow(
              'RMR',
              result.jciResult.rmr.toStringAsFixed(2),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                children: [
                  _buildCalcDetailRow(
                    'R1（岩石强度常量）',
                    '3',
                    isSubItem: true,
                  ),
                  _buildCalcDetailRow(
                    'R2（节理密度评分）',
                    '${result.jciResult.r2}',
                    isSubItem: true,
                  ),
                  _buildCalcDetailRow(
                    'R3（节理间距评分）',
                    '${result.jciResult.r3}',
                    isSubItem: true,
                  ),
                  _buildCalcDetailRow(
                    'R4+R5+R6（常量）',
                    '4',
                    isSubItem: true,
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            // Q 值及分项
            _buildCalcDetailRow(
              'Q 值',
              result.jciResult.qValue.toStringAsFixed(4),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                children: [
                  _buildCalcDetailRow(
                    'RQD_value',
                    result.jciResult.rqdValue.toStringAsFixed(2),
                    isSubItem: true,
                  ),
                  _buildCalcDetailRow(
                    'Jn',
                    result.jciResult.jn.toStringAsFixed(1),
                    isSubItem: true,
                  ),
                  _buildCalcDetailRow(
                    'SRF',
                    result.jciResult.srf.toStringAsFixed(1),
                    isSubItem: true,
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            // g(Q) 和 h(S)
            _buildCalcDetailRow(
              'g(Q)',
              result.jciResult.gQ.toStringAsFixed(2),
            ),
            _buildCalcDetailRow(
              'h(S)（强度应力比）',
              result.jciResult.hS.toStringAsFixed(2),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建围岩等级区域
  ///
  /// 需求 5.8: 以醒目的颜色和图标显示等级结果
  /// 需求 6.4: 同时显示调整前和调整后的等级
  /// 需求 6.5: 明确标注"因渗水降级"的说明
  Widget _buildRockGradeSection() {
    final classification = result.classification;
    final effectiveGrade = result.effectiveGrade;
    final gradeColor = _getGradeColor(effectiveGrade);
    final gradeIcon = _getGradeIcon(effectiveGrade);
    final manualOverride = result.manualReview?.hasOverride ?? false;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.terrain, color: Colors.brown),
                SizedBox(width: 8),
                Text(
                  '围岩等级',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 最终等级显示（需求 5.8）
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: gradeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: gradeColor, width: 2),
                ),
                child: Column(
                  children: [
                    Icon(
                      gradeIcon,
                      size: 48,
                      color: gradeColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      effectiveGrade.name,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: gradeColor,
                      ),
                    ),
                    Text(
                      effectiveGrade.description,
                      style: TextStyle(
                        fontSize: 16,
                        color: gradeColor,
                      ),
                    ),
                    if (manualOverride) ...[
                      const SizedBox(height: 6),
                      const Text(
                        '人工复核采用等级',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 渗水降级说明（需求 6.4, 6.5）
            if (classification.wasDowngraded) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.water_drop, color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '因渗水降级',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildGradeBadge(
                          classification.originalGrade,
                          label: '原等级',
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(
                            Icons.arrow_forward,
                            color: Colors.orange,
                          ),
                        ),
                        _buildGradeBadge(
                          classification.finalGrade,
                          label: '调整后',
                        ),
                      ],
                    ),
                    if (classification.downgradeReason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        classification.downgradeReason!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建等级徽章
  Widget _buildGradeBadge(RockGrade grade, {required String label}) {
    final color = _getGradeColor(grade);
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Text(
            grade.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建支护方案区域
  ///
  /// 需求 7.1: 显示对应等级的支护参数建议
  /// 需求 7.2: 输出支护工艺类型
  /// 需求 7.3: 输出支护参数
  Widget _buildSupportPlanSection() {
    final supportPlan = result.effectiveSupportPlan;
    final manualOverride = result.manualReview?.hasOverride ?? false;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.construction, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  '支护方案建议',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (manualOverride) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.indigo.withValues(alpha: 0.25),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.rate_review, color: Colors.indigo, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前显示人工复核选择的支护方案',
                        style: TextStyle(color: Colors.indigo, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 方案摘要
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      supportPlan.summary,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 预留方案提示
            if (supportPlan.isPlaceholder) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '暂无具体方案，请咨询专业人员',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 支护方法列表（需求 7.2, 7.3）
            if (supportPlan.methods.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '支护工艺',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              ...supportPlan.methods.map(_buildSupportMethodCard),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建人工复核区域
  Widget _buildManualReviewSection(BuildContext context) {
    final review = result.manualReview;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.rate_review, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  '人工复核',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (review == null) ...[
              const Text('是否接受识别结果'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _acceptRecognitionResult(context),
                      icon: const Icon(Icons.check),
                      label: const Text('接受'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showManualReviewDialog(context),
                      icon: const Icon(Icons.edit),
                      label: const Text('人工调整'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              _buildParamRow(
                '复核结论',
                review.acceptedRecognitionResult ? '接受识别结果' : '人工调整',
              ),
              if (review.hasOverride) ...[
                _buildParamRow('人工判断级别', review.manualGrade?.name ?? ''),
                _buildParamRow(
                  '人工支护方案',
                  review.selectedSupportPlan?.grade.fullName ?? '',
                ),
              ],
              if (review.reviewerName.isNotEmpty)
                _buildParamRow('复核人员', review.reviewerName),
              if (review.note.isNotEmpty) _buildParamRow('复核说明', review.note),
              _buildParamRow(
                '复核时间',
                review.reviewedAt.toLocal().toString().split('.').first,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _acceptRecognitionResult(BuildContext context) async {
    await onManualReview(
      ManualReview.accepted(
        reviewerName: result.engineeringInfo.workerName,
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已记录接受识别结果')),
      );
    }
  }

  Future<void> _showManualReviewDialog(BuildContext context) async {
    var manualGrade = result.classification.finalGrade;
    final noteController = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              final currentSupportPlan = const SupportAdvisorService()
                  .getSupportPlan(manualGrade);
              return AlertDialog(
                title: const Text('人工复核调整'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<RockGrade>(
                        initialValue: manualGrade,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '人工判断级别',
                          border: OutlineInputBorder(),
                        ),
                        selectedItemBuilder: (context) => RockGrade.values
                            .map(
                              (grade) => Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  grade.fullName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        items: RockGrade.values
                            .map(
                              (grade) => DropdownMenuItem(
                                value: grade,
                                child: _ManualGradeOption(
                                  grade: grade,
                                  supportPlan: const SupportAdvisorService()
                                      .getSupportPlan(grade),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => manualGrade = value);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _ManualGradeSupportPreview(
                        supportPlan: currentSupportPlan,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: '复核说明',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final selectedPlan = const SupportAdvisorService()
                          .getSupportPlan(manualGrade);
                      await onManualReview(
                        ManualReview.rejected(
                          manualGrade: manualGrade,
                          selectedSupportPlan: selectedPlan,
                          reviewerName: result.engineeringInfo.workerName,
                          note: noteController.text.trim(),
                        ),
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('人工复核已保存')),
                        );
                      }
                    },
                    child: const Text('保存'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      noteController.dispose();
    }
  }

  /// 构建支护方法卡片
  Widget _buildSupportMethodCard(SupportMethod method) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.build, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                method.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (method.parameters.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: method.parameters.entries.map((param) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${param.key}: ${param.value}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建三大指标汇总区域
  ///
  /// 需求 10.6: 指标1 = 裂隙条数/面积（条/m²）
  /// 需求 10.7: 指标2 = 平均节理间距（cm）
  /// 需求 10.8: 指标3 = 节理密度（m/m²）
  Widget _buildThreeIndicatorsSection() {
    final indicators = result.scanlineResult!.indicators;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  '三大指标汇总',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildIndicatorRow(
              '指标1：裂隙条数/面积',
              '${indicators.indicator1.toStringAsFixed(2)} 条/m²',
              Icons.grid_on,
              Colors.blue,
            ),
            const Divider(height: 24),
            _buildIndicatorRow(
              '指标2：平均节理间距',
              '${indicators.indicator2.toStringAsFixed(2)} cm',
              Icons.straighten,
              Colors.orange,
            ),
            const Divider(height: 24),
            _buildIndicatorRow(
              '指标3：节理密度',
              '${indicators.indicator3.toStringAsFixed(2)} m/m²',
              Icons.density_medium,
              Colors.purple,
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            // 补充统计信息
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStatChip(
                  '裂隙总数',
                  '${indicators.totalCracks} 条',
                ),
                _buildStatChip(
                  '≥25cm裂隙',
                  '${indicators.cracksAbove25cm} 条',
                ),
                _buildStatChip(
                  '裂隙总长度',
                  '${indicators.totalCrackLength.toStringAsFixed(1)} cm',
                ),
                _buildStatChip(
                  '图像面积',
                  '${indicators.imageAreaM2.toStringAsFixed(4)} m²',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建单个指标行
  Widget _buildIndicatorRow(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建统计标签
  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// 构建报告状态区域
  ///
  /// 需求 11.1: 显示报告生成状态和查看/分享按钮
  Widget _buildReportSection(BuildContext context) {
    final hasReport = result.reportPath != null;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.description, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  '检测报告',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasReport) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '报告已生成',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _viewReport(context),
                      icon: const Icon(Icons.visibility),
                      label: const Text('查看报告'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareReport(context),
                      icon: const Icon(Icons.share),
                      label: const Text('分享报告'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.grey,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '报告未生成',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 查看报告内容
  void _viewReport(BuildContext context) {
    final reportPath = result.reportPath;
    if (reportPath == null) return;

    try {
      final file = File(reportPath);
      final content = file.readAsStringSync();
      unawaited(
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('检测报告'),
            content: SingleChildScrollView(
              child: Text(
                content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    } on Exception {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法读取报告文件'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 分享报告
  void _shareReport(BuildContext context) {
    final reportPath = result.reportPath;
    if (reportPath == null) return;

    // 显示报告文件路径供用户手动分享
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('报告文件路径: $reportPath'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '确定',
          onPressed: () {},
        ),
      ),
    );
  }

  /// 构建提取参数区域
  Widget _buildExtractedParamsSection() {
    final params = result.extractedParams;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  '提取参数',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildParamRow('RQD 值', '${params.rqd.toStringAsFixed(1)}%'),
            _buildParamRow(
              '节理间距',
              '${params.jointSpacing.toStringAsFixed(2)} 米',
            ),
            _buildParamRow(
              '节理面密度',
              '${params.jointDensity.toStringAsFixed(2)} 条/m²',
            ),
          ],
        ),
      ),
    );
  }

  /// 构建计算明细行
  Widget _buildCalcDetailRow(
    String label,
    String value, {
    bool isSubItem = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isSubItem ? 13 : 14,
              color: isSubItem ? Colors.grey : Colors.black87,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isSubItem ? 13 : 14,
              fontWeight: isSubItem ? FontWeight.normal : FontWeight.bold,
              color: isSubItem ? Colors.grey : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建参数行
  Widget _buildParamRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建操作按钮区域
  ///
  /// 需求 8.1: 检测完成后提供"保存结果"按钮
  Widget _buildActionButtons(BuildContext context) {
    return Column(
      children: [
        // 保存结果按钮
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () async {
              await _handleSave(context);
            },
            icon: const Icon(Icons.save),
            label: const Text('更新本地记录'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 新建检测按钮
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.add),
            label: const Text('新建检测'),
          ),
        ),
      ],
    );
  }

  /// 处理保存操作
  Future<void> _handleSave(BuildContext context) async {
    onSave();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('本地记录已更新'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// 根据围岩等级获取颜色
  ///
  /// 需求 5.8: 使用颜色编码（绿色表示稳定，黄色表示中等，红色表示不稳定）
  Color _getGradeColor(RockGrade grade) {
    switch (grade) {
      case RockGrade.i1:
      case RockGrade.i2:
        return Colors.green;
      case RockGrade.ii1:
      case RockGrade.ii2:
        return Colors.orange;
      case RockGrade.iii:
        return Colors.deepOrange;
      case RockGrade.iv:
      case RockGrade.v:
        return Colors.red;
    }
  }

  /// 根据围岩等级获取图标
  ///
  /// 需求 5.8: 使用图标显示等级
  IconData _getGradeIcon(RockGrade grade) {
    switch (grade) {
      case RockGrade.i1:
      case RockGrade.i2:
        return Icons.check_circle;
      case RockGrade.ii1:
      case RockGrade.ii2:
        return Icons.info;
      case RockGrade.iii:
        return Icons.warning;
      case RockGrade.iv:
      case RockGrade.v:
        return Icons.dangerous;
    }
  }
}

class _ManualGradeOption extends StatelessWidget {
  const _ManualGradeOption({
    required this.grade,
    required this.supportPlan,
  });

  final RockGrade grade;
  final SupportPlan supportPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            grade.fullName,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            supportPlan.summary,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black87,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualGradeSupportPreview extends StatelessWidget {
  const _ManualGradeSupportPreview({required this.supportPlan});

  final SupportPlan supportPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Text(
        supportPlan.summary,
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.black87,
          height: 1.35,
        ),
      ),
    );
  }
}
