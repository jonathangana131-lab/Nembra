#!/usr/bin/env python3
"""Fail closed when the required Dashboard XCTest metrics are absent.

The Simulator artifact is useful regression evidence, not a physical-device or
display-refresh-rate certification. This validator only accepts measurements
owned by the sustained Horizon render-stress test and emitted by XCTest into the
exact result bundle.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


TEST_IDENTIFIER = (
    "NembraUITests/"
    "testHorizonV4DriveSustainedRenderIslandHitchEvidence()"
)
EXPECTED_ITERATIONS = 3
MINIMUM_INTERVAL_SECONDS = 5.5
MAXIMUM_GOOD_HITCH_RATIO_MS_PER_SECOND = 5.0


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read valid JSON from {path}: {error}") from error


def test_records(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        return [payload]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    return []


def validated_measurements(metric: dict[str, Any]) -> list[float] | None:
    raw = metric.get("measurements")
    if not isinstance(raw, list) or len(raw) != EXPECTED_ITERATIONS:
        return None

    measurements: list[float] = []
    for value in raw:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None
        measurement = float(value)
        if not math.isfinite(measurement) or measurement < 0:
            return None
        measurements.append(measurement)
    return measurements


def metric_identity(metric: dict[str, Any]) -> str:
    identifier = metric.get("identifier")
    display_name = metric.get("displayName")
    parts = [
        value
        for value in (identifier, display_name)
        if isinstance(value, str) and value.strip()
    ]
    return " | ".join(parts)


def is_monotonic_clock_metric(metric: dict[str, Any]) -> bool:
    identity = metric_identity(metric).casefold()
    return (
        "xctmetric_clock" in identity
        or ("clock" in identity and "monotonic" in identity)
    )


def is_hitch_ratio_metric(metric: dict[str, Any]) -> bool:
    identity = metric_identity(metric).casefold()
    return "hitch" in identity and "ratio" in identity


def validate(metrics_payload: Any, details_payload: Any) -> list[str]:
    errors: list[str] = []

    if not isinstance(details_payload, dict):
        errors.append("test-details output is not a JSON object")
    else:
        if details_payload.get("testIdentifier") != TEST_IDENTIFIER:
            errors.append(
                "test-details output does not identify the required sustained Dashboard test"
            )
        if details_payload.get("testResult") != "Passed":
            errors.append("the required sustained Dashboard test did not pass")
        if details_payload.get("hasPerformanceMetrics") is not True:
            errors.append("the required sustained Dashboard test has no performance metrics")

    matching_records = [
        record
        for record in test_records(metrics_payload)
        if record.get("testIdentifier") == TEST_IDENTIFIER
    ]
    if len(matching_records) != 1:
        errors.append(
            "performance-metrics output must contain exactly one record for the "
            "required sustained Dashboard test"
        )
        return errors

    runs = matching_records[0].get("testRuns")
    if not isinstance(runs, list) or not runs:
        errors.append("the sustained Dashboard metric record has no test runs")
        return errors

    metrics = [
        metric
        for run in runs
        if isinstance(run, dict)
        for metric in run.get("metrics", [])
        if isinstance(metric, dict)
    ]
    identities = sorted(
        identity
        for metric in metrics
        if (identity := metric_identity(metric))
    )

    accepted: dict[str, tuple[str, list[float]]] = {}
    for family, (predicate, required_unit) in {
        "monotonic clock": (is_monotonic_clock_metric, "s"),
        "app hitch-time ratio": (is_hitch_ratio_metric, "ms/s"),
    }.items():
        candidates: list[tuple[str, list[float]]] = []
        for metric in metrics:
            measurements = validated_measurements(metric)
            identity = metric_identity(metric)
            if (
                predicate(metric)
                and identity
                and measurements is not None
                and metric.get("unitOfMeasurement") == required_unit
            ):
                candidates.append((identity, measurements))
        if len(candidates) == 1:
            accepted[family] = candidates[0]
        else:
            errors.append(
                f"expected exactly one {family} metric in {required_unit} with "
                f"{EXPECTED_ITERATIONS} finite, nonnegative measurements; found "
                f"{len(candidates)} candidates (all identities: {identities})"
            )

    clock = accepted.get("monotonic clock")
    if clock is not None and any(
        value < MINIMUM_INTERVAL_SECONDS for value in clock[1]
    ):
        errors.append(
            "monotonic clock measurements do not prove each sustained interval "
            f"lasted at least {MINIMUM_INTERVAL_SECONDS:.1f} seconds: {clock[1]}"
        )

    hitch_ratio = accepted.get("app hitch-time ratio")
    if hitch_ratio is not None and any(
        value >= MAXIMUM_GOOD_HITCH_RATIO_MS_PER_SECOND
        for value in hitch_ratio[1]
    ):
        errors.append(
            "hitch-time ratio is outside Apple's good-experience range of less "
            f"than {MAXIMUM_GOOD_HITCH_RATIO_MS_PER_SECOND:.1f} ms/s: "
            f"{hitch_ratio[1]}"
        )

    if not errors:
        for family, (identifier, measurements) in accepted.items():
            print(f"{family}: {identifier} = {measurements}")
        print(
            "Accepted Release-configured Simulator-only sustained Dashboard "
            "performance evidence; "
            "this is not physical-device or display-refresh-rate proof."
        )

    return errors


def fixture(
    *,
    metrics: list[dict[str, Any]],
    has_performance_metrics: bool = True,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    return (
        [{"testIdentifier": TEST_IDENTIFIER, "testRuns": [{"metrics": metrics}]}],
        {
            "testIdentifier": TEST_IDENTIFIER,
            "testResult": "Passed",
            "hasPerformanceMetrics": has_performance_metrics,
        },
    )


def run_self_tests() -> None:
    def expect_accepted(name: str, payload: tuple[Any, Any]) -> None:
        errors = validate(*payload)
        if errors:
            raise RuntimeError(f"accept fixture {name!r} failed: {errors}")

    def expect_rejected(name: str, payload: tuple[Any, Any]) -> None:
        if not validate(*payload):
            raise RuntimeError(f"reject fixture {name!r} was unexpectedly accepted")

    accepted_identifier_shape = fixture(metrics=[
        {
            "identifier": "com.apple.dt.XCTMetric_Clock.time.monotonic",
            "displayName": "Elapsed render interval",
            "unitOfMeasurement": "s",
            "measurements": [6.0, 6.1, 6.0],
        },
        {
            "identifier": "com.apple.dt.XCTMetric_Hitch.frameStats.renderTime.p90",
            "displayName": "Hitch Time Ratio",
            "unitOfMeasurement": "ms/s",
            "measurements": [0.0, 1.0, 4.9],
        },
    ])
    expect_accepted("identifier shape", accepted_identifier_shape)

    # xcresulttool's schema requires displayName but makes identifier optional.
    accepted_display_name_shape = fixture(metrics=[
        {
            "displayName": "Clock Monotonic Time",
            "unitOfMeasurement": "s",
            "measurements": [6.0, 6.0, 6.0],
        },
        {
            "displayName": "Hitch Time Ratio",
            "unitOfMeasurement": "ms/s",
            "measurements": [0.0, 0.0, 0.0],
        },
    ])
    expect_accepted("display-name shape", accepted_display_name_shape)

    missing_metrics = fixture(metrics=[], has_performance_metrics=False)
    expect_rejected("missing metrics", missing_metrics)

    short_clock = fixture(metrics=[
        {
            "displayName": "Clock Monotonic Time",
            "unitOfMeasurement": "s",
            "measurements": [5.4, 6.0, 6.0],
        },
        {
            "displayName": "Hitch Time Ratio",
            "unitOfMeasurement": "ms/s",
            "measurements": [0.0, 0.0, 0.0],
        },
    ])
    expect_rejected("short clock", short_clock)

    incomplete_hitch = fixture(metrics=[
        {
            "displayName": "Clock Monotonic Time",
            "unitOfMeasurement": "s",
            "measurements": [6.0, 6.0, 6.0],
        },
        {
            "displayName": "Hitch Time Ratio",
            "unitOfMeasurement": "ms/s",
            "measurements": [0.0, 0.0],
        },
    ])
    expect_rejected("incomplete hitch", incomplete_hitch)

    distracting_hitch = fixture(metrics=[
        {
            "displayName": "Clock Monotonic Time",
            "unitOfMeasurement": "s",
            "measurements": [6.0, 6.0, 6.0],
        },
        {
            "displayName": "Hitch Time Ratio",
            "unitOfMeasurement": "ms/s",
            "measurements": [4.9, 5.0, 100.0],
        },
    ])
    expect_rejected("noticeable or distracting hitch", distracting_hitch)

    wrong_hitch_unit = fixture(metrics=[
        {
            "displayName": "Clock Monotonic Time",
            "unitOfMeasurement": "s",
            "measurements": [6.0, 6.0, 6.0],
        },
        {
            "displayName": "Hitch Time Ratio",
            "unitOfMeasurement": "ms",
            "measurements": [0.0, 0.0, 0.0],
        },
    ])
    expect_rejected("wrong hitch unit", wrong_hitch_unit)

    generic_hitch = fixture(metrics=[
        {
            "displayName": "Clock Monotonic Time",
            "unitOfMeasurement": "s",
            "measurements": [6.0, 6.0, 6.0],
        },
        {
            "displayName": "Total Hitch Time",
            "unitOfMeasurement": "ms/s",
            "measurements": [0.0, 0.0, 0.0],
        },
    ])
    expect_rejected("generic hitch metric", generic_hitch)

    wrong_test_metrics, wrong_test_details = accepted_display_name_shape
    wrong_test_details = dict(wrong_test_details)
    wrong_test_details["testIdentifier"] = "NembraUITests/testOtherPerformance()"
    expect_rejected("wrong exact test", (wrong_test_metrics, wrong_test_details))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--metrics", type=Path)
    parser.add_argument("--details", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    if arguments.self_test:
        run_self_tests()
        print("Dashboard performance evidence validator fixtures passed.")
        return 0
    if arguments.metrics is None or arguments.details is None:
        parser.error("--metrics and --details are required unless --self-test is used")

    try:
        metrics_payload = load_json(arguments.metrics)
        details_payload = load_json(arguments.details)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    errors = validate(metrics_payload, details_payload)
    if errors:
        print("Dashboard performance evidence rejected:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
