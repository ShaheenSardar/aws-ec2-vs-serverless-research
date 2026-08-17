from pathlib import Path
import hashlib

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch


# ============================================================
# PATHS
# ============================================================

ROOT = Path(__file__).resolve().parents[2]

SUMMARY_FILE = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "formal-summary-by-workload-architecture.csv"
)

FORMAL_FILE = (
    ROOT
    / "data"
    / "final"
    / "experiments.csv"
)

FIGURE_DIR = ROOT / "docs" / "figures"

MANIFEST_FILE = (
    ROOT
    / "data"
    / "processed"
    / "formal"
    / "figure-generation-manifest.csv"
)

FIGURE_DIR.mkdir(
    parents=True,
    exist_ok=True,
)


# ============================================================
# PUBLICATION STYLE
# ============================================================

plt.rcParams.update(
    {
        "font.family": "DejaVu Sans",
        "font.size": 9,
        "axes.titlesize": 10,
        "axes.labelsize": 9,
        "xtick.labelsize": 8,
        "ytick.labelsize": 8,
        "legend.fontsize": 8,
        "axes.linewidth": 0.8,
        "figure.dpi": 120,
        "savefig.dpi": 600,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
    }
)

EC2_COLOR = "#35689A"
SERVERLESS_COLOR = "#C86B28"
GRID_COLOR = "#D9D9D9"

WORKLOADS = [
    "W01",
    "W02",
    "W03",
    "W04",
    "W05",
    "W06",
]

WORKLOAD_LABELS = [
    "W01\nLow",
    "W02\nModerate",
    "W03\nHigh",
    "W04\nSudden Burst",
    "W05\nIdle-to-Burst",
    "W06\nSustained",
]


# ============================================================
# HELPERS
# ============================================================

def sha256_file(path):
    digest = hashlib.sha256()

    with path.open("rb") as file:
        for chunk in iter(
            lambda: file.read(1024 * 1024),
            b"",
        ):
            digest.update(chunk)

    return digest.hexdigest()


def save_figure(fig, name):
    png = FIGURE_DIR / f"{name}.png"
    pdf = FIGURE_DIR / f"{name}.pdf"

    fig.savefig(
        png,
        dpi=600,
        bbox_inches="tight",
        facecolor="white",
    )

    fig.savefig(
        pdf,
        bbox_inches="tight",
        facecolor="white",
    )

    plt.close(fig)

    return [png, pdf]


def style_axis(ax):
    ax.set_axisbelow(True)

    ax.yaxis.grid(
        True,
        linestyle="--",
        linewidth=0.6,
        color=GRID_COLOR,
    )

    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


# ============================================================
# VALIDATE FORMAL DATA ONLY
# ============================================================

def validate(summary, formal):
    if len(formal) != 36:
        raise RuntimeError(
            f"Expected 36 formal trials, found {len(formal)}"
        )

    if len(summary) != 12:
        raise RuntimeError(
            f"Expected 12 summary rows, found {len(summary)}"
        )

    if set(formal["workload_id"]) != set(WORKLOADS):
        raise RuntimeError(
            "Unexpected workload IDs."
        )

    if set(formal["architecture"]) != {"EC2", "SVL"}:
        raise RuntimeError(
            "Unexpected architecture values."
        )

    if (
        formal["experiment_id"]
        .astype(str)
        .str.startswith("P-")
        .any()
    ):
        raise RuntimeError(
            "Pilot experiment detected."
        )

    counts = formal.groupby(
        [
            "workload_id",
            "architecture",
        ]
    ).size()

    if not (counts == 3).all():
        raise RuntimeError(
            "Every condition must contain 3 trials."
        )


# ============================================================
# FIGURE 1 — ARCHITECTURE
# ============================================================

def draw_box(
    ax,
    x,
    y,
    width,
    height,
    title,
    detail,
    edge_color,
):
    box = FancyBboxPatch(
        (x, y),
        width,
        height,
        boxstyle="round,pad=0.015",
        facecolor="white",
        edgecolor=edge_color,
        linewidth=1.4,
    )

    ax.add_patch(box)

    ax.text(
        x + width / 2,
        y + height * 0.66,
        title,
        ha="center",
        va="center",
        weight="bold",
        fontsize=9,
    )

    ax.text(
        x + width / 2,
        y + height * 0.31,
        detail,
        ha="center",
        va="center",
        fontsize=7,
        color="#555555",
    )


