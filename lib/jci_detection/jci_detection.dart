/// JCI 检测模块
///
/// 提供 JCI（节理状态指数）计算和围岩支护分级功能。
/// 包含图像分析、JCI 计算、围岩分类、支护方案建议和本地存储等功能。
///
/// ## 主要组件
///
/// ### 模型 (Models)
/// - [RockType] - 岩石类型枚举
/// - [WaterCondition] - 地下水状况枚举
/// - [RockGrade] - 围岩等级枚举
/// - [EngineeringInfo] - 工程信息
/// - [ExtractedParameters] - 提取的参数
/// - [JciCalculationResult] - JCI 计算结果
/// - [RockClassificationResult] - 围岩分类结果
/// - [SupportMethod] - 支护方法
/// - [SupportPlan] - 支护方案
/// - [JciDetectionResult] - JCI 检测完整结果
/// - [CrackInfo] - 单条裂缝信息
/// - [CrackIdentificationResult] - 裂缝识别结果
/// - [Scanline] - 测线定义
/// - [ScanlineIntersection] - 测线交点信息
/// - [ScanlineResult] - 单条测线分析结果
/// - [ThreeIndicators] - 三大指标结果
/// - [ScanlineAnalysisResult] - 测线分析完整结果
/// - [ReportData] - 报告数据
/// - [JciStandardImageOption] - 标准样图选项
///
/// ### 服务 (Services)
/// - [RockClassifierService] - 围岩等级分类服务
/// - [JciCalculatorService] - JCI 计算服务
/// - [JciInputParameters] - JCI 输入参数
/// - [SupportAdvisorService] - 支护方案建议服务
/// - [ImageAnalyzerService] - 图像分析服务
/// - [ImageAnalysisException] - 图像分析异常
/// - [JciStorageService] - 本地存储服务
/// - [CrackIdentifierService] - 裂缝独立识别服务
/// - [ScanlineAnalyzerService] - 测线分析服务
/// - [ReportGeneratorService] - 报告生成服务
///
/// ### 状态管理 (Cubit)
/// - [JciDetectionCubit] - JCI 检测状态管理
/// - [JciDetectionState] - JCI 检测状态基类
/// - [JciDetectionInitial] - 初始状态
/// - [JciDetectionImagesSelected] - 图像已选择状态
/// - [JciDetectionAnalyzing] - 分析中状态
/// - [JciDetectionSuccess] - 分析成功状态
/// - [JciDetectionError] - 分析错误状态
/// - [JciHistoryCubit] - 历史记录状态管理
/// - [JciHistoryState] - 历史记录状态基类
/// - [JciHistoryInitial] - 历史记录初始状态
/// - [JciHistoryLoading] - 历史记录加载中状态
/// - [JciHistoryLoaded] - 历史记录加载成功状态
/// - [JciHistoryError] - 历史记录错误状态
///
/// ### 页面 (Views)
/// - [JciDetectionPage] - JCI 检测页面
/// - [JciHistoryPage] - 历史记录页面
library;

import 'package:crack_app/jci_detection/jci_detection.dart'
    show
        CrackIdentificationResult,
        CrackIdentifierService,
        CrackInfo,
        EngineeringInfo,
        ExtractedParameters,
        ImageAnalysisException,
        ImageAnalyzerService,
        JciCalculationResult,
        JciCalculatorService,
        JciDetectionAnalyzing,
        JciDetectionCubit,
        JciDetectionError,
        JciDetectionImagesSelected,
        JciDetectionInitial,
        JciDetectionPage,
        JciDetectionResult,
        JciDetectionState,
        JciDetectionSuccess,
        JciHistoryCubit,
        JciHistoryError,
        JciHistoryInitial,
        JciHistoryLoaded,
        JciHistoryLoading,
        JciHistoryPage,
        JciHistoryState,
        JciInputParameters,
        JciStandardImageOption,
        JciStorageService,
        ReportData,
        ReportGeneratorService,
        RockClassificationResult,
        RockClassifierService,
        RockGrade,
        RockType,
        Scanline,
        ScanlineAnalysisResult,
        ScanlineAnalyzerService,
        ScanlineIntersection,
        ScanlineResult,
        SupportAdvisorService,
        SupportMethod,
        SupportPlan,
        ThreeIndicators,
        WaterCondition;

// 状态管理 - JCI 检测 Cubit
export 'cubit/jci_detection_cubit.dart' show JciDetectionCubit;
// 状态管理 - JCI 检测状态
export 'cubit/jci_detection_state.dart'
    show
        JciDetectionAnalyzing,
        JciDetectionError,
        JciDetectionImagesSelected,
        JciDetectionInitial,
        JciDetectionState,
        JciDetectionSuccess;
// 状态管理 - 历史记录
export 'cubit/jci_history_cubit.dart'
    show
        JciHistoryCubit,
        JciHistoryError,
        JciHistoryInitial,
        JciHistoryLoaded,
        JciHistoryLoading,
        JciHistoryState;
// 模型 - 裂缝信息
export 'models/crack_info.dart' show CrackIdentificationResult, CrackInfo;
// 模型 - 枚举类型
export 'models/enums.dart' show RockGrade, RockType, WaterCondition;
// 模型 - 数据类
export 'models/form_validation_state.dart' show FormValidationState;
export 'models/models.dart'
    show
        EngineeringInfo,
        ExtractedParameters,
        JciCalculationResult,
        JciDetectionResult,
        RockClassificationResult,
        SupportMethod,
        SupportPlan;
// 模型 - 报告数据
export 'models/report_data.dart' show ReportData;
// 模型 - 测线分析
export 'models/scanline_models.dart'
    show
        Scanline,
        ScanlineAnalysisResult,
        ScanlineIntersection,
        ScanlineResult,
        ThreeIndicators;
// 模型 - 标准样图
export 'models/standard_image_option.dart'
    show JciStandardImageOption, jciStandardImageOptions;
// 服务 - 裂缝独立识别
export 'services/crack_identifier_service.dart' show CrackIdentifierService;
// 服务 - 图像分析
export 'services/image_analyzer_service.dart'
    show ImageAnalysisException, ImageAnalyzerService;
// 服务 - JCI 计算
export 'services/jci_calculator_service.dart'
    show JciCalculatorService, JciInputParameters;
// 服务 - 本地存储
export 'services/jci_storage_service.dart' show JciStorageService;
// 服务 - 报告生成
export 'services/report_generator_service.dart' show ReportGeneratorService;
// 服务 - 围岩分类
export 'services/rock_classifier_service.dart' show RockClassifierService;
// 服务 - 测线分析
export 'services/scanline_analyzer_service.dart' show ScanlineAnalyzerService;
// 服务 - 支护方案建议
export 'services/support_advisor_service.dart' show SupportAdvisorService;
// 页面 - JCI 检测页面
export 'view/jci_detection_page.dart' show JciDetectionPage;
// 页面 - 历史记录页面
export 'view/jci_history_page.dart' show JciHistoryPage;
