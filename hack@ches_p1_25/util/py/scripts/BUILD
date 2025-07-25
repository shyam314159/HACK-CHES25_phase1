# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@rules_python//python:defs.bzl", "py_binary")
load("//third_party/python:requirements.bzl", "requirement")

py_binary(
    name = "object_size",
    srcs = ["object_size.py"],
    deps = [
        "//util/py/packages/impl/object_size:elf",
        "//util/py/packages/impl/object_size:memory",
        "//util/py/packages/impl/object_size:report",
        "//util/py/packages/impl/object_size:types",
        "//util/py/packages/lib:bazel",
        "//util/py/packages/lib:ot_logging",
    ],
)

py_binary(
    name = "audit_sec_mmio_calls",
    srcs = ["audit_sec_mmio_calls.py"],
    visibility = ["//visibility:public"],
    deps = [
        "//util/py/packages/lib:bazel",
        "//util/py/packages/lib:ot_logging",
        "//util/py/packages/lib:register_usage_report",
        "//util/py/packages/lib:run",
        "//util/reggen:ip_block",
        requirement("rich"),
        requirement("typer"),
    ],
)

py_binary(
    name = "bazel_aspect_tool_audit_sec_mmio_calls",
    srcs = ["bazel_aspect_tool_audit_sec_mmio_calls.py"],
    visibility = ["//visibility:public"],
    deps = [
        "//util/py/packages/lib:bazel",
        "//util/py/packages/lib:register_usage_report",
    ],
)

py_binary(
    name = "bitstream_cache_create",
    srcs = ["bitstream_cache_create.py"],
    visibility = ["//visibility:public"],
    deps = [
        requirement("jsonschema"),
    ],
)

py_binary(
    name = "bitstreams_fragment_from_manifest",
    srcs = ["bitstreams_fragment_from_manifest.py"],
    visibility = ["//visibility:public"],
    deps = [
        requirement("jsonschema"),
    ],
)

py_binary(
    name = "get_bitstream_build_id",
    srcs = ["get_bitstream_build_id.py"],
    data = [
        "//rules/scripts:bitstreams_manifest_schema",
        "@bitstreams//:manifest",
    ],
    visibility = ["//visibility:public"],
    deps = [
        requirement("jsonschema"),
    ],
)