def arrow(ax, start, end):
    ax.add_patch(
        FancyArrowPatch(
            start,
            end,
            arrowstyle="-|>",
            mutation_scale=12,
            linewidth=1.2,
            color="#555555",
        )
    )


def figure_architecture():
    fig, ax = plt.subplots(
        figsize=(9, 4.8)
    )

    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis("off")

    ax.text(
        0.5,
        0.95,
        "Experimental Architecture and Measurement Workflow",
        ha="center",
        fontsize=12,
        weight="bold",
    )

    draw_box(
        ax,
        0.04,
        0.39,
        0.17,
        0.22,
        "Locust",
        "Shared /compute workload\nSame concurrency and duration",
        "#555555",
    )

    draw_box(
        ax,
        0.31,
        0.64,
        0.25,
        0.21,
        "EC2 Architecture",
        "t3.small • Ubuntu 24.04\nNginx • Gunicorn • Flask • Docker",
        EC2_COLOR,
    )

    draw_box(
        ax,
        0.31,
        0.17,
        0.25,
        0.21,
        "Serverless Architecture",
        "HTTP API Gateway\nLambda • Python 3.12 • 1024 MB",
        SERVERLESS_COLOR,
    )

    draw_box(
        ax,
        0.69,
        0.64,
        0.20,
        0.21,
        "CloudWatch",
        "CPU • Network\nDuration • Concurrency\nAPI metrics",
        "#666666",
    )

    draw_box(
        ax,
        0.69,
        0.17,
        0.20,
        0.21,
        "Formal Analysis",
        "Performance\nVariability\nCost efficiency",
        "#666666",
    )

    draw_box(
        ax,
        0.69,
        0.425,
        0.20,
        0.12,
        "36 Formal Trials",
        "6 workloads × 2 architectures × 3 trials",
        "#444444",
    )

    arrow(
        ax,
        (0.21, 0.53),
        (0.31, 0.73),
    )

    arrow(
        ax,
        (0.21, 0.47),
        (0.31, 0.27),
    )

    arrow(
        ax,
        (0.56, 0.74),
        (0.69, 0.74),
    )

    arrow(
        ax,
        (0.56, 0.27),
        (0.69, 0.27),
    )

    arrow(
        ax,
        (0.56, 0.70),
        (0.69, 0.52),
    )

    arrow(
        ax,
        (0.56, 0.31),
        (0.69, 0.45),
    )

    ax.text(
        0.5,
        0.055,
        (
            "Result figures use accepted formal W01-W06 trials only; "
            "pilot calibration data are excluded."
        ),
        ha="center",
        fontsize=7.5,
        color="#555555",
    )

    return save_figure(
        fig,
        "figure_01_research_architecture",
    )


# ============================================================
# FIGURES 2–6
# ============================================================

def summary_for(summary, architecture):
    data = summary[
        summary["architecture_code"]
        == architecture
    ].copy()

    data["workload_id"] = pd.Categorical(
        data["workload_id"],
        categories=WORKLOADS,
        ordered=True,
    )

    return data.sort_values(
        "workload_id"
    )


def grouped_bar(
    summary,
    mean_column,
    sd_column,
    ylabel,
    title,
    filename,
):
    ec2 = summary_for(
        summary,
        "EC2",
    )

    svl = summary_for(
        summary,
        "SVL",
    )

    ec2_mean = pd.to_numeric(
        ec2[mean_column]
    ).to_numpy()

    svl_mean = pd.to_numeric(
        svl[mean_column]
    ).to_numpy()

    ec2_sd = pd.to_numeric(
        ec2[sd_column]
    ).to_numpy()

    svl_sd = pd.to_numeric(
        svl[sd_column]
    ).to_numpy()

    x = np.arange(
        len(WORKLOADS)
    )

    width = 0.36

    fig, ax = plt.subplots(
        figsize=(7.4, 4.2)
    )

    ax.bar(
        x - width / 2,
        ec2_mean,
        width,
        yerr=ec2_sd,
        capsize=3,
        color=EC2_COLOR,
        edgecolor="black",
        linewidth=0.45,
        label="EC2",
    )

    ax.bar(
        x + width / 2,
        svl_mean,
        width,
        yerr=svl_sd,
        capsize=3,
        color=SERVERLESS_COLOR,
        edgecolor="black",
        linewidth=0.45,
        label="Serverless",
    )

    ax.set_xticks(x)

    ax.set_xticklabels(
        WORKLOAD_LABELS
    )

    ax.set_xlabel(
        "Formal workload"
    )

    ax.set_ylabel(
        ylabel
    )

    ax.set_title(
        title,
        weight="bold",
        pad=10,
    )

    ax.legend(
        frameon=False,
        ncol=2,
    )

    style_axis(ax)

    ax.set_ylim(
        bottom=0
    )

    fig.tight_layout()

    return save_figure(
        fig,
        filename,
    )


