#!/usr/bin/env python3
"""使用ONNX模型预测裂缝（滑动窗口 + 后处理）"""
import numpy as np
import cv2
import onnxruntime as ort
from PIL import Image
import matplotlib.pyplot as plt
import os
import argparse
from datetime import datetime
from skimage import morphology, measure
import math

MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

# ==================== 后处理函数 ====================

def detect_ruler(image, ruler_length_cm=50, ruler_color='yellow'):
    """检测图片中的尺子，并计算像素到厘米的比例"""
    if isinstance(image, Image.Image):
        img_np = np.array(image)
    else:
        img_np = image.copy()

    hsv = cv2.cvtColor(img_np, cv2.COLOR_RGB2HSV)

    if ruler_color == 'yellow':
        lower, upper = np.array([20, 100, 100]), np.array([35, 255, 255])
        mask = cv2.inRange(hsv, lower, upper)
    elif ruler_color == 'red':
        lower1, upper1 = np.array([0, 100, 100]), np.array([10, 255, 255])
        lower2, upper2 = np.array([160, 100, 100]), np.array([180, 255, 255])
        mask = cv2.inRange(hsv, lower1, upper1) | cv2.inRange(hsv, lower2, upper2)
    else:
        lower_y, upper_y = np.array([20, 100, 100]), np.array([35, 255, 255])
        lower_r1, upper_r1 = np.array([0, 100, 100]), np.array([10, 255, 255])
        lower_r2, upper_r2 = np.array([160, 100, 100]), np.array([180, 255, 255])
        mask = cv2.inRange(hsv, lower_y, upper_y) | cv2.inRange(hsv, lower_r1, upper_r1) | cv2.inRange(hsv, lower_r2, upper_r2)

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None, None, None

    largest = max(contours, key=cv2.contourArea)
    x, y, w, h = cv2.boundingRect(largest)

    ruler_mask = np.zeros(mask.shape, dtype=np.uint8)
    cv2.drawContours(ruler_mask, [largest], -1, 255, -1)

    ruler_length_pixels = max(w, h)
    pixel_to_cm = ruler_length_cm / ruler_length_pixels

    print(f"✓ 检测到尺子: {w}x{h}像素, 1像素={pixel_to_cm:.4f}cm")
    return pixel_to_cm, ruler_mask, (x, y, w, h)

def remove_ruler_from_mask(crack_mask, ruler_mask):
    """从裂缝mask中移除尺子区域"""
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (10, 10))
    ruler_mask_expanded = cv2.dilate(ruler_mask, kernel, iterations=2)
    return cv2.bitwise_and(crack_mask, cv2.bitwise_not(ruler_mask_expanded))

def extract_crack_skeletons(binary_mask):
    """提取裂缝的骨架"""
    binary = (binary_mask > 0).astype(np.uint8)
    skeleton = morphology.skeletonize(binary)
    return skeleton.astype(np.uint8)

def measure_crack_lengths(skeleton, pixel_to_cm):
    """测量每条裂缝的长度（不过滤）"""
    labeled_skeleton = measure.label(skeleton, connectivity=2)
    crack_info = []
    for region in measure.regionprops(labeled_skeleton):
        length_pixels = region.area
        length_cm = length_pixels * pixel_to_cm
        minr, minc, maxr, maxc = region.bbox
        crack_info.append({
            'length_pixels': length_pixels,
            'length_cm': length_cm,
            'bbox': (minc, minr, maxc - minc, maxr - minr),
            'centroid': region.centroid
        })
    crack_info.sort(key=lambda x: x['length_cm'], reverse=True)
    return crack_info

def calculate_line_crack_intersections(line_start, line_end, skeleton):
    """计算测线与裂缝骨架的交点"""
    x1, y1 = line_start
    x2, y2 = line_end
    line_length = np.sqrt((x2 - x1)**2 + (y2 - y1)**2)
    num_samples = int(line_length) + 1

    intersections = []
    prev_on_crack = False

    for i in range(num_samples):
        t = i / max(num_samples - 1, 1)
        x, y = int(x1 + t * (x2 - x1)), int(y1 + t * (y2 - y1))
        if 0 <= y < skeleton.shape[0] and 0 <= x < skeleton.shape[1]:
            on_crack = skeleton[y, x] > 0
            if on_crack and not prev_on_crack:
                distance = np.sqrt((x - x1)**2 + (y - y1)**2)
                intersections.append((x, y, distance))
            prev_on_crack = on_crack
    return intersections

