#!/usr/bin/env python3
"""
使用移动端模型进行裂隙检测（支持大图切片）
基于 predict_with_ruler.py，但使用 savss_mobile.ptl 模型

功能：
1. 裂隙检测
2. 黄色尺子检测
3. 三个指标计算：
   - 指标1: (长度≥25cm的裂隙条数) / 图像面积（m²）
   - 指标2: 平均节理间距（cm）
   - 指标3: 裂隙总长度（m） / 图像面积（m²）

用法:
    python3 predict_with_mobile.py --image cut_picture/14.jpg
    python3 predict_with_mobile.py --image cut_picture/14.jpg --ruler_length 50 --calculate_indicators
"""

import numpy as np
import torch
import argparse
import os
import cv2
import time
from datetime import datetime
from PIL import Image
from skimage import morphology, measure

# ExecuTorch 支持（可选）
try:
    from executorch.extension.pybindings.portable_lib import _load_for_executorch
    EXECUTORCH_AVAILABLE = True
except ImportError:
    EXECUTORCH_AVAILABLE = False

def cracknex_retinex_enhancement(image):
    """
    CrackNex Retinex图像增强

    Args:
        image: OpenCV图像 (BGR格式) 或 PIL Image对象

    Returns:
        enhanced: 增强后的图像 (与输入格式相同)，如果失败返回原图
    """
    try:
        # 判断输入类型
        is_pil = isinstance(image, Image.Image)

        # 转换为numpy数组
        if is_pil:
            image_np = np.array(image)
            # PIL是RGB，转换为BGR
            image_np = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)
        else:
            image_np = image.copy()

        if image_np is None or image_np.size == 0:
            raise ValueError("输入图像为空")

        image_float = image_np.astype(np.float32) / 255.0

        # 多尺度Retinex
        scales = [15, 80, 250]
        msr_result = np.zeros_like(image_float)

        for scale in scales:
            illumination = cv2.GaussianBlur(image_float, (0, 0), scale)
            illumination = np.maximum(illumination, 0.01)
            reflectance = np.log(image_float + 0.01) - np.log(illumination + 0.01)
            msr_result += reflectance

        msr_result = msr_result / len(scales)

        # 颜色恢复
        sum_channels = np.sum(image_float, axis=2, keepdims=True)
        sum_channels = np.maximum(sum_channels, 0.01)
        ratio = np.maximum(125.0 * image_float / sum_channels, 0.01)
        color_restoration = np.log(ratio)

        enhanced = msr_result * color_restoration

        # 归一化
        enhanced = np.clip(enhanced, -3, 3)
        enhanced_range = enhanced.max() - enhanced.min()
        if enhanced_range > 0:
            enhanced = (enhanced - enhanced.min()) / enhanced_range
        else:
            enhanced = np.zeros_like(enhanced)
        enhanced = (enhanced * 255).astype(np.uint8)

        # 转换回原始格式
        if is_pil:
            # BGR转RGB，然后转PIL
            enhanced = cv2.cvtColor(enhanced, cv2.COLOR_BGR2RGB)
            enhanced = Image.fromarray(enhanced)

        return enhanced
    except Exception as e:
        print(f"⚠ 图像增强失败: {e}，返回原图")
        return image


def model_inference(model, input_tensor, use_executorch=False):
    """
    统一的模型推理接口，支持 TorchScript 和 ExecuTorch

    Args:
        model: 模型对象
        input_tensor: 输入张量
        use_executorch: 是否使用 ExecuTorch

    Returns:
        output: 模型输出
    """
    if use_executorch:
        # ExecuTorch 推理
        output = model.forward((input_tensor,))
        # ExecuTorch 返回的是元组，需要提取第一个元素
        if isinstance(output, tuple):
            output = output[0]
        return output
    else:
        # TorchScript 推理
        return model(input_tensor)

def preprocess_image_mobile(img_np, size=512):
    """
    移动端模型预处理（ImageNet 标准化）
    Args:
        img_np: numpy array (H, W, 3) RGB
        size: 目标尺寸
    Returns:
        tensor: (1, 3, size, size)
    """
    # ImageNet 标准化参数
    MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

    # 调整大小
    img_resized = cv2.resize(img_np, (size, size), interpolation=cv2.INTER_LINEAR)

    # 归一化到 [0, 1]
    img_float = img_resized.astype(np.float32) / 255.0

    # ImageNet 标准化
    img_normalized = (img_float - MEAN.reshape(1, 1, 3)) / STD.reshape(1, 1, 3)

    # 转换为 CHW 格式
    img_chw = np.transpose(img_normalized, (2, 0, 1))

    # 添加 batch 维度
    img_tensor = torch.from_numpy(img_chw).unsqueeze(0)

    return img_tensor

def detect_ruler(image, ruler_length_cm=50, ruler_color='yellow'):
    """
    检测图片中的黄色尺子，并计算像素到厘米的比例

    Args:
        image: PIL Image对象或numpy数组
        ruler_length_cm: 尺子的实际长度(厘米)
        ruler_color: 尺子颜色 ('yellow', 'red', 或 'both')

    Returns:
        pixel_to_cm: 像素到厘米的比例
        ruler_mask: 尺子的mask
        ruler_bbox: 尺子的边界框 (x, y, w, h)
    """
    # 转换为numpy数组
    if isinstance(image, Image.Image):
        img_np = np.array(image)
    else:
        img_np = image.copy()

    # 转换到HSV色彩空间
    img_hsv = cv2.cvtColor(img_np, cv2.COLOR_RGB2HSV)

    # 初始化mask
    ruler_mask = None

    # 黄色范围 (HSV)
    if ruler_color in ['yellow', 'both']:
        yellow_lower1 = np.array([22, 120, 120])
        yellow_upper1 = np.array([32, 255, 255])
        yellow_mask1 = cv2.inRange(img_hsv, yellow_lower1, yellow_upper1)

        yellow_lower2 = np.array([20, 100, 100])
        yellow_upper2 = np.array([34, 255, 255])
        yellow_mask2 = cv2.inRange(img_hsv, yellow_lower2, yellow_upper2)

        ruler_mask = cv2.bitwise_or(yellow_mask1, yellow_mask2)

    # 如果没有检测到任何颜色，返回空mask
    if ruler_mask is None:
        ruler_mask = np.zeros((img_hsv.shape[0], img_hsv.shape[1]), dtype=np.uint8)

    # 形态学操作，去除噪声
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    ruler_mask = cv2.morphologyEx(ruler_mask, cv2.MORPH_CLOSE, kernel)
    ruler_mask = cv2.morphologyEx(ruler_mask, cv2.MORPH_OPEN, kernel)

    # 查找轮廓
    contours, _ = cv2.findContours(ruler_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if len(contours) == 0:
        print(f"  ⚠ 未检测到{ruler_color}尺子")
        return None, ruler_mask, None

    # 找到最大的轮廓（假设是尺子）
    largest_contour = max(contours, key=cv2.contourArea)
    x, y, w, h = cv2.boundingRect(largest_contour)

    # 计算尺子的长度（像素）
    ruler_length_pixels = max(w, h)

    # 计算像素到厘米的比例
    pixel_to_cm = ruler_length_cm / ruler_length_pixels

    print(f"  ✓ 检测到{ruler_color}尺子:")
    print(f"    位置: ({x}, {y})")
    print(f"    尺寸: {w}x{h} 像素")
    print(f"    长度: {ruler_length_pixels} 像素 = {ruler_length_cm} cm")
    print(f"    比例: 1 像素 = {pixel_to_cm:.4f} cm")

    return pixel_to_cm, ruler_mask, (x, y, w, h)

def remove_ruler_from_mask(crack_mask, ruler_mask):
    """从裂缝mask中移除尺子区域"""
    # 扩展尺子mask，确保完全移除
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (10, 10))
    ruler_mask_expanded = cv2.dilate(ruler_mask, kernel, iterations=2)

    # 从裂缝mask中减去尺子区域
    crack_mask_clean = cv2.bitwise_and(crack_mask, cv2.bitwise_not(ruler_mask_expanded))

    return crack_mask_clean

def extract_crack_skeletons(binary_mask):
    """
    提取裂缝的骨架

    Args:
        binary_mask: 二值化的裂缝mask

    Returns:
        skeleton: 骨架图
    """
    # 确保是二值图
    binary = (binary_mask > 0).astype(np.uint8)

    # 骨架化
    skeleton = morphology.skeletonize(binary)

    return skeleton.astype(np.uint8)