# ============================================================
# FIGURE 7 — RESOURCE BEHAVIOR
# ============================================================

def resource_figure(formal):
    ec2 = formal[
        formal["architecture"] == "EC2"
    ].copy()

    svl = formal[
        formal["architecture"] == "SVL"
    ].copy()

    ec2["ec2_cpu_avg_percent"] = pd.to_numeric(
        ec2["ec2_cpu_avg_percent"]
    )

    ec2["ec2_cpu_max_percent"] = pd.to_numeric(
        ec2["ec2_cpu_max_percent"]
    )

    svl["lambda_concurrency_peak"] = pd.to_numeric(
        svl["lambda_concurrency_peak"]
    )

    cpu = (
        ec2.groupby("workload_id")
        .agg(
            mean_cpu=(
                "ec2_cpu_avg_percent",
                "mean",
            ),
            sd_cpu=(
                "ec2_cpu_avg_percent",
                "std",
            ),
            max_cpu=(
                "ec2_cpu_max_percent",
                "mean",
            ),
        )
        .reindex(WORKLOADS)
    )

    concurrency = (
        svl.groupby("workload_id")
        .agg(
            mean_concurrency=(
                "lambda_concurrency_peak",
                "mean",
            ),
            sd_concurrency=(
                "lambda_concurrency_peak",
                "std",
            ),
        )
        .reindex(WORKLOADS)
    )

    x = np.arange(
        len(WORKLOADS)
    )

    fig, axes = plt.subplots(
        1,
        2,
        figsize=(8.6, 4.0),
    )

    ax = axes[0]

    ax.errorbar(
        x,
        cpu["mean_cpu"],
        yerr=cpu["sd_cpu"],
        marker="o",
        capsize=3,
        color=EC2_COLOR,
        label="Mean CPU ± SD",
    )

    ax.plot(
        x,
        cpu["max_cpu"],
        marker="s",
        linestyle="--",
        color="#758CA5",
        label="Mean trial maximum CPU",
    )

    ax.set_xticks(x)
    ax.set_xticklabels(WORKLOADS)

    ax.set_xlabel(
        "Formal workload"
    )

    ax.set_ylabel(
        "CPU utilization (%)"
    )

    ax.set_title(
        "(a) EC2 resource behavior",
        weight="bold",
    )

    ax.set_ylim(bottom=0)

    ax.legend(
        frameon=False,
        fontsize=7,
    )

    style_axis(ax)

    ax = axes[1]

    ax.errorbar(
        x,
        concurrency["mean_concurrency"],
        yerr=concurrency["sd_concurrency"],
        marker="o",
        capsize=3,
        color=SERVERLESS_COLOR,
        label="Peak concurrency ± SD",
    )

    ax.axhline(
        10,
        linestyle="--",
        linewidth=1,
        color="#777777",
        label="Observed account quota = 10",
    )

    ax.set_xticks(x)
    ax.set_xticklabels(WORKLOADS)

    ax.set_xlabel(
        "Formal workload"
    )

    ax.set_ylabel(
        "ConcurrentExecutions"
    )

    ax.set_title(
        "(b) Lambda scaling behavior",
        weight="bold",
    )

    ax.set_ylim(bottom=0)

    ax.legend(
        frameon=False,
        fontsize=7,
    )

    style_axis(ax)

    fig.suptitle(
        "Resource and Scaling Behavior",
        weight="bold",
        fontsize=11,
    )

    fig.tight_layout()

    return save_figure(
        fig,
        "figure_07_resource_behavior",
    )


