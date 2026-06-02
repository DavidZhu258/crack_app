from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence

import onnx
from onnx import AttributeProto, helper


@dataclass(frozen=True)
class ResizeRewriteConfig:
    target_mode: str = "pytorch_half_pixel"
    source_modes: tuple[str, ...] = ("half_pixel",)
    run_checker: bool = True
    fail_if_no_changes: bool = False


@dataclass(frozen=True)
class ResizeNodeInfo:
    index: int
    name: str
    inputs: tuple[str, ...]
    outputs: tuple[str, ...]
    mode: str | None
    coordinate_transformation_mode: str | None
    nearest_mode: str | None
    cubic_coeff_a: float | None


@dataclass(frozen=True)
class ResizeRewriteChange:
    node_index: int
    node_name: str
    op_mode: str | None
    old_mode: str
    new_mode: str


@dataclass(frozen=True)
class ResizeRewriteReport:
    total_resize_nodes: int
    changed_count: int
    remaining_source_mode_count: int
    target_mode: str
    source_modes: tuple[str, ...]
    changes: tuple[ResizeRewriteChange, ...]

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def inspect_resize_nodes(model: onnx.ModelProto) -> list[ResizeNodeInfo]:
    resize_nodes: list[ResizeNodeInfo] = []
    for index, node in enumerate(model.graph.node):
        if node.op_type != "Resize":
            continue
        resize_nodes.append(
            ResizeNodeInfo(
                index=index,
                name=node.name or f"Resize_{index}",
                inputs=tuple(node.input),
                outputs=tuple(node.output),
                mode=_string_attr(node, "mode"),
                coordinate_transformation_mode=_string_attr(
                    node,
                    "coordinate_transformation_mode",
                ),
                nearest_mode=_string_attr(node, "nearest_mode"),
                cubic_coeff_a=_float_attr(node, "cubic_coeff_a"),
            ),
        )
    return resize_nodes


def rewrite_resize_coordinate_transformation(
    model: onnx.ModelProto,
    config: ResizeRewriteConfig | None = None,
) -> ResizeRewriteReport:
    config = config or ResizeRewriteConfig()
    source_modes = set(config.source_modes)
    changes: list[ResizeRewriteChange] = []

    for index, node in enumerate(model.graph.node):
        if node.op_type != "Resize":
            continue
        old_mode = _string_attr(node, "coordinate_transformation_mode")
        if old_mode not in source_modes:
            continue
        _set_string_attr(node, "coordinate_transformation_mode", config.target_mode)
        changes.append(
            ResizeRewriteChange(
                node_index=index,
                node_name=node.name or f"Resize_{index}",
                op_mode=_string_attr(node, "mode"),
                old_mode=old_mode,
                new_mode=config.target_mode,
            ),
        )

    remaining_source_mode_count = sum(
        1
        for node in inspect_resize_nodes(model)
        if node.coordinate_transformation_mode in source_modes
    )
    if config.fail_if_no_changes and not changes:
        raise RuntimeError(
            "No Resize nodes matched source modes: "
            + ", ".join(config.source_modes),
        )
    return ResizeRewriteReport(
        total_resize_nodes=len(inspect_resize_nodes(model)),
        changed_count=len(changes),
        remaining_source_mode_count=remaining_source_mode_count,
        target_mode=config.target_mode,
        source_modes=config.source_modes,
        changes=tuple(changes),
    )


def rewrite_model_file(
    input_path: str | Path,
    output_path: str | Path,
    config: ResizeRewriteConfig | None = None,
) -> ResizeRewriteReport:
    config = config or ResizeRewriteConfig()
    input_path = Path(input_path)
    output_path = Path(output_path)
    model = onnx.load(input_path)
    report = rewrite_resize_coordinate_transformation(model, config)
    if config.run_checker:
        onnx.checker.check_model(model)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    onnx.save(model, output_path)
    return report


def _string_attr(node: onnx.NodeProto, name: str) -> str | None:
    for attr in node.attribute:
        if attr.name != name:
            continue
        value = helper.get_attribute_value(attr)
        if isinstance(value, bytes):
            return value.decode("utf-8")
        return str(value)
    return None


def _float_attr(node: onnx.NodeProto, name: str) -> float | None:
    for attr in node.attribute:
        if attr.name != name:
            continue
        value = helper.get_attribute_value(attr)
        return float(value)
    return None


def _set_string_attr(node: onnx.NodeProto, name: str, value: str) -> None:
    for attr in node.attribute:
        if attr.name != name:
            continue
        attr.type = AttributeProto.STRING
        attr.s = value.encode("utf-8")
        return
    node.attribute.append(helper.make_attribute(name, value))


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rewrite ONNX Resize coordinate_transformation_mode values for "
            "Ascend ATC compatibility."
        ),
    )
    parser.add_argument("--input", required=True, help="Source ONNX path.")
    parser.add_argument("--output", help="Destination ONNX path.")
    parser.add_argument(
        "--target-mode",
        default="pytorch_half_pixel",
        help=(
            "Replacement coordinate_transformation_mode. "
            "Use pytorch_half_pixel first for parity, asymmetric as fallback."
        ),
    )
    parser.add_argument(
        "--source-mode",
        action="append",
        default=None,
        help="Source coordinate mode to replace. Defaults to half_pixel.",
    )
    parser.add_argument(
        "--inspect-only",
        action="store_true",
        help="Print Resize inventory without saving a rewritten model.",
    )
    parser.add_argument(
        "--skip-checker",
        action="store_true",
        help="Skip onnx.checker.check_model before saving.",
    )
    parser.add_argument(
        "--fail-if-no-changes",
        action="store_true",
        help="Exit with an error if no matching Resize nodes are found.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> None:
    args = _parse_args(argv)
    input_path = Path(args.input)

    if args.inspect_only:
        model = onnx.load(input_path)
        resize_nodes = [asdict(node) for node in inspect_resize_nodes(model)]
        print(json.dumps({"resizeNodes": resize_nodes}, indent=2))
        return

    if not args.output:
        raise SystemExit("--output is required unless --inspect-only is set")

    config = ResizeRewriteConfig(
        target_mode=args.target_mode,
        source_modes=tuple(args.source_mode or ["half_pixel"]),
        run_checker=not args.skip_checker,
        fail_if_no_changes=args.fail_if_no_changes,
    )
    report = rewrite_model_file(input_path, args.output, config)
    print(json.dumps(report.to_dict(), indent=2))


if __name__ == "__main__":
    main()