def measure_crack_lengths(skeleton, pixel_to_cm, min_length_pixels=20):
    """
    测量每条裂缝的长度

    Args:
        skeleton: 骨架图
        pixel_to_cm: 像素到厘米的转换比例
        min_length_pixels: 最小裂缝长度（像素），小于此值的忽略

    Returns:
        crack_info: 裂缝信息列表
    """
    # 标记连通区域
    labeled_skeleton = measure.label(skeleton, connectivity=2)

    crack_info = []

    # 遍历每个连通区域
    for region in measure.regionprops(labeled_skeleton):
        # 获取区域的像素数量（骨架长度的近似）
        length_pixels = region.area

        # 过滤太小的区域
        if length_pixels < min_length_pixels:
            continue

        # 转换为厘米
        length_cm = length_pixels * pixel_to_cm

        # 获取边界框
        minr, minc, maxr, maxc = region.bbox

        crack_info.append({
            'id': region.label,
            'length_pixels': length_pixels,
            'length_cm': length_cm,
            'bbox': (minc, minr, maxc - minc, maxr - minr),  # (x, y, w, h)
            'centroid': region.centroid
        })

    # 按长度排序
    crack_info.sort(key=lambda x: x['length_cm'], reverse=True)

    return crack_info

def calculate_joint_spacing_four_lines(image_shape, skeleton, pixel_to_cm):
    """
    使用4条测线（井字形）计算节理间距

    Args:
        image_shape: (height, width)
        skeleton: 骨架图
        pixel_to_cm: 像素到厘米的转换比例

    Returns:
        avg_spacing: 平均节理间距（cm）
        rqd_results: 每条测线的详细结果
        test_lines: 测线坐标列表
    """
    h, w = image_shape

    # 定义4条测线（井字形）
    test_lines = [
        # 横线1 (上1/3处)
        {'start': (0, h // 3), 'end': (w - 1, h // 3), 'name': '横线1'},
        # 横线2 (下2/3处)
        {'start': (0, 2 * h // 3), 'end': (w - 1, 2 * h // 3), 'name': '横线2'},
        # 竖线1 (左1/3处)
        {'start': (w // 3, 0), 'end': (w // 3, h - 1), 'name': '竖线1'},
        # 竖线2 (右2/3处)
        {'start': (2 * w // 3, 0), 'end': (2 * w // 3, h - 1), 'name': '竖线2'},
    ]

    rqd_results = []
    all_spacings = []

    for line_info in test_lines:
        start = line_info['start']
        end = line_info['end']
        name = line_info['name']

        # 获取测线上的像素坐标
        num_points = max(abs(end[0] - start[0]), abs(end[1] - start[1])) + 1
        x_coords = np.linspace(start[0], end[0], num_points).astype(int)
        y_coords = np.linspace(start[1], end[1], num_points).astype(int)

        # 获取测线上的骨架值
        line_values = skeleton[y_coords, x_coords]

        # 找到交点（骨架值>0的位置）
        intersection_indices = np.where(line_values > 0)[0]

        if len(intersection_indices) < 2:
            continue

        # 计算相邻交点之间的间距
        spacings_pixels = np.diff(intersection_indices)
        spacings_cm = spacings_pixels * pixel_to_cm

        # 过滤掉太小的间距（可能是噪声）
        valid_spacings = spacings_cm[spacings_cm > 1.0]

        if len(valid_spacings) > 0:
            avg_spacing_cm = np.mean(valid_spacings)
            all_spacings.extend(valid_spacings)

            # 构建交点坐标列表 (x, y, distance_from_start)
            intersection_coords = []
            for idx in intersection_indices:
                x = x_coords[idx]
                y = y_coords[idx]
                # 计算从起点的距离（像素）
                dist_pixels = np.sqrt((x - start[0])**2 + (y - start[1])**2)
                dist_cm = dist_pixels * pixel_to_cm
                intersection_coords.append((x, y, dist_cm))

            rqd_results.append({
                'name': name,
                'intersections': intersection_coords,  # 改为坐标列表
                'num_intersections': len(intersection_indices),  # 添加数量字段
                'avg_spacing_cm': avg_spacing_cm,
                'spacings': valid_spacings.tolist()
            })

    # 计算总体平均间距
    if len(all_spacings) > 0:
        avg_spacing = np.mean(all_spacings)
    else:
        avg_spacing = 0

    return avg_spacing, rqd_results, test_lines

def detect_valid_region(image, threshold=10):
    """
    检测图像中的有效区域（非黑色/背景区域）
    """
    if isinstance(image, Image.Image):
        image = np.array(image)

    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
    else:
        gray = image

    valid_mask = (gray > threshold).astype(np.uint8) * 255

    return valid_mask

def grid_predict(model, image, grid_size=1024, window_size=512, device='cpu', use_executorch=False):
    """
    网格模式推理：将图像resize到固定尺寸，然后分成2x2网格，每个格子512x512

    优化版本：添加详细性能日志，优化内存管理

    Args:
        use_executorch: 是否使用 ExecuTorch 引擎

    Args:
        model: TorchScript 移动端模型
        image: PIL 图像
        grid_size: 网格总尺寸（默认1024，即2x2个512x512）
        window_size: 每个窗口大小（默认512）
        device: 设备

    Returns:
        prediction: 预测结果 (grid_size, grid_size)
        original_size: 原始图像尺寸 (H, W)
    """
    import time
    import gc

    print(f"\n{'='*80}")
    print(f"🚀 网格模式推理 - 性能优化版")
    print(f"{'='*80}")

    total_start = time.time()

    # ========== 步骤1: 图像转换 ==========
    step_start = time.time()
    print(f"\n[步骤1/5] 图像格式转换...")

    if isinstance(image, Image.Image):
        image_np = np.array(image)
    else:
        image_np = image

    # 确保是 RGB
    if len(image_np.shape) == 2:
        image_np = cv2.cvtColor(image_np, cv2.COLOR_GRAY2RGB)
    elif image_np.shape[2] == 4:
        image_np = cv2.cvtColor(image_np, cv2.COLOR_RGBA2RGB)

    h, w = image_np.shape[:2]
    original_size = (h, w)

    step_time = time.time() - step_start
    print(f"  ✓ 原始尺寸: {w}x{h}")
    print(f"  ✓ 格式: RGB, shape={image_np.shape}")
    print(f"  ✓ 耗时: {step_time:.3f}s")

    # ========== 步骤2: Resize图像 ==========
    step_start = time.time()
    print(f"\n[步骤2/5] Resize图像到固定尺寸...")
    print(f"  目标尺寸: {grid_size}x{grid_size}")

    image_resized = cv2.resize(image_np, (grid_size, grid_size), interpolation=cv2.INTER_LINEAR)

    # 释放原始图像内存
    del image_np
    gc.collect()

    step_time = time.time() - step_start
    print(f"  ✓ Resize完成: {image_resized.shape}")
    print(f"  ✓ 缩放比例: {grid_size/w:.2f}x (宽), {grid_size/h:.2f}x (高)")
    print(f"  ✓ 耗时: {step_time:.3f}s")

    # ========== 步骤3: 网格划分 ==========
    step_start = time.time()
    print(f"\n[步骤3/5] 网格划分...")

    n_grids = grid_size // window_size
    total_windows = n_grids * n_grids

    print(f"  ✓ 网格数量: {n_grids}x{n_grids} = {total_windows}个窗口")
    print(f"  ✓ 每个窗口: {window_size}x{window_size}")
    print(f"  ✓ 无重叠，无冗余计算")

    step_time = time.time() - step_start
    print(f"  ✓ 耗时: {step_time:.3f}s")

    # ========== 步骤4: 批量推理 ==========
    print(f"\n[步骤4/5] 批量推理...")
    print(f"  总窗口数: {total_windows}")
    print(f"  预计时间: ~{total_windows * 48 / 60:.1f}分钟 (按48秒/窗口估算)")
    print(f"  {'='*80}")

    # 初始化预测结果
    prediction = np.zeros((grid_size, grid_size), dtype=np.float32)

    inference_start = time.time()
    window_count = 0

    # 记录每个窗口的详细时间
    window_times = []

    for i in range(n_grids):
        for j in range(n_grids):
            window_start = time.time()

            # 计算窗口位置
            y_start = i * window_size
            y_end = y_start + window_size
            x_start = j * window_size
            x_end = x_start + window_size

            # 提取窗口（优化：不拷贝，直接切片）
            extract_start = time.time()
            window = image_resized[y_start:y_end, x_start:x_end]
            extract_time = time.time() - extract_start

            # 预处理
            preprocess_start = time.time()
            window_tensor = preprocess_image_mobile(window, window_size).to(device)
            preprocess_time = time.time() - preprocess_start

            # 推理（核心瓶颈）
            inference_window_start = time.time()
            with torch.no_grad():
                output = model_inference(model, window_tensor, use_executorch)
            inference_window_time = time.time() - inference_window_start

            # 后处理
            postprocess_start = time.time()
            pred = output.cpu().numpy()[0, 0, ...]
            prediction[y_start:y_end, x_start:x_end] = pred
            postprocess_time = time.time() - postprocess_start

            # 清理内存（优化：减少GC频率）
            cleanup_start = time.time()
            del window_tensor, output, pred
            # 不在循环内调用 gc.collect()，避免性能损失
            cleanup_time = time.time() - cleanup_start

            window_total_time = time.time() - window_start
            window_times.append(window_total_time)
            window_count += 1

            # 显示详细进度
            elapsed = time.time() - inference_start
            avg_time = elapsed / window_count
            eta = avg_time * (total_windows - window_count)

            print(f"\r  窗口[{i},{j}] ({window_count}/{total_windows}) | "
                  f"提取:{extract_time*1000:.0f}ms 预处理:{preprocess_time*1000:.0f}ms "
                  f"推理:{inference_window_time:.1f}s 后处理:{postprocess_time*1000:.0f}ms "
                  f"清理:{cleanup_time*1000:.0f}ms | "
                  f"总:{window_total_time:.1f}s | "
                  f"已用:{elapsed:.0f}s 剩余:{eta:.0f}s", end='', flush=True)

    print()  # 换行

    inference_time = time.time() - inference_start
    print(f"  {'='*80}")
    print(f"  ✓ 推理完成!")
    print(f"  ✓ 总耗时: {inference_time:.1f}s ({inference_time/60:.1f}分钟)")
    print(f"  ✓ 平均每窗口: {inference_time/total_windows:.1f}s")
    print(f"  ✓ 最快窗口: {min(window_times):.1f}s")
    print(f"  ✓ 最慢窗口: {max(window_times):.1f}s")

    # ========== 步骤5: 清理和返回 ==========
    step_start = time.time()
    print(f"\n[步骤5/5] 清理内存...")

    del image_resized
    gc.collect()

    step_time = time.time() - step_start
    print(f"  ✓ 内存清理完成")
    print(f"  ✓ 耗时: {step_time:.3f}s")

    # ========== 总结 ==========
    total_time = time.time() - total_start
    print(f"\n{'='*80}")
    print(f"✅ 网格模式推理完成!")
    print(f"{'='*80}")
    print(f"  总耗时: {total_time:.1f}s ({total_time/60:.1f}分钟)")
    print(f"  推理占比: {inference_time/total_time*100:.1f}%")
    print(f"  其他占比: {(total_time-inference_time)/total_time*100:.1f}%")
    print(f"{'='*80}\n")

    return prediction, original_size

def sliding_window_predict(model, image, window_size=512, stride=256, device='cpu',
                          skip_empty_windows=True, valid_content_threshold=0.1,
                          batch_size=1, use_cache=False, cache_file=None,
                          auto_resize=True, max_dimension=1280, use_executorch=False):
    """
    使用滑动窗口对大图进行预测（移动端模型版本，支持缓存）

    Args:
        use_executorch: 是否使用 ExecuTorch 引擎

    Args:
        model: TorchScript 移动端模型
        image: PIL 图像
        window_size: 窗口大小（默认 512）
        stride: 滑动步长（默认 256）
        device: 设备
        skip_empty_windows: 是否跳过空白窗口
        valid_content_threshold: 有效内容阈值
        batch_size: 批处理大小（默认 1，增加可提速但占用更多内存）
        use_cache: 是否使用缓存
        cache_file: 缓存文件路径
        auto_resize: 是否自动resize大图以减少窗口数
        max_dimension: 自动resize时的最大尺寸

    Returns:
        prediction: 预测结果
        count_map: 计数图
        original_size: 原始图像尺寸 (H, W)
    """
    import hashlib
    import pickle

    # 转换为 numpy array (RGB)
    if isinstance(image, Image.Image):
        image_np = np.array(image)
    else:
        image_np = image

    # 确保是 RGB
    if len(image_np.shape) == 2:
        image_np = cv2.cvtColor(image_np, cv2.COLOR_GRAY2RGB)
    elif image_np.shape[2] == 4:
        image_np = cv2.cvtColor(image_np, cv2.COLOR_RGBA2RGB)

    h_orig, w_orig = image_np.shape[:2]
    original_size = (h_orig, w_orig)

    # 自动resize以减少窗口数
    if auto_resize and (h_orig > max_dimension or w_orig > max_dimension):
        scale = max_dimension / max(h_orig, w_orig)
        new_h = int(h_orig * scale)
        new_w = int(w_orig * scale)

        print(f"  🔧 自动Resize: {w_orig}x{h_orig} → {new_w}x{new_h}")
        print(f"     缩放比例: {scale:.2f}x")

        image_np = cv2.resize(image_np, (new_w, new_h), interpolation=cv2.INTER_LINEAR)

        # 计算窗口数对比
        import math
        old_windows = math.ceil(h_orig / stride) * math.ceil(w_orig / stride)
        new_windows = math.ceil(new_h / stride) * math.ceil(new_w / stride)
        print(f"     窗口数: {old_windows} → {new_windows} (减少{old_windows-new_windows}个)")

    h, w = image_np.shape[:2]

    # 检查缓存
    if use_cache and cache_file:
        # 生成缓存key（基于图像尺寸和参数，避免计算整个图像hash）
        cache_key = hashlib.md5(
            f"{h}_{w}_{window_size}_{stride}_{valid_content_threshold}_{batch_size}".encode()
        ).hexdigest()

        cache_path = f"{cache_file}_{cache_key}.npz"

        if os.path.exists(cache_path):
            print(f"  ✓ 发现缓存文件，直接加载...")
            try:
                cached_data = np.load(cache_path)
                prediction = cached_data['prediction']
                count_map = cached_data['count_map']
                print(f"  ✓ 缓存加载成功！跳过推理")
                return prediction, count_map, original_size
            except Exception as e:
                print(f"  ⚠ 缓存加载失败: {e}，重新推理")

    # 初始化预测结果
    prediction = np.zeros((h, w), dtype=np.float32)
    count_map = np.zeros((h, w), dtype=np.float32)

    # 检测有效区域
    if skip_empty_windows:
        print("  检测有效区域...")
        valid_mask = detect_valid_region(image_np)
    else:
        valid_mask = None

    # 计算窗口数量（确保覆盖整个图像）
    import math
    n_windows_h = max(1, math.ceil((h - window_size) / stride) + 1) if h > window_size else 1
    n_windows_w = max(1, math.ceil((w - window_size) / stride) + 1) if w > window_size else 1

    # 如果图像小于窗口大小，只需要一个窗口
    if h <= window_size:
        n_windows_h = 1
    if w <= window_size:
        n_windows_w = 1

    total_windows = n_windows_h * n_windows_w

    print(f"  图像尺寸: {w}x{h}")
    print(f"  窗口大小: {window_size}x{window_size}")
    print(f"  滑动步长: {stride}")
    print(f"  窗口数量: {n_windows_w}x{n_windows_h} = {total_windows}")
    print(f"  批处理大小: {batch_size}")

    # 收集所有窗口信息
    print(f"  正在收集窗口信息...")
    windows_info = []

    for i in range(n_windows_h):
        for j in range(n_windows_w):
            # 计算窗口位置
            # 对于最后一个窗口，从图像边缘向内取 window_size
            if i == n_windows_h - 1 and h > window_size:
                y_start = h - window_size
                y_end = h
            else:
                y_start = i * stride
                y_end = min(y_start + window_size, h)

            if j == n_windows_w - 1 and w > window_size:
                x_start = w - window_size
                x_end = w
            else:
                x_start = j * stride
                x_end = min(x_start + window_size, w)

            # 提取窗口
            window = image_np[y_start:y_end, x_start:x_end]
            actual_h, actual_w = window.shape[:2]

            # 检查是否跳过空白窗口
            if skip_empty_windows and valid_mask is not None:
                window_valid_mask = valid_mask[y_start:y_end, x_start:x_end]
                valid_ratio = window_valid_mask.sum() / (actual_h * actual_w * 255)

                if valid_ratio < valid_content_threshold:
                    continue

            windows_info.append({
                'window': window,
                'y_start': y_start,
                'y_end': y_end,
                'x_start': x_start,
                'x_end': x_end,
                'actual_h': actual_h,
                'actual_w': actual_w
            })

    total_valid_windows = len(windows_info)
    skipped_count = total_windows - total_valid_windows
    print(f"  ✓ 收集完成: 有效窗口 {total_valid_windows}, 跳过 {skipped_count}")
    print(f"  有效窗口: {total_valid_windows}/{total_windows} (跳过 {skipped_count} 个空白窗口)")

    # 批处理推理
    window_count = 0
    import gc
    import sys

    print(f"  开始推理... (总共 {total_valid_windows} 个窗口)")
    print(f"  ⚠️  注意: Mamba模型在CPU上较慢，首次推理约需6-7分钟，请耐心等待...")
    start_time = time.time()
    last_progress_time = start_time

    for batch_start in range(0, total_valid_windows, batch_size):
        batch_end = min(batch_start + batch_size, total_valid_windows)
        batch_windows = windows_info[batch_start:batch_end]

        try:
            # 在每个批次前清理内存
            gc.collect()
            if device.type == 'cuda':
                torch.cuda.empty_cache()

            # 预处理批次
            batch_tensors = []
            for info in batch_windows:
                window_tensor = preprocess_image_mobile(info['window'], window_size)
                batch_tensors.append(window_tensor)

            # 合并为批次
            if len(batch_tensors) > 1:
                batch_input = torch.cat(batch_tensors, dim=0).to(device)
            else:
                batch_input = batch_tensors[0].to(device)

            # 立即清理batch_tensors
            del batch_tensors

            # 批量推理
            with torch.no_grad():
                batch_output = model_inference(model, batch_input, use_executorch)

            # 立即清理输入
            del batch_input

            # 立即移到CPU并清理GPU内存
            batch_output_cpu = batch_output.cpu().numpy()
            del batch_output
            if device.type == 'cuda':
                torch.cuda.empty_cache()

            # 处理批次结果
            for idx, info in enumerate(batch_windows):
                # 获取输出 (模型输出尺寸 = 输入尺寸)
                pred = batch_output_cpu[idx, 0, ...]

                # 获取模型输出的实际尺寸
                pred_h, pred_w = pred.shape

                # 如果输出尺寸与期望的窗口大小不一致，需要resize
                if pred_h != info['actual_h'] or pred_w != info['actual_w']:
                    pred = cv2.resize(pred, (info['actual_w'], info['actual_h']),
                                    interpolation=cv2.INTER_LINEAR)

                # 累加到预测结果
                prediction[info['y_start']:info['y_end'],
                          info['x_start']:info['x_end']] += pred
                count_map[info['y_start']:info['y_end'],
                         info['x_start']:info['x_end']] += 1

                window_count += 1

            # 清理内存
            del batch_output_cpu

            # 每个批次都执行垃圾回收
            gc.collect()

        except Exception as e:
            print(f"\n  ✗ 批次 {batch_start}-{batch_end} 处理失败: {e}")
            import traceback
            traceback.print_exc()
            continue

        # 显示进度（每个窗口都显示，但限制更新频率避免IO阻塞）
        current_time = time.time()
        if current_time - last_progress_time >= 0.5 or window_count == total_valid_windows:  # 每0.5秒更新一次
            progress = window_count / total_valid_windows * 100
            elapsed = current_time - start_time
            avg_time_per_window = elapsed / window_count if window_count > 0 else 0
            eta = avg_time_per_window * (total_valid_windows - window_count)

            # 使用 \r 实现同行更新
            sys.stdout.write(f"\r  进度: {window_count}/{total_valid_windows} ({progress:.1f}%) | "
                            f"已用时: {elapsed:.1f}s | 预计剩余: {eta:.1f}s | "
                            f"速度: {avg_time_per_window:.1f}s/窗口")
            sys.stdout.flush()
            last_progress_time = current_time

    # 换行并显示完成信息
    print()  # 换行
    total_time = time.time() - start_time
    print(f"  ✓ 完成! 处理: {window_count}, 跳过: {skipped_count}, 总耗时: {total_time:.1f}s")

    # 平均化
    count_map[count_map == 0] = 1
    prediction = prediction / count_map

    # 保存缓存
    if use_cache and cache_file:
        try:
            os.makedirs(os.path.dirname(cache_file), exist_ok=True)
            np.savez_compressed(cache_path, prediction=prediction, count_map=count_map)
            print(f"  ✓ 缓存已保存: {cache_path}")
        except Exception as e:
            print(f"  ⚠ 缓存保存失败: {e}")

    return prediction, count_map, original_size


def extract_crack_skeletons(binary_mask):
    """
    提取裂缝的骨架

    Args:
        binary_mask: 二值化的裂缝mask

    Returns:
        skeleton: 骨架图
    """
    # 确保是二值图
    binary = (binary_mask > 0).astype(np.uint8)

    # 骨架化
    skeleton = morphology.skeletonize(binary)

    return skeleton.astype(np.uint8)

def measure_crack_lengths(skeleton, pixel_to_cm, min_length_pixels=20):
    """
    测量每条裂缝的长度

    Args:
        skeleton: 骨架图
        pixel_to_cm: 像素到厘米的转换比例
        min_length_pixels: 最小裂缝长度（像素），小于此值的忽略

    Returns:
        crack_info: 裂缝信息列表
    """
    # 标记连通区域
    labeled_skeleton = measure.label(skeleton, connectivity=2)

    crack_info = []

    # 遍历每个连通区域
    for region in measure.regionprops(labeled_skeleton):
        # 获取区域的像素数量（骨架长度的近似）
        length_pixels = region.area

        # 过滤太小的区域
        if length_pixels < min_length_pixels:
            continue

        # 转换为厘米
        length_cm = length_pixels * pixel_to_cm

        # 获取边界框
        minr, minc, maxr, maxc = region.bbox

        crack_info.append({
            'id': region.label,
            'length_pixels': length_pixels,
            'length_cm': length_cm,
            'bbox': (minc, minr, maxc - minc, maxr - minr),
            'centroid': region.centroid
        })

    return crack_info

def create_visualization_all(original_img, crack_mask, crack_info, pixel_to_cm, ruler_bbox=None, ruler_length_cm=50):
    """
    创建完整的可视化结果（类似predict_with_ruler.py的visualization_all）

    Args:
        original_img: 原始图像 (PIL Image 或 numpy array)
        crack_mask: 裂缝二值mask
        crack_info: 裂缝信息列表
        pixel_to_cm: 像素到厘米的转换比例
        ruler_bbox: 尺子边界框 (x, y, w, h)
        ruler_length_cm: 尺子长度（厘米）

    Returns:
        vis: 可视化结果 (RGB)
    """
    # 转换为 numpy array
    if isinstance(original_img, Image.Image):
        img_np = np.array(original_img)
    else:
        img_np = original_img.copy()

    vis = img_np.copy()

    # 绘制尺子边界框（绿色）
    if ruler_bbox is not None:
        x, y, w, h = ruler_bbox
        cv2.rectangle(vis, (x, y), (x+w, y+h), (0, 255, 0), 4)
        cv2.putText(vis, f"Ruler: {ruler_length_cm}cm", (x, y-10),
                   cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 255, 0), 3)

    # 绘制裂缝（半透明红色）
    crack_colored = np.zeros_like(img_np)
    crack_colored[:, :, 2] = crack_mask  # 红色通道
    vis = cv2.addWeighted(vis, 0.7, crack_colored, 0.3, 0)

    # 绘制每条裂缝的标注
    for i, crack in enumerate(crack_info):
        x, y, w, h = crack['bbox']
        cx, cy = int(crack['centroid'][1]), int(crack['centroid'][0])

        # 根据裂缝长度选择颜色
        if crack['length_cm'] > 30:
            color = (0, 0, 255)  # 红色 - 长裂缝
            thickness = 3
        elif crack['length_cm'] > 15:
            color = (0, 165, 255)  # 橙色 - 中等裂缝
            thickness = 2
        else:
            color = (0, 255, 255)  # 黄色 - 短裂缝
            thickness = 2

        # 绘制边界框
        cv2.rectangle(vis, (x, y), (x+w, y+h), color, thickness)

        # 绘制中心点
        cv2.circle(vis, (cx, cy), 5, color, -1)

        # 绘制标签（带背景）
        label = f"#{i+1}: {crack['length_cm']:.1f}cm"
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 0.7
        font_thickness = 2

        # 计算文本大小
        (text_w, text_h), baseline = cv2.getTextSize(label, font, font_scale, font_thickness)

        # 确定标签位置（避免超出图像边界）
        label_x = max(x, 5)
        label_y = max(y - 10, text_h + 10)

        # 绘制文本背景（黑色半透明）
        overlay = vis.copy()
        cv2.rectangle(overlay,
                     (label_x - 5, label_y - text_h - 5),
                     (label_x + text_w + 5, label_y + baseline + 5),
                     (0, 0, 0), -1)
        vis = cv2.addWeighted(vis, 0.6, overlay, 0.4, 0)

        # 绘制文本
        cv2.putText(vis, label, (label_x, label_y),
                   font, font_scale, color, font_thickness)

    # 添加图例
    legend_y = 30
    legend_x = vis.shape[1] - 250

    # 图例背景
    overlay = vis.copy()
    cv2.rectangle(overlay, (legend_x - 10, 10), (vis.shape[1] - 10, 150), (0, 0, 0), -1)
    vis = cv2.addWeighted(vis, 0.7, overlay, 0.3, 0)

    # 图例文本
    cv2.putText(vis, "Crack Length:", (legend_x, legend_y),
               cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
    cv2.putText(vis, "> 30cm", (legend_x, legend_y + 30),
               cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)
    cv2.putText(vis, "15-30cm", (legend_x, legend_y + 60),
               cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 2)
    cv2.putText(vis, "< 15cm", (legend_x, legend_y + 90),
               cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 2)

    # 添加统计信息
    stats_y = vis.shape[0] - 100
    stats_x = 20

    # 统计背景
    overlay = vis.copy()
    cv2.rectangle(overlay, (10, stats_y - 30), (350, vis.shape[0] - 10), (0, 0, 0), -1)
    vis = cv2.addWeighted(vis, 0.7, overlay, 0.3, 0)

    # 统计文本
    total_length = sum(c['length_cm'] for c in crack_info)
    cv2.putText(vis, f"Total Cracks: {len(crack_info)}", (stats_x, stats_y),
               cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
    cv2.putText(vis, f"Total Length: {total_length:.1f} cm", (stats_x, stats_y + 30),
               cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
    if len(crack_info) > 0:
        avg_length = total_length / len(crack_info)
        cv2.putText(vis, f"Avg Length: {avg_length:.1f} cm", (stats_x, stats_y + 60),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)

    return vis

def visualize_joint_spacing(skeleton, results, test_lines, pixel_to_cm):
    """
    在骨架图上可视化节理间距计算过程

    Args:
        skeleton: 裂缝骨架图（二值图）
        results: 节理间距计算结果列表
        test_lines: 测线坐标列表
        pixel_to_cm: 像素到厘米的转换比例

    Returns:
        vis_img: 可视化图像（BGR格式）
    """
    # 创建彩色图像
    if len(skeleton.shape) == 2:
        vis_img = cv2.cvtColor((skeleton * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    else:
        vis_img = skeleton.copy()

    # 定义颜色
    line_colors = [
        (0, 255, 255),    # H-Line1 - 黄色
        (0, 165, 255),    # H-Line2 - 橙色
        (255, 0, 255),    # V-Line1 - 品红
        (255, 255, 0),    # V-Line2 - 青色
    ]

    # 英文标签
    line_labels = ['H-Line1', 'H-Line2', 'V-Line1', 'V-Line2']

    # 绘制每条测线及其交点
    for i, (result, line_info) in enumerate(zip(results, test_lines)):
        color = line_colors[i]
        line_label = line_labels[i]
        intersections = result['intersections']

        # 从字典中提取起点和终点
        line_start = line_info['start']
        line_end = line_info['end']

        # 1. 绘制测线（实线，从边缘到边缘）
        cv2.line(vis_img, line_start, line_end, color, thickness=3)

        # 2. 标记交点
        for j, (x, y, dist) in enumerate(intersections):
            # 绘制交点圆圈
            cv2.circle(vis_img, (int(x), int(y)), 6, (0, 0, 255), -1)  # 红色实心圆
            cv2.circle(vis_img, (int(x), int(y)), 8, (255, 255, 255), 2)  # 白色边框

            # 标注交点编号
            label = f"{chr(65+j)}"  # A, B, C, D, ...
            cv2.putText(vis_img, label, (int(x)+12, int(y)-12),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)

        # 3. 在测线中点标注节理间距
        mid_x = (line_start[0] + line_end[0]) // 2
        mid_y = (line_start[1] + line_end[1]) // 2

        spacing_label = f"{line_label}: {result['avg_spacing_cm']:.1f}cm"

        # 根据测线类型调整标签位置
        if i < 2:  # 横线
            label_pos = (mid_x - 70, mid_y - 40 if i == 0 else mid_y + 50)
        else:  # 竖线
            label_pos = (mid_x - 90 if i == 2 else mid_x + 20, mid_y)

        # 绘制背景框
        (text_w, text_h), _ = cv2.getTextSize(spacing_label, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
        cv2.rectangle(vis_img,
                     (label_pos[0]-5, label_pos[1]-text_h-5),
                     (label_pos[0]+text_w+5, label_pos[1]+5),
                     (0, 0, 0), -1)

        # 绘制文本
        cv2.putText(vis_img, spacing_label, label_pos,
                   cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

    # 4. 添加节理间距信息面板（右上角）
    joint_spacing_avg = np.mean([r['avg_spacing_cm'] for r in results])

    panel_x = vis_img.shape[1] - 320
    panel_y = 30
    panel_w = 300
    panel_h = 150

    # 绘制半透明背景
    overlay = vis_img.copy()
    cv2.rectangle(overlay, (panel_x, panel_y), (panel_x+panel_w, panel_y+panel_h), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.7, vis_img, 0.3, 0, vis_img)

    # 绘制边框
    cv2.rectangle(vis_img, (panel_x, panel_y), (panel_x+panel_w, panel_y+panel_h), (255, 255, 255), 2)

    # 标题
    cv2.putText(vis_img, "Joint Spacing Analysis", (panel_x+10, panel_y+25),
               cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)

    # 各测线节理间距
    y_offset = 55
    for i, result in enumerate(results):
        text = f"{line_labels[i]}: {result['avg_spacing_cm']:.1f}cm"
        cv2.putText(vis_img, text, (panel_x+10, panel_y+y_offset),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.45, line_colors[i], 1)
        y_offset += 22

    # 平均节理间距
    cv2.putText(vis_img, f"Avg Spacing: {joint_spacing_avg:.1f}cm", (panel_x+10, panel_y+y_offset+5),
               cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

    return vis_img


def visualize_result(image, prediction, threshold=0.5, alpha=0.4):
    """
    可视化检测结果

    Args:
        image: 原始图像 (PIL Image 或 numpy array)
        prediction: 预测结果 (numpy array)
        threshold: 二值化阈值
        alpha: 叠加透明度

    Returns:
        result_img: 可视化结果 (BGR)
        binary_mask: 二值化掩码
    """
    # 转换为 numpy array
    if isinstance(image, Image.Image):
        image_np = np.array(image)
    else:
        image_np = image.copy()

    # 转换为 BGR
    if len(image_np.shape) == 2:
        image_bgr = cv2.cvtColor(image_np, cv2.COLOR_GRAY2BGR)
    elif image_np.shape[2] == 3:
        image_bgr = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)
    else:
        image_bgr = cv2.cvtColor(image_np, cv2.COLOR_RGBA2BGR)

    # 应用 sigmoid
    prediction_sigmoid = 1.0 / (1.0 + np.exp(-prediction))

    # 二值化
    binary_mask = (prediction_sigmoid > threshold).astype(np.uint8) * 255

    # 创建彩色掩码（红色）
    color_mask = np.zeros_like(image_bgr)
    color_mask[binary_mask > 0] = [0, 0, 255]  # 红色 (BGR)

    # 叠加
    result_img = cv2.addWeighted(image_bgr, 1 - alpha, color_mask, alpha, 0)

    return result_img, binary_mask

def main(args):
    # 处理快捷模式
    if args.use_grid and args.grid_size:
        # 自定义网格模式
        print(f"🔧 自定义网格模式: resize到{args.grid_size}x{args.grid_size}")
        print(f"   窗口大小: {args.window_size}x{args.window_size}")
        args.grid_mode = True
        n_grids = args.grid_size // args.window_size
        print(f"   网格划分: {n_grids}x{n_grids} = {n_grids*n_grids}个窗口")
    elif args.medium:
        print("🔷 中窗口模式: resize到640x640, 2x2网格, 4次扫描")
        print("   计算量: 512² → 320² = 减少2.5倍")
        args.grid_mode = True
        args.grid_size = 640
        args.window_size = 320
    elif args.small:
        print("🔸 小窗口模式: 320x320窗口, 计算量减少2.5倍")
        args.grid_mode = True
        args.grid_size = 1024
        args.window_size = 320
        print(f"   网格划分: {args.grid_size//args.window_size}x{args.grid_size//args.window_size} = {(args.grid_size//args.window_size)**2}个窗口")
    elif args.ultra_fast:
        print("⚡ 超快模式: resize到512x512, 1次扫描")
        args.grid_mode = True
        args.grid_size = 512
        args.window_size = 512
    elif args.grid:
        print("🎯 网格模式: resize到1024x1024, 2x2网格, 4次扫描")
        args.grid_mode = True
        args.grid_size = 1024
        args.window_size = 512
    else:
        args.grid_mode = False
        if args.fast:
            args.stride = 512
            print("🚀 快速模式: stride=512 (无重叠)")
        elif args.balanced:
            args.stride = 384
            print("⚖️  平衡模式: stride=384 (25%重叠)")
        elif args.accurate:
            args.stride = 256
            print("🎯 精确模式: stride=256 (50%重叠)")

    print("=" * 80)
    print("移动端模型裂隙检测（支持大图切片 + 尺子检测 + 指标计算）")
    print("=" * 80)
    print(f"模型: {args.model}")
    print(f"图像: {args.image}")
    print(f"窗口大小: {args.window_size}")
    print(f"滑动步长: {args.stride} (重叠率: {max(0, (1-args.stride/args.window_size)*100):.0f}%)")
    print(f"阈值: {args.threshold}")
    print(f"设备: {args.device}")
    if args.calculate_indicators:
        print(f"尺子长度: {args.ruler_length} cm")
        print(f"尺子颜色: {args.ruler_color}")
        print(f"计算指标: 是")
    print("=" * 80)

    # 检查文件
    if not os.path.exists(args.model):
        print(f"✗ 模型文件不存在: {args.model}")
        return

    if not os.path.exists(args.image):
        print(f"✗ 图像文件不存在: {args.image}")
        return

    # 设置设备
    device = torch.device(args.device)

    # 读取图片
    print("\n[1/7] 正在读取图片..." if args.enhance else "\n[1/6] 正在读取图片...")
    original_img = Image.open(args.image).convert('RGB')
    print(f"✓ 图片尺寸: {original_img.size[0]}x{original_img.size[1]}")

    # 图像增强（如果启用）
    if args.enhance:
        print("\n[2/7] 正在进行图像增强...")
        try:
            enhanced_img = cracknex_retinex_enhancement(original_img)

            # 保存增强后的图片到输出目录
            os.makedirs(args.output_dir, exist_ok=True)
            base_name = os.path.splitext(os.path.basename(args.image))[0]
            enhanced_output_path = os.path.join(args.output_dir, f"{base_name}_enhanced.jpg")
            enhanced_img.save(enhanced_output_path)
            print(f"✓ 增强图片已保存: {enhanced_output_path}")

            # 使用增强后的图片进行后续处理
            original_img = enhanced_img
            print(f"✓ 将使用增强后的图片进行检测")
        except Exception as e:
            print(f"⚠ 图像增强失败: {e}，将使用原始图片")
            # 继续使用原始图片

    # 检测尺子（如果指定了ruler_length）
    pixel_to_cm = None
    ruler_mask = None
    ruler_bbox = None

    if args.ruler_length is not None and args.ruler_length > 0:
        step_num = "3/7" if args.enhance else "2/6"
        print(f"\n[{step_num}] 正在检测尺子...")
        color_name = {'yellow': '黄色', 'red': '红色', 'both': '黄色和红色'}[args.ruler_color]
        print(f"  检测颜色: {color_name}")
        pixel_to_cm, ruler_mask, ruler_bbox = detect_ruler(original_img, args.ruler_length, args.ruler_color)

        if pixel_to_cm is None:
            print("⚠️  警告: 无法检测到尺子，将使用默认比例")
            print(f"  提示: 当前检测颜色为 '{args.ruler_color}'")
            print(f"  如果尺子是其他颜色，请使用 --ruler_color 参数指定 (yellow/red/both)")
            # 不返回，继续执行，但后续会使用默认比例

    # 加载模型
    if args.enhance:
        step_num = "4/7" if args.calculate_indicators else "3/7"
    else:
        step_num = "3/6" if args.calculate_indicators else "1/6"
    print(f"\n[{step_num}] 加载模型...")

    # 检测模型类型
    model_ext = os.path.splitext(args.model)[1].lower()
    use_executorch = model_ext == '.pte'

    try:
        if use_executorch:
            # ExecuTorch 模型 (.pte)
            if not EXECUTORCH_AVAILABLE:
                print("✗ ExecuTorch 未安装，无法加载 .pte 模型")
                print("  请安装: pip install executorch")
                return
            print("  使用 ExecuTorch 引擎")
            model = _load_for_executorch(args.model)
            print("✓ ExecuTorch 模型加载成功")
        else:
            # TorchScript 模型 (.ptl, .pt)
            print("  使用 TorchScript 引擎")
            model = torch.jit.load(args.model, map_location=device)
            model.eval()
            print("✓ TorchScript 模型加载成功")
    except Exception as e:
        print(f"✗ 模型加载失败: {e}")
        return

    # 滑动窗口预测
    if args.enhance:
        step_num = "5/7" if args.calculate_indicators else "4/7"
    else:
        step_num = "4/6" if args.calculate_indicators else "2/6"
    print(f"\n[{step_num}] 裂隙检测推理...")

    if args.grid_mode:
        print(f"  模式: 🚀 网格模式（最快）")
        print(f"  网格尺寸: {args.grid_size}x{args.grid_size}")
        print(f"  窗口大小: {args.window_size}x{args.window_size}")
        print(f"  网格数量: {args.grid_size//args.window_size}x{args.grid_size//args.window_size}")
    else:
        print(f"  模式: 滑动窗口")
        print(f"  窗口大小: {args.window_size}x{args.window_size}")
        print(f"  滑动步长: {args.stride} (重叠率: {(1-args.stride/args.window_size)*100:.0f}%)")
        print(f"  批处理大小: {args.batch_size}")
        if args.use_cache:
            print(f"  缓存: 启用")

    # 准备缓存文件路径
    cache_file = None
    if args.use_cache and not args.grid_mode:
        os.makedirs(args.cache_dir, exist_ok=True)
        base_name = os.path.splitext(os.path.basename(args.image))[0]
        cache_file = os.path.join(args.cache_dir, base_name)

    start_time = time.time()

    # 根据模式选择推理方式
    if args.grid_mode:
        # 网格模式
        prediction, original_size = grid_predict(
            model, original_img,
            grid_size=args.grid_size,
            window_size=args.window_size,
            device=device,
            use_executorch=use_executorch
        )
        # Resize回原始尺寸
        print(f"\n[后处理] Resize回原始尺寸...")
        resize_start = time.time()
        h_orig, w_orig = original_size
        prediction = cv2.resize(prediction, (w_orig, h_orig), interpolation=cv2.INTER_LINEAR)
        resize_time = time.time() - resize_start
        print(f"  ✓ Resize完成: {w_orig}x{h_orig}")
        print(f"  ✓ 耗时: {resize_time:.3f}s")
    else:
        # 滑动窗口模式
        prediction, count_map, slide_original_size = sliding_window_predict(
            model, original_img,
            window_size=args.window_size,
            stride=args.stride,
            device=device,
            skip_empty_windows=args.skip_empty,
            valid_content_threshold=args.valid_threshold,
            batch_size=args.batch_size,
            use_cache=args.use_cache,
            cache_file=cache_file,
            auto_resize=True,
            max_dimension=1280,
            use_executorch=use_executorch
        )

        # 如果进行了auto_resize，需要resize回原始尺寸
        h_slide, w_slide = prediction.shape
        h_orig, w_orig = slide_original_size
        if h_slide != h_orig or w_slide != w_orig:
            print(f"\n[后处理] Resize回原始尺寸...")
            resize_start = time.time()
            prediction = cv2.resize(prediction, (w_orig, h_orig), interpolation=cv2.INTER_LINEAR)
            resize_time = time.time() - resize_start
            print(f"  ✓ Resize完成: {w_orig}x{h_orig}")
            print(f"  ✓ 耗时: {resize_time:.3f}s")

    inference_time = time.time() - start_time
    print(f"\n{'='*80}")
    print(f"✅ 预测完成，总耗时: {inference_time:.2f}秒 ({inference_time/60:.2f}分钟)")
    print(f"{'='*80}")

    # 后处理
    print(f"\n[后处理] 二值化处理...")
    postprocess_start = time.time()
    pred_norm = prediction / np.max(prediction) if np.max(prediction) > 0 else prediction
    pred_binary = ((pred_norm > args.threshold) * 255).astype(np.uint8)
    postprocess_time = time.time() - postprocess_start
    print(f"  ✓ 阈值: {args.threshold}")
    print(f"  ✓ 耗时: {postprocess_time:.3f}s")

    # 移除尺子区域（如果检测到尺子）
    crack_mask_clean = pred_binary
    if args.calculate_indicators and ruler_mask is not None:
        if args.enhance:
            step_num = "6/7"
        else:
            step_num = "5/6"
        print(f"\n[{step_num}] 正在移除尺子区域...")
        crack_mask_clean = remove_ruler_from_mask(pred_binary, ruler_mask)
        print("✓ 尺子区域已移除")

    # 提取骨架和测量裂缝（始终执行，用于生成visualization_all）
    skeleton = None
    crack_info = []
    indicator1 = None
    joint_spacing_avg = None
    indicator3 = None
    rqd_results = None
    test_lines = None

    # 如果有尺子长度，就可以提取骨架和测量裂缝
    if args.ruler_length is not None and args.ruler_length > 0:
        if args.enhance:
            step_num = "6/7"
        else:
            step_num = "5/6"
        print(f"\n[{step_num}] 提取裂缝骨架和测量长度...")

        # 计算pixel_to_cm（如果还没有）
        if pixel_to_cm is None:
            # 使用默认值：假设图像宽度对应ruler_length cm
            pixel_to_cm = args.ruler_length / original_img.size[0]
            print(f"  使用默认比例: 1像素 = {pixel_to_cm:.4f} cm")

        # 提取骨架
        print("  提取裂缝骨架...")
        skeleton = extract_crack_skeletons(crack_mask_clean)

        # 测量裂缝长度
        print("  测量裂缝长度...")
        min_length_pixels = args.min_crack_length / pixel_to_cm
        crack_info = measure_crack_lengths(skeleton, pixel_to_cm, min_length_pixels)
        print(f"  ✓ 检测到 {len(crack_info)} 条裂缝")

    # 计算指标（如果启用）
    if args.calculate_indicators and pixel_to_cm is not None and skeleton is not None:
        print(f"\n  正在计算岩石质量指标...")

        # 图像尺寸
        image_shape = (original_img.size[1], original_img.size[0])  # (height, width)
        image_width_cm = original_img.size[0] * pixel_to_cm
        image_height_cm = original_img.size[1] * pixel_to_cm

        # 检测有效区域（如果启用）
        valid_ratio = 1.0
        if args.detect_valid_region:
            print("  检测图像有效区域...")
            valid_mask = detect_valid_region(original_img, threshold=args.valid_region_threshold)
            valid_area_pixels = np.sum(valid_mask > 0)
            total_pixels = original_img.size[0] * original_img.size[1]
            valid_ratio = valid_area_pixels / total_pixels if total_pixels > 0 else 1.0
            print(f"  有效区域比例: {valid_ratio*100:.1f}%")

        # 计算面积
        image_area_cm2_total = image_width_cm * image_height_cm
        image_area_cm2 = image_area_cm2_total * valid_ratio
        image_area_m2 = image_area_cm2 / 10000  # cm² 转 m²

        # 指标1 = (长度≥25cm的裂隙条数) / 图像面积（m²）
        long_cracks_count = sum(1 for c in crack_info if c['length_cm'] >= 25)
        indicator1 = long_cracks_count / image_area_m2 if image_area_m2 > 0 else 0

        # 指标2 - 节理间距
        print("  计算节理间距...")
        joint_spacing_avg, rqd_results, test_lines = calculate_joint_spacing_four_lines(
            image_shape, skeleton, pixel_to_cm
        )

        # 指标3 = 裂隙总长度（m） / 图像面积（m²）
        total_crack_length_cm = sum(c['length_cm'] for c in crack_info)
        total_crack_length_m = total_crack_length_cm / 100  # cm 转 m
        indicator3 = total_crack_length_m / image_area_m2 if image_area_m2 > 0 else 0

        print(f"✓ 岩石质量指标计算完成!")
        print(f"\n  图像实际尺寸: {image_width_cm:.1f} cm × {image_height_cm:.1f} cm")
        if args.detect_valid_region:
            print(f"  图像总面积: {image_area_cm2_total:.1f} cm²")
            print(f"  有效区域比例: {valid_ratio*100:.1f}%")
            print(f"  有效区域面积: {image_area_cm2:.1f} cm² ({image_area_m2:.4f} m²)")
        else:
            print(f"  图像面积: {image_area_cm2:.1f} cm² ({image_area_m2:.4f} m²)")
        print(f"  裂隙总数: {len(crack_info)} 条")
        print(f"  长度≥25cm的裂隙: {long_cracks_count} 条")
        print(f"  裂隙总长度: {total_crack_length_cm:.1f} cm ({total_crack_length_m:.2f} m)")
        print(f"\n  指标1: {indicator1:.4f} 条/m²")
        print(f"  指标2 - 平均节理间距: {joint_spacing_avg:.2f} cm")
        print(f"  指标3: {indicator3:.4f} m/m²")

    # 可视化
    if args.enhance:
        step_num = "6.5/7" if args.calculate_indicators else "5/7"
    else:
        step_num = "6/6" if args.calculate_indicators else "3/6"
    print(f"\n[{step_num}] 生成可视化结果...")
    result_img, binary_mask = visualize_result(original_img, prediction, args.threshold, args.alpha)

    # 计算统计信息
    crack_ratio = (binary_mask > 0).sum() / binary_mask.size * 100
    print(f"✓ 裂隙占比: {crack_ratio:.2f}%")

    # 保存结果
    if args.enhance:
        step_num = "7/7"
    else:
        step_num = "6/6"
    print(f"\n[{step_num}] 保存结果...")
    output_dir = args.output_dir
    os.makedirs(output_dir, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_name = os.path.splitext(os.path.basename(args.image))[0]

    # 创建带时间戳的子目录（类似predict_with_ruler.py）
    result_subdir = os.path.join(output_dir, f"{timestamp}_{base_name}")
    os.makedirs(result_subdir, exist_ok=True)

    # 保存各种结果
    prob_map_path = os.path.join(result_subdir, f"{base_name}_prob.png")
    mask_path = os.path.join(result_subdir, f"{base_name}_mask.png")
    result_path = os.path.join(result_subdir, f"{base_name}_result.png")

    # 应用 sigmoid 并保存概率图
    prediction_sigmoid = 1.0 / (1.0 + np.exp(-prediction))
    cv2.imwrite(prob_map_path, (prediction_sigmoid * 255).astype(np.uint8))
    cv2.imwrite(mask_path, binary_mask)
    cv2.imwrite(result_path, result_img)

    # 保存骨架图和visualization_all（如果提取了骨架）
    if skeleton is not None:
        # 保存骨架图
        skeleton_path = os.path.join(result_subdir, f"{base_name}_skeleton.png")
        cv2.imwrite(skeleton_path, skeleton * 255)
        print(f"  - 骨架图: {os.path.basename(skeleton_path)}")

        # 如果计算了节理间距，保存joint_spacing可视化
        if rqd_results is not None and test_lines is not None:
            spacing_vis = visualize_joint_spacing(skeleton, rqd_results, test_lines, pixel_to_cm)
            spacing_vis_path = os.path.join(result_subdir, f"{base_name}_joint_spacing.jpg")
            cv2.imwrite(spacing_vis_path, spacing_vis)
            print(f"  - 节理间距分析: {os.path.basename(spacing_vis_path)}")

        # 如果有裂缝信息，创建并保存visualization_all
        if len(crack_info) > 0:
            vis_all = create_visualization_all(
                original_img,
                crack_mask_clean,
                crack_info,
                pixel_to_cm,
                ruler_bbox=ruler_bbox,  # 使用检测到的尺子边界框
                ruler_length_cm=args.ruler_length
            )
            vis_all_path = os.path.join(result_subdir, f"{base_name}_visualization_all.jpg")
            cv2.imwrite(vis_all_path, cv2.cvtColor(vis_all, cv2.COLOR_RGB2BGR))
            print(f"  - 完整可视化: {os.path.basename(vis_all_path)}")

    print(f"✓ 结果已保存到: {result_subdir}")
    print(f"  - 概率图: {os.path.basename(prob_map_path)}")
    print(f"  - 二值掩码: {os.path.basename(mask_path)}")
    print(f"  - 可视化结果: {os.path.basename(result_path)}")

    # 保存指标结果（如果计算了）
    if args.calculate_indicators and indicator1 is not None:
        report_path = os.path.join(result_subdir, f"{base_name}_report.txt")
        with open(report_path, 'w', encoding='utf-8') as f:
            f.write("=" * 80 + "\n")
            f.write("岩石质量指标报告\n")
            f.write("=" * 80 + "\n\n")
            f.write(f"图像文件: {args.image}\n")
            f.write(f"处理时间: {timestamp}\n\n")

            f.write("--- 图像信息 ---\n")
            f.write(f"图像尺寸: {original_img.size[0]}x{original_img.size[1]} 像素\n")
            f.write(f"实际尺寸: {image_width_cm:.1f} cm × {image_height_cm:.1f} cm\n")
            if args.detect_valid_region:
                f.write(f"总面积: {image_area_cm2_total:.1f} cm²\n")
                f.write(f"有效区域比例: {valid_ratio*100:.1f}%\n")
                f.write(f"有效面积: {image_area_cm2:.1f} cm² ({image_area_m2:.4f} m²)\n")
            else:
                f.write(f"图像面积: {image_area_cm2:.1f} cm² ({image_area_m2:.4f} m²)\n")
            f.write(f"像素比例: 1 像素 = {pixel_to_cm:.4f} cm\n\n")

            f.write("--- 裂隙统计 ---\n")
            f.write(f"裂隙总数: {len(crack_info)} 条\n")
            f.write(f"长度≥25cm的裂隙: {long_cracks_count} 条\n")
            f.write(f"裂隙总长度: {total_crack_length_cm:.1f} cm ({total_crack_length_m:.2f} m)\n")
            f.write(f"裂隙占比: {crack_ratio:.2f}%\n\n")

            f.write("--- 岩石质量指标 ---\n")
            f.write(f"指标1 (长度≥25cm的裂隙条数/面积): {indicator1:.4f} 条/m²\n")
            f.write(f"指标2 (平均节理间距): {joint_spacing_avg:.2f} cm\n")
            f.write(f"指标3 (裂隙总长度/面积): {indicator3:.4f} m/m²\n\n")

            f.write("--- 详细裂隙信息 ---\n")
            for i, crack in enumerate(crack_info[:20], 1):  # 只保存前20条
                f.write(f"{i}. 长度: {crack['length_cm']:.2f} cm ({crack['length_pixels']} 像素)\n")
            if len(crack_info) > 20:
                f.write(f"... 还有 {len(crack_info) - 20} 条裂隙\n")

        print(f"  - 指标报告: {os.path.basename(report_path)}")

    # 打印总结
    w, h = original_img.size
    print("\n" + "=" * 80)
    print("检测完成！")
    print("=" * 80)
    print(f"裂隙占比: {crack_ratio:.2f}%")
    print(f"推理时间: {inference_time:.2f} 秒")
    print(f"图像尺寸: {w}x{h}")
    if args.calculate_indicators and indicator1 is not None:
        print(f"\n岩石质量指标:")
        print(f"  指标1: {indicator1:.4f} 条/m²")
        print(f"  指标2: {joint_spacing_avg:.2f} cm")
        print(f"  指标3: {indicator3:.4f} m/m²")
    print("=" * 80)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='使用移动端模型进行裂隙检测（支持大图切片）')

    # 基本参数
    parser.add_argument('--model', default='savss_mobile.ptl', help='模型文件路径')
    parser.add_argument('--image', default='cut_picture/14.jpg', help='输入图像路径')
    parser.add_argument('--output_dir', default='mobile_predict_results', help='输出目录')

    # 滑动窗口参数
    parser.add_argument('--window_size', type=int, default=512, help='窗口大小（默认 512）')
    parser.add_argument('--stride', type=int, default=512, help='滑动步长（默认 512，无重叠最快）')
    parser.add_argument('--skip_empty', action='store_true', default=True, help='跳过空白窗口')
    parser.add_argument('--valid_threshold', type=float, default=0.1, help='有效内容阈值（默认 0.1）')
    parser.add_argument('--batch_size', type=int, default=1, help='批处理大小（默认 1，稳定性优先）')
    parser.add_argument('--use_cache', action='store_true', default=False, help='使用缓存加速（默认启用）')
    parser.add_argument('--cache_dir', type=str, default='mobile_cache', help='缓存目录（默认 mobile_cache）')

    # 快捷模式
    parser.add_argument('--fast', action='store_true', help='快速模式（stride=512, 无重叠）')
    parser.add_argument('--balanced', action='store_true', help='平衡模式（stride=384, 25%%重叠）')
    parser.add_argument('--accurate', action='store_true', help='精确模式（stride=256, 50%%重叠）')
    parser.add_argument('--grid', action='store_true', help='网格模式（resize到1024x1024，4次扫描）')
    parser.add_argument('--ultra_fast', action='store_true', help='超快模式（resize到512x512，1次扫描）')
    parser.add_argument('--small', action='store_true', help='小窗口模式（320x320窗口，计算量减少2.5倍）')
    parser.add_argument('--medium', action='store_true', help='中窗口模式（resize到640x640，4次扫描，计算量减少4倍）')

    # 网格模式参数（高级用法）
    parser.add_argument('--use_grid', action='store_true', help='使用网格模式（需配合--grid_size和--window_size）')
    parser.add_argument('--grid_size', type=int, help='网格总尺寸（如640）')

    # 后处理参数
    parser.add_argument('--threshold', type=float, default=0.4, help='二值化阈值（默认 0.5）')
    parser.add_argument('--alpha', type=float, default=0.4, help='叠加透明度（默认 0.4）')

    # 尺子检测参数
    parser.add_argument('--ruler_length', type=float, default=50.0, help='尺子实际长度(cm)，默认50cm')
    parser.add_argument('--ruler_color', type=str, default='yellow', choices=['yellow', 'red', 'both'],
                        help='尺子颜色（默认yellow）')

    # 指标计算参数
    parser.add_argument('--calculate_indicators', action='store_true', help='是否计算三个指标')
    parser.add_argument('--min_crack_length', type=float, default=1.0, help='最小裂缝长度(cm)，默认1.0')
    parser.add_argument('--detect_valid_region', action='store_true', help='是否检测有效区域（用于不规则图片）')
    parser.add_argument('--valid_region_threshold', type=int, default=10, help='有效区域阈值，默认10')

    # 设备参数
    parser.add_argument('--device', default='cpu', help='设备（cpu 或 cuda）')

    # 图像增强参数
    parser.add_argument('--enhance', action='store_true', help='启用图像增强（Retinex增强），增强后的图片会保存到输出目录')

    # 调试参数
    parser.add_argument('--debug', action='store_true', help='启用调试模式（显示详细信息）')

    args = parser.parse_args()

    # 如果启用调试模式，设置更详细的日志
    if args.debug:
        print("=" * 80)
        print("调试模式已启用")
        print("=" * 80)
        import psutil
        process = psutil.Process()
        print(f"初始内存使用: {process.memory_info().rss / 1024 / 1024:.1f} MB")
        print(f"可用内存: {psutil.virtual_memory().available / 1024 / 1024:.1f} MB")
        print("=" * 80)

    main(args)

