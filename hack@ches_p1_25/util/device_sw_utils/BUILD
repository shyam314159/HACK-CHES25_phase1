# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@rules_python//python:defs.bzl", "py_binary")
load("//third_party/python:requirements.bzl", "requirement")

package(default_visibility = ["//visibility:public"])

py_binary(
    name = "extract_sw_logs_db",
    srcs = ["extract_sw_logs.py"],
    main = "extract_sw_logs.py",
    deps = [
        requirement("pyelftools"),
    ],
)
