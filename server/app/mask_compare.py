from __future__ import annotations

import json
from collections import deque
from typing import Any


DEFAULT_MASK_TOLERANCE = {
    "minMaskIou": 0.85,
    "maxPixelErrorRate": 0.15,
    "maxCrackRatioDelta": 1.5,
}


def parse_mask_json(value: str) -> list[list[bool]]:
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError as exc:
        raise ValueError("appMask must be valid JSON") from exc
    if isinstance(decoded, dict):
        rle_payload = decoded.get("binaryMaskRle") or decoded.get("maskRle")
        if isinstance(rle_payload, dict):
            return _decode_rle_mask(rle_payload)
        decoded = decoded.get("binaryMask") or decoded.get("mask")
    if not isinstance(decoded, list):
        raise ValueError("appMask must be a 2D boolean array")
    mask: list[list[bool]] = []
    for row in decoded:
        if not isinstance(row, list):
            raise ValueError("appMask must be a 2D boolean array")
        mask.append([_to_bool(pixel) for pixel in row])
    return mask


def compare_masks(
    app_mask: list[list[bool]],
    server_mask: list[list[bool]],
    tolerance: dict[str, float] | None = None,
) -> dict[str, Any]:
    effective_tolerance = {**DEFAULT_MASK_TOLERANCE, **(tolerance or {})}
    app_width, app_height = _dimensions(app_mask)
    server_width, server_height = _dimensions(server_mask)
    width = max(app_width, server_width)
    height = max(app_height, server_height)
    total = max(1, width * height)
    intersection = 0
    union = 0
    mismatch = 0
    for y in range(height):
        for x in range(width):
            app_value = _mask_value(app_mask, x, y)
            server_value = _mask_value(server_mask, x, y)
            if app_value and server_value:
                intersection += 1
            if app_value or server_value:
                union += 1
            if app_value != server_value:
                mismatch += 1

    mask_iou = 1.0 if union == 0 else intersection / union
    pixel_error_rate = mismatch / total
    app_crack_ratio = _crack_ratio(app_mask)
    server_crack_ratio = _crack_ratio(server_mask)
    crack_ratio_delta = abs(app_crack_ratio - server_crack_ratio)
    app_components = connected_components(app_mask)
    server_components = connected_components(server_mask)
    failed_reasons: list[str] = []
    if mask_iou < effective_tolerance["minMaskIou"]:
        failed_reasons.append("mask_iou")
    if pixel_error_rate > effective_tolerance["maxPixelErrorRate"]:
        failed_reasons.append("pixel_error_rate")
    if crack_ratio_delta > effective_tolerance["maxCrackRatioDelta"]:
        failed_reasons.append("crack_ratio_delta")

    return {
        "passed": not failed_reasons,
        "failedReasons": failed_reasons,
        "tolerance": effective_tolerance,
        "metrics": {
            "maskIou": mask_iou,
            "pixelErrorRate": pixel_error_rate,
            "crackRatioDelta": crack_ratio_delta,
            "appCrackRatio": app_crack_ratio,
            "serverCrackRatio": server_crack_ratio,
            "appConnectedComponents": app_components,
            "serverConnectedComponents": server_components,
            "connectedComponentDelta": abs(app_components - server_components),
        },
        "dimensions": {
            "app": {"width": app_width, "height": app_height},
            "server": {"width": server_width, "height": server_height},
            "comparison": {"width": width, "height": height},
        },
    }


def connected_components(mask: list[list[bool]]) -> int:
    width, height = _dimensions(mask)
    if width == 0 or height == 0:
        return 0
    visited = [[False for _ in range(width)] for _ in range(height)]
    count = 0
    for y in range(height):
        for x in range(width):
            if not _mask_value(mask, x, y) or visited[y][x]:
                continue
            count += 1
            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited[y][x] = True
            while queue:
                current_x, current_y = queue.popleft()
                for next_x, next_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if (
                        0 <= next_x < width
                        and 0 <= next_y < height
                        and _mask_value(mask, next_x, next_y)
                        and not visited[next_y][next_x]
                    ):
                        visited[next_y][next_x] = True
                        queue.append((next_x, next_y))
    return count


def _dimensions(mask: list[list[bool]]) -> tuple[int, int]:
    return max((len(row) for row in mask), default=0), len(mask)


def _mask_value(mask: list[list[bool]], x: int, y: int) -> bool:
    return y < len(mask) and x < len(mask[y]) and mask[y][x]


def _crack_ratio(mask: list[list[bool]]) -> float:
    total = sum(len(row) for row in mask)
    if total == 0:
        return 0.0
    crack = sum(1 for row in mask for pixel in row if pixel)
    return crack / total * 100


def _to_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        return value.lower() in {"1", "true", "yes", "y"}
    return bool(value)


def _decode_rle_mask(payload: dict[str, Any]) -> list[list[bool]]:
    width = int(payload.get("width") or 0)
    height = int(payload.get("height") or 0)
    runs = payload.get("runs")
    if width <= 0 or height <= 0 or not isinstance(runs, list):
        raise ValueError("appMask RLE must include width, height, and runs")
    value = _to_bool(payload.get("firstValue", False))
    flat: list[bool] = []
    for raw_run in runs:
        run = int(raw_run)
        if run < 0:
            raise ValueError("appMask RLE run lengths must be non-negative")
        flat.extend([value] * run)
        value = not value
    expected = width * height
    if len(flat) < expected:
        flat.extend([False] * (expected - len(flat)))
    if len(flat) > expected:
        flat = flat[:expected]
    return [
        [flat[y * width + x] for x in range(width)]
        for y in range(height)
    ]