# ============================================================
# MAIN
# ============================================================

def main():
    print("=" * 66)
    print(" DAY 2 - TASK 27 - PUBLICATION FIGURE GENERATION")
    print("=" * 66)

    if not SUMMARY_FILE.exists():
        raise FileNotFoundError(
            SUMMARY_FILE
        )

    if not FORMAL_FILE.exists():
        raise FileNotFoundError(
            FORMAL_FILE
        )

    summary = pd.read_csv(
        SUMMARY_FILE
    )

    formal = pd.read_csv(
        FORMAL_FILE
    )

    validate(
        summary,
        formal,
    )

    print()
    print("Formal data validation : PASS")
    print("Formal trials          : 36 / 36")
    print("Summary groups         : 12 / 12")
    print("Pilot trials used      : 0")

    outputs = []

    print()
    print("Generating Figure 1...")
    outputs += figure_architecture()

    print("Generating Figure 2...")
    outputs += grouped_bar(
        summary,
        "mean_avg_latency_ms",
        "sd_avg_latency_ms",
        "Average response latency (ms)",
        "Average Response Latency by Workload",
        "figure_02_average_latency",
    )

    print("Generating Figure 3...")
    outputs += grouped_bar(
        summary,
        "mean_p95_latency_ms",
        "sd_p95_latency_ms",
        "P95 response latency (ms)",
        "P95 Response Latency by Workload",
        "figure_03_p95_latency",
    )

    print("Generating Figure 4...")
    outputs += grouped_bar(
        summary,
        "mean_throughput_rps",
        "sd_throughput_rps",
        "Achieved throughput (requests/s)",
        "Achieved Throughput by Workload",
        "figure_04_throughput",
    )

    print("Generating Figure 5...")
    outputs += grouped_bar(
        summary,
        "mean_failure_rate_percent",
        "sd_failure_rate_percent",
        "Request failure rate (%)",
        "Failure Rate by Workload",
        "figure_05_failure_rate",
    )

    print("Generating Figure 6...")
    outputs += grouped_bar(
        summary,
        "mean_cost_per_1000_successful_requests_usd",
        "sd_cost_per_1000_usd",
        "Estimated USD per 1,000 successful requests",
        "Estimated Cost Efficiency by Workload",
        "figure_06_cost_per_1000",
    )

    print("Generating Figure 7...")
    outputs += resource_figure(
        formal
    )

    if len(outputs) != 14:
        raise RuntimeError(
            f"Expected 14 files; created {len(outputs)}"
        )

    manifest_rows = []

    for source in [
        SUMMARY_FILE,
        FORMAL_FILE,
    ]:
        manifest_rows.append(
            {
                "artifact_type": "SOURCE_DATA",
                "path": str(
                    source.relative_to(ROOT)
                ),
                "sha256": sha256_file(source),
                "formal_only": "YES",
            }
        )

    for output in outputs:
        if not output.exists():
            raise RuntimeError(
                f"Missing output: {output}"
            )

        if output.stat().st_size == 0:
            raise RuntimeError(
                f"Zero-byte output: {output}"
            )

        manifest_rows.append(
            {
                "artifact_type": "FIGURE",
                "path": str(
                    output.relative_to(ROOT)
                ),
                "sha256": sha256_file(output),
                "formal_only": "YES",
            }
        )

    pd.DataFrame(
        manifest_rows
    ).to_csv(
        MANIFEST_FILE,
        index=False,
    )

    print()
    print("=" * 66)
    print(" TASK 27 PASSED")
    print(" 7 / 7 PUBLICATION FIGURES GENERATED")
    print(" 7 / 7 PNG FILES GENERATED")
    print(" 7 / 7 VECTOR PDF FILES GENERATED")
    print(" 36 / 36 FORMAL TRIALS REPRESENTED")
    print(" 0 PILOT TRIALS USED IN RESULT FIGURES")
    print(" SAMPLE SD ERROR BARS INCLUDED")
    print(" FIGURE MANIFEST CREATED")
    print(" PUBLICATION FIGURES READY")
    print("=" * 66)


if __name__ == "__main__":
    main()