def calculate_joint_spacing_four_lines(image_shape, skeleton, pixel_to_cm, margin_ratio=0.0):
    """在图像上绘制4条测线并计算节理间距"""
    height, width = image_shape
    margin_x, margin_y = int(width * margin_ratio), int(height * margin_ratio)

    test_lines = []
    h_positions = [height // 3, 2 * height // 3]
    v_positions = [width // 3, 2 * width // 3]

    for y in h_positions:
        test_lines.append(((margin_x, y), (width - margin_x - 1, y)))
    for x in v_positions:
        test_lines.append(((x, margin_y), (x, height - margin_y - 1)))

    results = []
    line_names = ['横线1', '横线2', '竖线1', '竖线2']

    for i, (start, end) in enumerate(test_lines):
        intersections_px = calculate_line_crack_intersections(start, end, skeleton)
        intersections = [(x, y, dist * pixel_to_cm) for x, y, dist in intersections_px]

        if len(intersections) >= 2:
            first_dist, last_dist = intersections[0][2], intersections[-1][2]
            effective_length_cm = last_dist - first_dist
            joint_spacing_cm = effective_length_cm / len(intersections) if len(intersections) > 0 else 0
        else:
            effective_length_cm, joint_spacing_cm = 0, 0

        results.append({
            'line_name': line_names[i],
            'start': start, 'end': end,
            'effective_length_cm': effective_length_cm,
            'joint_spacing_cm': joint_spacing_cm,
            'num_intersections': len(intersections),
            'intersections': intersections
        })

    joint_spacing_avg = np.mean([r['joint_spacing_cm'] for r in results])
    return joint_spacing_avg, results, test_lines



def calculate_three_indicators(image_shape, crack_info, skeleton, pixel_to_cm):
    """计算三大岩石质量指标"""
    height, width = image_shape
    image_area_cm2 = (width * pixel_to_cm) * (height * pixel_to_cm)
    image_area_m2 = image_area_cm2 / 10000

    # 指标1: 长度≥25cm的裂隙条数 / 图像面积(m²)
    long_cracks_count = sum(1 for c in crack_info if c['length_cm'] >= 25)
    indicator1 = long_cracks_count / image_area_m2 if image_area_m2 > 0 else 0

    # 指标2: 平均节理间距
    joint_spacing_avg, rqd_results, test_lines = calculate_joint_spacing_four_lines(
        image_shape, skeleton, pixel_to_cm
    )
    indicator2 = joint_spacing_avg

    # 指标3: 裂隙总长度(m) / 图像面积(m²)
    total_crack_length_m = sum(c['length_cm'] for c in crack_info) / 100
    indicator3 = total_crack_length_m / image_area_m2 if image_area_m2 > 0 else 0

    return indicator1, indicator2, indicator3, rqd_results, test_lines

def visualize_joint_spacing(skeleton, results, test_lines, pixel_to_cm):
    """在骨架图上可视化节理间距计算过程（网格图）"""
    if len(skeleton.shape) == 2:
        vis_img = cv2.cvtColor((skeleton * 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    else:
        vis_img = skeleton.copy()

    line_colors = [(0, 255, 255), (0, 165, 255), (255, 0, 255), (255, 255, 0)]
    line_labels = ['H-Line1', 'H-Line2', 'V-Line1', 'V-Line2']

    for i, (result, (line_start, line_end)) in enumerate(zip(results, test_lines)):
        color = line_colors[i]
        intersections = result['intersections']
        cv2.line(vis_img, line_start, line_end, color, thickness=3)
        for j, (x, y, dist) in enumerate(intersections):
            cv2.circle(vis_img, (int(x), int(y)), 6, (0, 0, 255), -1)
            cv2.circle(vis_img, (int(x), int(y)), 8, (255, 255, 255), 2)
            cv2.putText(vis_img, f"{chr(65+j)}", (int(x)+12, int(y)-12),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
        mid_x = (line_start[0] + line_end[0]) // 2
        mid_y = (line_start[1] + line_end[1]) // 2
        spacing_label = f"{line_labels[i]}: {result['joint_spacing_cm']:.1f}cm"
        if i < 2:
            label_pos = (mid_x - 70, mid_y - 40 if i == 0 else mid_y + 50)
        else:
            label_pos = (mid_x - 90 if i == 2 else mid_x + 20, mid_y)
        (text_w, text_h), _ = cv2.getTextSize(spacing_label, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
        cv2.rectangle(vis_img, (label_pos[0]-5, label_pos[1]-text_h-5),
                     (label_pos[0]+text_w+5, label_pos[1]+5), (0, 0, 0), -1)
        cv2.putText(vis_img, spacing_label, label_pos, cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)

    joint_spacing_avg = np.mean([r['joint_spacing_cm'] for r in results])
    panel_x, panel_y = vis_img.shape[1] - 320, 30
    overlay = vis_img.copy()
    cv2.rectangle(overlay, (panel_x, panel_y), (panel_x+300, panel_y+150), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.7, vis_img, 0.3, 0, vis_img)
    cv2.rectangle(vis_img, (panel_x, panel_y), (panel_x+300, panel_y+150), (255, 255, 255), 2)
    cv2.putText(vis_img, "Joint Spacing Analysis", (panel_x+10, panel_y+25),
               cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
    y_offset = 55
    for i, result in enumerate(results):
        cv2.putText(vis_img, f"{line_labels[i]}: {result['joint_spacing_cm']:.1f}cm",
                   (panel_x+10, panel_y+y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.45, line_colors[i], 1)
        y_offset += 22
    cv2.putText(vis_img, f"Avg Spacing: {joint_spacing_avg:.1f}cm", (panel_x+10, panel_y+y_offset+5),
               cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
    return vis_img

def sliding_window_predict(image_np, ort_session, window_size=256, output_scale=2, max_windows=20):
    """滑动窗口预测（仅ONNX）

    缩放逻辑：根据max_windows计算图像应缩放到的目标尺寸
    - 使用25%重叠减少边界问题
    - 自动缩放大图以控制窗口数量
    """
    orig_h, orig_w = image_np.shape[:2]

    # 使用25%重叠
    overlap = 0.25
    stride = int(window_size * (1 - overlap))  # stride = 192

    # 根据max_windows计算目标尺寸
    # 总窗口数 = n_h * n_w，其中 n = (size - window_size) / stride + 1
    # 简化：假设图像接近正方形，每边窗口数 = sqrt(max_windows)
    # 每边尺寸 = (windows_per_side - 1) * stride + window_size
    windows_per_side = int(math.sqrt(max_windows))
    target_side = (windows_per_side - 1) * stride + window_size

    # 计算缩放比例（基于较长边）
    max_orig = max(orig_h, orig_w)
    scale = min(1.0, target_side / max_orig)

    new_h = max(window_size, int(orig_h * scale))
    new_w = max(window_size, int(orig_w * scale))

    # 缩放图像
    if scale < 1.0:
        image_resized = cv2.resize(image_np, (new_w, new_h), interpolation=cv2.INTER_AREA)
        print(f"  缩放: {orig_w}x{orig_h} -> {new_w}x{new_h} (scale={scale:.3f})")
    else:
        image_resized = image_np.copy()

    h, w = image_resized.shape[:2]

    # 计算padding使尺寸能被stride整除
    pad_h = (stride - (h - window_size) % stride) % stride if h > window_size else window_size - h
    pad_w = (stride - (w - window_size) % stride) % stride if w > window_size else window_size - w

    if pad_h > 0 or pad_w > 0:
        image_resized = np.pad(image_resized, ((0, pad_h), (0, pad_w), (0, 0)), mode='reflect')

    h_pad, w_pad = image_resized.shape[:2]

    # 计算实际窗口数
    n_h = max(1, (h_pad - window_size) // stride + 1)
    n_w = max(1, (w_pad - window_size) // stride + 1)
    total = n_h * n_w

    print(f"  处理尺寸: {h}x{w} -> padding后: {h_pad}x{w_pad}")
    print(f"  窗口: {window_size}, 步长: {stride}, 重叠: {overlap*100:.0f}%, 总窗口数: {total} ({n_h}x{n_w})")

    # 输出尺寸
    out_h, out_w = h_pad * output_scale, w_pad * output_scale
    out_window = window_size * output_scale

    pred = np.zeros((out_h, out_w), dtype=np.float32)
    count_map = np.zeros((out_h, out_w), dtype=np.float32)

    count = 0
    for i in range(n_h):
        for j in range(n_w):
            y = min(i * stride, h_pad - window_size)
            x = min(j * stride, w_pad - window_size)

            window = image_resized[y:y+window_size, x:x+window_size]
            window_norm = (window.astype(np.float32) / 255.0 - MEAN) / STD

            # ONNX推理
            onnx_input = window_norm.transpose(2, 0, 1)[np.newaxis, ...].astype(np.float32)
            onnx_out = ort_session.run(None, {'input': onnx_input})[0]
            out_window_pred = 1 / (1 + np.exp(-onnx_out[0, 0]))  # sigmoid

            # 检查NaN
            if np.isnan(out_window_pred).any():
                print(f"  窗口{count} ({y},{x}): 检测到NaN，跳过")
                out_window_pred = np.nan_to_num(out_window_pred, nan=0.0)

            oy, ox = y * output_scale, x * output_scale
            pred[oy:oy+out_window, ox:ox+out_window] += out_window_pred
            count_map[oy:oy+out_window, ox:ox+out_window] += 1

            count += 1
            if count % 10 == 0:
                print(f"  进度: {count}/{total}")

    # 平均
    count_map = np.maximum(count_map, 1)
    pred = pred / count_map

    # 裁剪回缩放后尺寸
    pred = pred[:h*output_scale, :w*output_scale]

    # 放大回原始尺寸
    pred = cv2.resize(pred, (orig_w, orig_h), interpolation=cv2.INTER_LINEAR)

    return pred



def main():
    parser = argparse.ArgumentParser(description='ONNX模型裂缝预测')
    parser.add_argument('--image', type=str, default='../test/data/cut_picture/14.jpg')
    parser.add_argument('--onnx', type=str, default='savss_256.onnx')
    parser.add_argument('--output_dir', type=str, default='./predict_results', help='输出目录')
    parser.add_argument('--window_size', type=int, default=256, help='滑动窗口大小')
    parser.add_argument('--max_windows', type=int, default=20, help='最大滑动窗口数量')
    parser.add_argument('--output_scale', type=int, default=2, help='输出相对于输入的倍数')
    parser.add_argument('--threshold', type=float, default=0.3, help='二值化阈值')
    parser.add_argument('--ruler_length', type=float, default=50, help='尺子长度(cm)')
    parser.add_argument('--ruler_color', type=str, default='yellow', choices=['yellow', 'red', 'both'])
    parser.add_argument('--calculate_indicators', action='store_true', help='计算三大岩石质量指标')
    args = parser.parse_args()

    # 创建输出目录
    image_name = os.path.splitext(os.path.basename(args.image))[0]
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    output_dir = os.path.join(args.output_dir, f"{timestamp}_{image_name}")
    os.makedirs(output_dir, exist_ok=True)

    print("=" * 80)
    print("ONNX 裂缝预测")
    print("=" * 80)
    print(f"图像: {args.image}")
    print(f"ONNX: {args.onnx}")
    print(f"输出目录: {output_dir}")
    print("=" * 80)

    # 加载图像
    img = Image.open(args.image).convert('RGB')
    img_np = np.array(img)
    print(f"原始尺寸: {img.size}")

    # 检测尺子
    print("\n[1] 检测尺子...")
    pixel_to_cm, ruler_mask, ruler_bbox = detect_ruler(img, args.ruler_length, args.ruler_color)
    if pixel_to_cm is None:
        print("警告: 未检测到尺子，使用默认比例 1像素=0.01cm")
        pixel_to_cm = 0.01
        ruler_mask = np.zeros((img_np.shape[0], img_np.shape[1]), dtype=np.uint8)

    # 加载ONNX模型
    print("\n[2] 加载ONNX模型...")
    ort_session = ort.InferenceSession(args.onnx, providers=['CPUExecutionProvider'])

    # 滑动窗口推理
    print("\n[3] 滑动窗口推理...")
    pred = sliding_window_predict(
        img_np, ort_session,
        window_size=args.window_size,
        output_scale=args.output_scale,
        max_windows=args.max_windows
    )
    print(f"输出: shape={pred.shape}, min={pred.min():.4f}, max={pred.max():.4f}")

    # 后处理
    print("\n[4] 后处理...")
    binary = ((pred > args.threshold) * 255).astype(np.uint8)
    clean = remove_ruler_from_mask(binary, ruler_mask)
    skeleton = extract_crack_skeletons(clean)
    cracks = measure_crack_lengths(skeleton, pixel_to_cm)
    print(f"检测到 {len(cracks)} 条裂缝")

    # 计算三大指标
    if args.calculate_indicators:
        print("\n[5] 计算岩石质量指标...")
        image_shape = (img_np.shape[0], img_np.shape[1])
        ind1, ind2, ind3, rqd_results, test_lines = calculate_three_indicators(
            image_shape, cracks, skeleton, pixel_to_cm
        )
        print("\n" + "=" * 60)
        print("三大岩石质量指标:")
        print("=" * 60)
        print(f"指标1 (条/m²): {ind1:.4f}")
        print(f"指标2 - 节理间距(cm): {ind2:.2f}")
        print(f"指标3 (m/m²): {ind3:.4f}")
        print("=" * 60)

    # ==================== 保存结果 ====================
    print("\n[6] 保存结果...")

    # 1. 保存原图
    img.save(os.path.join(output_dir, f"{image_name}_original.jpg"))

    # 2. 保存尺子检测结果
    ruler_vis = img_np.copy()
    if ruler_bbox is not None:
        x, y, w, h = ruler_bbox
        cv2.rectangle(ruler_vis, (x, y), (x+w, y+h), (0, 255, 0), 3)
        cv2.putText(ruler_vis, f"Ruler: {args.ruler_length}cm", (x, y-10),
                   cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 0), 2)
    cv2.imwrite(os.path.join(output_dir, f"{image_name}_ruler_detection.jpg"),
                cv2.cvtColor(ruler_vis, cv2.COLOR_RGB2BGR))

    # 3. 保存预测结果
    cv2.imwrite(os.path.join(output_dir, f"{image_name}_prediction.png"), binary)
    cv2.imwrite(os.path.join(output_dir, f"{image_name}_clean.png"), clean)
    cv2.imwrite(os.path.join(output_dir, f"{image_name}_skeleton.png"), skeleton * 255)

    # 4. 保存可视化叠加图
    overlay = img_np.copy()
    overlay[clean > 0] = [255, 0, 0]
    cv2.imwrite(os.path.join(output_dir, f"{image_name}_overlay.jpg"),
                cv2.cvtColor(overlay, cv2.COLOR_RGB2BGR))

    # 5. 保存网格图（如果计算了指标）
    if args.calculate_indicators:
        joint_vis = visualize_joint_spacing(skeleton, rqd_results, test_lines, pixel_to_cm)
        cv2.imwrite(os.path.join(output_dir, f"{image_name}_joint_spacing.jpg"), joint_vis)

    # 6. 保存CSV
    csv_path = os.path.join(output_dir, f"{image_name}_cracks.csv")
    with open(csv_path, 'w', encoding='utf-8') as f:
        f.write("ID,长度(cm),长度(像素),中心X,中心Y,边界框X,边界框Y,边界框宽,边界框高\n")
        for i, crack in enumerate(cracks):
            cx, cy = crack['centroid']
            bx, by, bw, bh = crack['bbox']
            f.write(f"{i+1},{crack['length_cm']:.2f},{crack['length_pixels']},"
                   f"{cy:.1f},{cx:.1f},{bx},{by},{bw},{bh}\n")

    # 7. 保存报告
    report_path = os.path.join(output_dir, f"{image_name}_report.txt")
    with open(report_path, 'w', encoding='utf-8') as f:
        f.write("=" * 60 + "\n")
        f.write("ONNX 裂缝预测报告\n")
        f.write("=" * 60 + "\n\n")
        f.write(f"图像: {args.image}\n")
        f.write(f"尺寸: {img.size[0]} x {img.size[1]}\n")
        f.write(f"尺子长度: {args.ruler_length} cm\n")
        f.write(f"像素比例: 1像素 = {pixel_to_cm:.4f} cm\n\n")
        f.write(f"检测到裂缝: {len(cracks)} 条\n")
        total_length = sum(c['length_cm'] for c in cracks)
        f.write(f"裂缝总长度: {total_length:.2f} cm\n\n")

        if args.calculate_indicators:
            f.write("=" * 60 + "\n")
            f.write("三大岩石质量指标:\n")
            f.write("=" * 60 + "\n")
            f.write(f"指标1 (条/m²): {ind1:.4f}\n")
            f.write(f"指标2 - 节理间距(cm): {ind2:.2f}\n")
            f.write(f"指标3 (m/m²): {ind3:.4f}\n\n")
            f.write("各测线节理间距:\n")
            for r in rqd_results:
                f.write(f"  {r['line_name']}: {r['joint_spacing_cm']:.2f}cm (交点数: {r['num_intersections']})\n")

    # 打印输出文件列表
    print("\n" + "=" * 60)
    print("输出文件:")
    print("=" * 60)
    print(f"✓ 原图: {image_name}_original.jpg")
    print(f"✓ 尺子检测: {image_name}_ruler_detection.jpg")
    print(f"✓ 预测结果: {image_name}_prediction.png")
    print(f"✓ 骨架图: {image_name}_skeleton.png")
    print(f"✓ 叠加图: {image_name}_overlay.jpg")
    if args.calculate_indicators:
        print(f"✓ 网格图: {image_name}_joint_spacing.jpg")
    print(f"✓ 裂缝CSV: {image_name}_cracks.csv")
    print(f"✓ 报告: {image_name}_report.txt")
    print(f"\n✓ 所有结果已保存到: {output_dir}")

if __name__ == '__main__':
    main()
