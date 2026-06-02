from __future__ import annotations

import onnx
from onnx import TensorProto, helper

from server.scripts.ascend_onnx_rewrite import (
    ResizeRewriteConfig,
    inspect_resize_nodes,
    rewrite_model_file,
    rewrite_resize_coordinate_transformation,
)


def test_inspect_resize_nodes_reports_coordinate_modes() -> None:
    model = _resize_model()

    resize_nodes = inspect_resize_nodes(model)

    assert [node.name for node in resize_nodes] == [
        "resize_half_pixel",
        "resize_asymmetric",
    ]
    assert [node.coordinate_transformation_mode for node in resize_nodes] == [
        "half_pixel",
        "asymmetric",
    ]
    assert [node.mode for node in resize_nodes] == ["linear", "linear"]


def test_rewrite_only_replaces_configured_resize_coordinate_mode() -> None:
    model = _resize_model()

    report = rewrite_resize_coordinate_transformation(
        model,
        ResizeRewriteConfig(target_mode="pytorch_half_pixel"),
    )

    resize_nodes = inspect_resize_nodes(model)
    assert report.changed_count == 1
    assert report.remaining_source_mode_count == 0
    assert report.changes[0].node_name == "resize_half_pixel"
    assert report.changes[0].old_mode == "half_pixel"
    assert report.changes[0].new_mode == "pytorch_half_pixel"
    assert [node.coordinate_transformation_mode for node in resize_nodes] == [
        "pytorch_half_pixel",
        "asymmetric",
    ]


def test_rewrite_model_file_saves_checker_clean_model(tmp_path) -> None:
    source = tmp_path / "source.onnx"
    target = tmp_path / "target.onnx"
    onnx.save(_resize_model(), source)

    report = rewrite_model_file(
        source,
        target,
        ResizeRewriteConfig(target_mode="asymmetric"),
    )

    rewritten = onnx.load(target)
    onnx.checker.check_model(rewritten)
    resize_nodes = inspect_resize_nodes(rewritten)
    assert report.changed_count == 1
    assert target.exists()
    assert all(
        node.coordinate_transformation_mode != "half_pixel"
        for node in resize_nodes
    )


def _resize_model() -> onnx.ModelProto:
    input_info = helper.make_tensor_value_info(
        "input",
        TensorProto.FLOAT,
        [1, 1, 4, 4],
    )
    output_info = helper.make_tensor_value_info(
        "output",
        TensorProto.FLOAT,
        [1, 1, 8, 8],
    )
    sizes = helper.make_tensor(
        "sizes",
        TensorProto.INT64,
        [4],
        [1, 1, 8, 8],
    )
    resize_half_pixel = helper.make_node(
        "Resize",
        ["input", "", "", "sizes"],
        ["mid"],
        name="resize_half_pixel",
        mode="linear",
        coordinate_transformation_mode="half_pixel",
        nearest_mode="floor",
    )
    resize_asymmetric = helper.make_node(
        "Resize",
        ["mid", "", "", "sizes"],
        ["output"],
        name="resize_asymmetric",
        mode="linear",
        coordinate_transformation_mode="asymmetric",
        nearest_mode="floor",
    )
    graph = helper.make_graph(
        [resize_half_pixel, resize_asymmetric],
        "resize_test",
        [input_info],
        [output_info],
        [sizes],
    )
    return helper.make_model(
        graph,
        opset_imports=[helper.make_opsetid("", 16)],
    )
