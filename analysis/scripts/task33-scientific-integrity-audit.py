from __future__ import annotations

import csv
import hashlib
import math
import re
import sys
from pathlib import Path

import pandas as pd


# ============================================================
# TASK 33 — SCIENTIFIC INTEGRITY AUDIT
# Read-only for research results/paper.
# Writes only Task 33 audit artifacts.
# ============================================================

ROOT = Path(r"E:\GKS Research\aws-ec2-vs-serverless-research")

FORMAL = ROOT / "data" / "final" / "experiments.csv"
WORKLOADS = ROOT / "load-testing" / "scenarios" / "formal-workloads.csv"
MATRIX = ROOT / "docs" / "methodology" / "formal-experiment-matrix.csv"
SUMMARY = ROOT / "data" / "processed" / "formal" / "formal-summary-by-workload-architecture.csv"
COMPARISON = ROOT / "data" / "processed" / "formal" / "formal-architecture-comparison.csv"
PREPRINT = ROOT / "docs" / "preprint" / "preprint.md"
REPRO = ROOT / "docs" / "reproducibility" / "REPRODUCIBILITY.md"

TABLE_DIR = ROOT / "data" / "processed" / "formal" / "tables"
TABLE_DOC_DIR = ROOT / "docs" / "tables"
FIGURE_DIR = ROOT / "docs" / "figures"
ANALYSIS_DIR = ROOT / "analysis" / "scripts"

OUT_DIR = ROOT / "data" / "processed" / "formal"
AUDIT_CSV = OUT_DIR / "task33-scientific-integrity-audit.csv"
AUDIT_MD = ROOT / "docs" / "reproducibility" / "SCIENTIFIC-INTEGRITY-AUDIT.md"
TRACE_CSV = OUT_DIR / "task33-traceability-manifest.csv"


WORKLOAD_EXPECTED = {
    "W01": {"name": "Low", "users": 5, "spawn": 1.0, "duration": 60, "idle": 0},
    "W02": {"name": "Moderate", "users": 15, "spawn": 3.0, "duration": 60, "idle": 0},
    "W03": {"name": "High", "users": 30, "spawn": 5.0, "duration": 60, "idle": 0},
    "W04": {"name": "Sudden-Burst", "users": 30, "spawn": 30.0, "duration": 60, "idle": 0},
    "W05": {"name": "Idle-to-Burst", "users": 30, "spawn": 30.0, "duration": 60, "idle": 300},
    "W06": {"name": "Sustained", "users": 20, "spawn": 4.0, "duration": 300, "idle": 0},
}

WORKLOAD_HEADINGS = {
    "W01": "## 5.1 Low Workload",
    "W02": "## 5.2 Moderate Workload",
    "W03": "## 5.3 High Workload",
    "W04": "## 5.4 Sudden Burst",
    "W05": "## 5.5 Idle-to-Burst",
    "W06": "## 5.6 Sustained Workload",
}


def require(path: Path) -> None:
    if not path.exists():
        raise FileNotFoundError(f"Required Task 33 input missing: {path}")


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def clean(value) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and math.isnan(value):
        return ""
    return str(value).strip()


def num(value) -> float:
    return float(value)


def section(text: str, start_heading: str, next_heading: str | None = None) -> str:
    start = text.find(start_heading)
    if start < 0:
        return ""
    if next_heading:
        end = text.find(next_heading, start + len(start_heading))
        if end >= 0:
            return text[start:end]
    return text[start:]


def comparison_row(df: pd.DataFrame, workload: str) -> pd.Series:
    rows = df[df["workload_id"].astype(str) == workload]
    if len(rows) != 1:
        raise RuntimeError(f"Expected exactly one comparison row for {workload}; found {len(rows)}")
    return rows.iloc[0]


required = [FORMAL, WORKLOADS, MATRIX, SUMMARY, COMPARISON, PREPRINT, REPRO]
for p in required:
    require(p)

OUT_DIR.mkdir(parents=True, exist_ok=True)
AUDIT_MD.parent.mkdir(parents=True, exist_ok=True)

formal = pd.read_csv(FORMAL)
workloads = pd.read_csv(WORKLOADS)
matrix = pd.read_csv(MATRIX)
summary = pd.read_csv(SUMMARY)
comparison = pd.read_csv(COMPARISON)

paper = PREPRINT.read_text(encoding="utf-8-sig")
repro = REPRO.read_text(encoding="utf-8-sig")

audit_rows: list[dict[str, str]] = []


def add(check: str, passed: bool, evidence: str) -> None:
    audit_rows.append(
        {
            "check": check,
            "status": "PASS" if passed else "FAIL",
            "evidence": evidence,
        }
    )


# ============================================================
# CHECK 1 — 36 formal trials
# ============================================================

add(
    "01_36_formal_trials",
    len(formal) == 36 and formal["experiment_id"].nunique() == 36,
    f"rows={len(formal)}; unique_ids={formal['experiment_id'].nunique()}",
)


# ============================================================
# CHECK 2 — pilot data excluded
# ============================================================

pilot_ids = formal["experiment_id"].astype(str).str.startswith("P-").sum()
paper_formal_scope = (
    "Pilot calibration runs are excluded" in paper
    or "Pilot data were stored separately" in paper
)
add(
    "02_pilot_excluded_from_formal_results",
    pilot_ids == 0 and paper_formal_scope,
    f"pilot_ids_in_formal={int(pilot_ids)}; paper_discloses_separation={paper_formal_scope}",
)


# ============================================================
# CHECK 3 — no fake measurements / raw evidence traceability
# Operational definition:
# - no TO_BE_MEASURED placeholders
# - no obvious fabricated placeholders
# - each accepted ID has raw Locust + metadata evidence
# - application/terraform commits are populated
# ============================================================

string_df = formal.astype(str)
placeholder_tokens = {"TO_BE_MEASURED", "TBD", "FAKE", "FABRICATED", "PLACEHOLDER"}
placeholder_count = 0
for token in placeholder_tokens:
    placeholder_count += int((string_df == token).sum().sum())

raw_expected = 0
raw_found = 0
missing_raw: list[str] = []

for exp_id in formal["experiment_id"].astype(str):
    arch_dir = "ec2" if exp_id.startswith("EC2-") else "serverless"
    files = [
        ROOT / "data" / "raw" / "formal" / arch_dir / f"{exp_id}_stats.csv",
        ROOT / "data" / "raw" / "formal" / arch_dir / f"{exp_id}_stats_history.csv",
        ROOT / "data" / "raw" / "formal" / arch_dir / f"{exp_id}_failures.csv",
        ROOT / "data" / "raw" / "formal" / arch_dir / f"{exp_id}_exceptions.csv",
        ROOT / "data" / "raw" / "formal" / arch_dir / f"{exp_id}_console.log",
        ROOT / "data" / "raw" / "formal" / "metadata" / f"{exp_id}_metadata.csv",
    ]
    raw_expected += len(files)
    for path in files:
        if path.exists():
            raw_found += 1
        else:
            missing_raw.append(str(path.relative_to(ROOT)))

commit_cols_ok = all(
    c in formal.columns for c in ["application_commit", "terraform_commit"]
)
empty_commit_rows = 999
if commit_cols_ok:
    empty_commit_rows = int(
        (
            formal["application_commit"].map(clean).eq("")
            | formal["terraform_commit"].map(clean).eq("")
        ).sum()
    )

add(
    "03_no_fake_measurements_raw_evidence",
    placeholder_count == 0
    and raw_found == raw_expected
    and empty_commit_rows == 0,
    (
        f"placeholder_cells={placeholder_count}; raw_evidence={raw_found}/{raw_expected}; "
        f"rows_missing_commit_trace={empty_commit_rows}; "
        f"missing_raw_examples={missing_raw[:3]}"
    ),
)


# ============================================================
# CHECK 4 — no missing formal values
# ============================================================

empty_cells = 0
empty_examples: list[str] = []
for idx, row in formal.iterrows():
    for col in formal.columns:
        if clean(row[col]) == "":
            empty_cells += 1
            if len(empty_examples) < 5:
                empty_examples.append(f"{row['experiment_id']}:{col}")

tbm_count = int((formal.astype(str) == "TO_BE_MEASURED").sum().sum())

add(
    "04_no_missing_formal_values",
    empty_cells == 0 and tbm_count == 0,
    f"empty_cells={empty_cells}; TO_BE_MEASURED={tbm_count}; examples={empty_examples}",
)


# ============================================================
# CHECK 5 — every table traceable to dataset
# ============================================================

table_csvs = sorted(TABLE_DIR.glob("table_0[1-6]_*.csv"))
table_mds = sorted(TABLE_DOC_DIR.glob("table_0[1-6]_*.md"))
table_audits = list(TABLE_DIR.glob("*audit*.csv"))
table_manifests = list(TABLE_DIR.glob("*manifest*.csv"))

table_audit_failures = 0
for path in table_audits:
    try:
        df = pd.read_csv(path)
        if "status" in df.columns:
            table_audit_failures += int((df["status"].astype(str).str.upper() != "PASS").sum())
    except Exception:
        table_audit_failures += 1

table_script = ANALYSIS_DIR / "generate-final-tables.py"
table_script_text = table_script.read_text(encoding="utf-8-sig") if table_script.exists() else ""
table_source_link = (
    "experiments.csv" in table_script_text
    or "formal-summary-by-workload-architecture.csv" in table_script_text
)

add(
    "05_every_table_traceable_to_dataset",
    len(table_csvs) == 6
    and len(table_mds) == 6
    and table_script.exists()
    and table_source_link
    and table_audit_failures == 0
    and len(table_manifests) >= 1,
    (
        f"table_csvs={len(table_csvs)}/6; table_mds={len(table_mds)}/6; "
        f"generator={table_script.exists()}; source_link={table_source_link}; "
        f"table_audit_failures={table_audit_failures}; manifests={len(table_manifests)}"
    ),
)


# ============================================================
# CHECK 6 — every figure traceable to dataset
# ============================================================

pngs = sorted(FIGURE_DIR.glob("figure_0[1-7]_*.png"))
pdfs = sorted(FIGURE_DIR.glob("figure_0[1-7]_*.pdf"))
figure_manifests = list(FIGURE_DIR.glob("*manifest*.csv"))
figure_manifests += list((ROOT / "data" / "processed" / "formal").glob("*figure*manifest*.csv"))

figure_script = ANALYSIS_DIR / "generate-publication-figures.py"
figure_script_text = figure_script.read_text(encoding="utf-8-sig") if figure_script.exists() else ""
figure_source_link = (
    "experiments.csv" in figure_script_text
    or "formal-summary-by-workload-architecture.csv" in figure_script_text
    or "formal-trial-analysis-input.csv" in figure_script_text
)

add(
    "06_every_figure_traceable_to_dataset",
    len(pngs) == 7
    and len(pdfs) == 7
    and figure_script.exists()
    and figure_source_link
    and len(figure_manifests) >= 1,
    (
        f"png={len(pngs)}/7; pdf={len(pdfs)}/7; generator={figure_script.exists()}; "
        f"source_link={figure_source_link}; manifests={len(figure_manifests)}"
    ),
)


# ============================================================
# CHECK 7 — no changed workload parameters
# ============================================================

frozen_problems: list[str] = []

if len(workloads) != 6:
    frozen_problems.append(f"workload_file_rows={len(workloads)}")

for _, row in workloads.iterrows():
    raw_id = str(row["workload_id"]).strip()
    wid = raw_id[2:] if raw_id.startswith("F-") else raw_id
    if wid not in WORKLOAD_EXPECTED:
        frozen_problems.append(f"unexpected_workload={raw_id}")
        continue

    exp = WORKLOAD_EXPECTED[wid]
    if int(float(row["users"])) != exp["users"]:
        frozen_problems.append(f"{wid}:users")
    if float(row["spawn_rate"]) != exp["spawn"]:
        frozen_problems.append(f"{wid}:spawn")
    if int(float(row["duration_seconds"])) != exp["duration"]:
        frozen_problems.append(f"{wid}:duration")
    if int(float(row["idle_before_seconds"])) != exp["idle"]:
        frozen_problems.append(f"{wid}:idle")

for wid, exp in WORKLOAD_EXPECTED.items():
    rows = formal[formal["workload_id"].astype(str) == wid]
    if len(rows) != 6:
        frozen_problems.append(f"{wid}:formal_rows={len(rows)}")
        continue

    if set(pd.to_numeric(rows["concurrent_users"]).astype(int)) != {exp["users"]}:
        frozen_problems.append(f"{wid}:dataset_users")
    if set(pd.to_numeric(rows["spawn_rate"]).astype(float)) != {exp["spawn"]}:
        frozen_problems.append(f"{wid}:dataset_spawn")
    if set(pd.to_numeric(rows["duration_seconds"]).astype(int)) != {exp["duration"]}:
        frozen_problems.append(f"{wid}:dataset_duration")
    if set(pd.to_numeric(rows["compute_iterations"]).astype(int)) != {25000}:
        frozen_problems.append(f"{wid}:compute_iterations")

add(
    "07_no_changed_workload_parameters",
    not frozen_problems,
    "none" if not frozen_problems else "; ".join(frozen_problems),
)


# ============================================================
# CHECK 8 — exactly 3 trials per condition
# ============================================================

group_counts = formal.groupby(["workload_id", "architecture"]).size()
bad_groups = group_counts[group_counts != 3]

add(
    "08_three_trials_per_condition",
    len(group_counts) == 12 and bad_groups.empty,
    f"groups={len(group_counts)}; bad_groups={bad_groups.to_dict()}",
)


# ============================================================
# CHECK 9 — Lambda quota limitation disclosed
# ============================================================

paper_lower = paper.lower()
quota_ok = all(
    token in paper_lower
    for token in [
        "account-specific",
        "concurrency quota",
        "not",
        "general",
        "lambda",
    ]
)
quota_section_ok = "## 7.4 AWS Account Concurrency Limitation" in paper
bad_quota_claims = [
    "aws lambda maximum concurrency is 10",
    "lambda maximum concurrency is 10",
    "aws lambda limit is 10",
    "lambda can only scale to 10",
]
quota_bad = [p for p in bad_quota_claims if p in paper_lower]

add(
    "09_lambda_quota_limitation_disclosed",
    quota_ok and quota_section_ok and not quota_bad,
    f"section_7_4={quota_section_ok}; prohibited_claims={quota_bad}",
)


# ============================================================
# CHECK 10 — closed-loop Locust behavior disclosed
# ============================================================

closed_loop_ok = (
    "closed-loop" in paper_lower
    and "achieved throughput" in paper_lower
    and "fixed offered" in paper_lower
)

add(
    "10_closed_loop_locust_behavior_disclosed",
    closed_loop_ok,
    (
        f"closed_loop={'closed-loop' in paper_lower}; "
        f"achieved_throughput={'achieved throughput' in paper_lower}; "
        f"fixed_offered_caution={'fixed offered' in paper_lower}"
    ),
)


# ============================================================
# CHECK 11 — cost assumptions disclosed
# ============================================================

cost_tokens = [
    "list-price",
    "free tier",
    "credits",
    "discount",
    "taxes",
    "not_directly_attributable",
    "cost per 1,000 successful requests",
]
missing_cost_tokens = [t for t in cost_tokens if t not in paper_lower]

add(
    "11_cost_assumptions_disclosed",
    not missing_cost_tokens,
    f"missing_tokens={missing_cost_tokens}",
)


# ============================================================
# CHECK 12 — research questions answered
# ============================================================

rq_intro = all(f"**RQ{i}." in paper for i in range(1, 5))
rq_answers = all(f"**RQ{i} —" in paper for i in range(1, 5))
rq_section = "## 6.5 Answers to the Research Questions" in paper

add(
    "12_research_questions_answered",
    rq_intro and rq_answers and rq_section,
    f"rq_intro={rq_intro}; rq_answers={rq_answers}; answer_section={rq_section}",
)


# ============================================================
# CHECK 13 — conclusions supported by formal data
# ============================================================

comparison_by_w = {w: comparison_row(comparison, w) for w in WORKLOAD_EXPECTED}

cost_ec2_better = sum(
    num(r["ec2_mean_cost_per_1000_usd"]) < num(r["serverless_mean_cost_per_1000_usd"])
    for r in comparison_by_w.values()
)

reliability_ec2_not_worse = sum(
    num(r["ec2_mean_failure_rate_percent"]) <= num(r["serverless_mean_failure_rate_percent"])
    for r in comparison_by_w.values()
)

w04 = comparison_by_w["W04"]
w05 = comparison_by_w["W05"]
w06 = comparison_by_w["W06"]

burst_support = (
    num(w04["serverless_mean_avg_latency_ms"]) < num(w04["ec2_mean_avg_latency_ms"])
    and num(w04["serverless_mean_throughput_rps"]) > num(w04["ec2_mean_throughput_rps"])
    and num(w05["serverless_mean_avg_latency_ms"]) < num(w05["ec2_mean_avg_latency_ms"])
    and num(w05["serverless_mean_throughput_rps"]) > num(w05["ec2_mean_throughput_rps"])
)

mixed_w06 = (
    num(w06["serverless_mean_avg_latency_ms"]) < num(w06["ec2_mean_avg_latency_ms"])
    and num(w06["serverless_mean_p95_ms"]) > num(w06["ec2_mean_p95_ms"])
)

conclusion = section(paper, "# 9. Conclusion", "# References")
conclusion_lower = conclusion.lower()

conclusion_text_ok = all(
    phrase in conclusion_lower
    for phrase in [
        "workload-dependent",
        "lower normalized cost",
        "stronger request reliability",
        "not evidence that aws lambda normally has a concurrency limit of 10",
    ]
)

support_ok = (
    cost_ec2_better >= 4
    and reliability_ec2_not_worse >= 4
    and burst_support
    and mixed_w06
)

add(
    "13_conclusions_supported_by_data",
    support_ok and conclusion_text_ok,
    (
        f"EC2_lower_cost_workloads={cost_ec2_better}/6; "
        f"EC2_not_worse_reliability={reliability_ec2_not_worse}/6; "
        f"W04_W05_burst_support={burst_support}; W06_mixed={mixed_w06}; "
        f"conclusion_text_ok={conclusion_text_ok}"
    ),
)


# ============================================================
# CHECK 14 — no contradictions between paper and CSV
# Includes numeric spot-check of every W01-W06 Results subsection
# plus known EC2 Docker contradiction guard.
# ============================================================

contradictions: list[str] = []

if "the ec2 system used a `t3.small` instance running ubuntu 24.04, docker" in paper_lower:
    contradictions.append("Abstract incorrectly describes formal EC2 deployment as Docker")

if "the application ran in docker" in paper_lower:
    contradictions.append("Section 3.2 incorrectly describes formal EC2 deployment as Docker")

table1_path = TABLE_DOC_DIR / "table_01_experimental_environment.md"
if table1_path.exists():
    table1_lower = table1_path.read_text(encoding="utf-8-sig").lower()
    if "docker" in table1_lower:
        contradictions.append("Table 1 contains Docker for formal EC2 deployment")

if "aws region (`ap-south-1`)" not in paper_lower and "ap-south-1" not in paper_lower:
    contradictions.append("Paper does not contain ap-south-1")

if "25,000" not in paper:
    contradictions.append("Paper does not state 25,000 compute iterations")

heading_order = ["W01", "W02", "W03", "W04", "W05", "W06"]

for i, wid in enumerate(heading_order):
    next_heading = (
        WORKLOAD_HEADINGS[heading_order[i + 1]]
        if i + 1 < len(heading_order)
        else "## 5.7 Cost Comparison"
    )
    sec = section(paper, WORKLOAD_HEADINGS[wid], next_heading)
    if not sec:
        contradictions.append(f"{wid}: Results subsection missing")
        continue

    r = comparison_by_w[wid]
    expected_numbers = [
        f"{num(r['ec2_mean_avg_latency_ms']):.2f}",
        f"{num(r['serverless_mean_avg_latency_ms']):.2f}",
        f"{num(r['ec2_mean_p95_ms']):.2f}",
        f"{num(r['serverless_mean_p95_ms']):.2f}",
        f"{num(r['ec2_mean_throughput_rps']):.2f}",
        f"{num(r['serverless_mean_throughput_rps']):.2f}",
        f"{num(r['ec2_mean_failure_rate_percent']):.3f}",
        f"{num(r['serverless_mean_failure_rate_percent']):.3f}",
        f"{num(r['ec2_mean_cost_per_1000_usd']):.6f}",
        f"{num(r['serverless_mean_cost_per_1000_usd']):.6f}",
    ]

    missing_numbers = [n for n in expected_numbers if n not in sec]
    if missing_numbers:
        contradictions.append(f"{wid}: paper missing current CSV values {missing_numbers}")

add(
    "14_no_contradictions_text_vs_csv",
    not contradictions,
    "none" if not contradictions else " | ".join(contradictions[:10]),
)


# ============================================================
# TRACEABILITY MANIFEST
# ============================================================

trace_paths: list[Path] = [
    FORMAL,
    WORKLOADS,
    MATRIX,
    SUMMARY,
    COMPARISON,
    PREPRINT,
    REPRO,
]

trace_paths += table_csvs + table_mds + pngs + pdfs

for p in [
    ANALYSIS_DIR / "generate-final-tables.py",
    ANALYSIS_DIR / "generate-publication-figures.py",
    ANALYSIS_DIR / "analyze-formal-results.ps1",
    ANALYSIS_DIR / "calculate-formal-costs.ps1",
    ANALYSIS_DIR / "build-complete-preprint.py",
]:
    if p.exists():
        trace_paths.append(p)

trace_paths = sorted(set(trace_paths))

trace_rows = []
for p in trace_paths:
    if p.exists() and p.is_file():
        trace_rows.append(
            {
                "path": str(p.relative_to(ROOT)),
                "sha256": sha256(p),
                "bytes": p.stat().st_size,
            }
        )

pd.DataFrame(trace_rows).to_csv(TRACE_CSV, index=False)


# ============================================================
# WRITE AUDIT OUTPUTS
# ============================================================

audit = pd.DataFrame(audit_rows)
audit.to_csv(AUDIT_CSV, index=False)

failures = audit[audit["status"] != "PASS"]

md = []
md.append("# Task 33 — Scientific Integrity Audit")
md.append("")
md.append(f"- Checks passed: **{len(audit) - len(failures)} / {len(audit)}**")
md.append(f"- Checks failed: **{len(failures)}**")
md.append("")
md.append("| Check | Status | Evidence |")
md.append("|---|---|---|")
for _, r in audit.iterrows():
    evidence = str(r["evidence"]).replace("|", "/")
    md.append(f"| {r['check']} | {r['status']} | {evidence} |")
md.append("")
md.append("## Interpretation")
md.append("")
if failures.empty:
    md.append(
        "All automated scientific-integrity checks passed. This audit confirms internal repository/data/paper consistency under the explicit checks implemented here; it does not replace external peer review."
    )
else:
    md.append(
        "One or more automated checks failed. The preprint should not be frozen until the failed checks are corrected and Task 33 is rerun."
    )

AUDIT_MD.write_text("\n".join(md) + "\n", encoding="utf-8")


# ============================================================
# TERMINAL OUTPUT
# ============================================================

print("=" * 80)
print(" DAY 2 - TASK 33 - SCIENTIFIC INTEGRITY AUDIT")
print("=" * 80)
print()
print(audit[["check", "status"]].to_string(index=False))
print()
print("Integrity summary")
print("-----------------")
print(f"Formal trials                    : {len(formal)} / 36")
print(f"Unique formal IDs                : {formal['experiment_id'].nunique()} / 36")
print(f"Pilot IDs in formal data         : {int(pilot_ids)}")
print(f"Formal condition groups          : {len(group_counts)} / 12")
print(f"Groups with exactly 3 trials     : {int((group_counts == 3).sum())} / 12")
print(f"Raw evidence files               : {raw_found} / {raw_expected}")
print(f"Missing formal cells             : {empty_cells}")
print(f"Frozen workload problems         : {len(frozen_problems)}")
print(f"Table CSV / Markdown             : {len(table_csvs)} / 6 ; {len(table_mds)} / 6")
print(f"Figure PNG / PDF                 : {len(pngs)} / 7 ; {len(pdfs)} / 7")
print(f"Text/data contradictions         : {len(contradictions)}")
print(f"Audit checks passed              : {len(audit) - len(failures)} / {len(audit)}")
print(f"Audit checks failed              : {len(failures)}")
print(f"Traceability manifest entries    : {len(trace_rows)}")

if failures.empty:
    print()
    print("=" * 80)
    print(" TASK 33 PASSED")
    print(" 36 / 36 FORMAL TRIALS VERIFIED")
    print(" PILOT DATA EXCLUDED FROM FORMAL RESULTS")
    print(" RAW EVIDENCE TRACEABILITY VERIFIED")
    print(" NO MISSING FORMAL VALUES")
    print(" TABLE TRACEABILITY VERIFIED")
    print(" FIGURE TRACEABILITY VERIFIED")
    print(" FROZEN WORKLOAD PARAMETERS VERIFIED")
    print(" 3 TRIALS PER CONDITION VERIFIED")
    print(" LAMBDA ACCOUNT-QUOTA LIMITATION DISCLOSED")
    print(" CLOSED-LOOP LOCUST BEHAVIOR DISCLOSED")
    print(" COST ASSUMPTIONS DISCLOSED")
    print(" ALL 4 RESEARCH QUESTIONS ANSWERED")
    print(" CONCLUSIONS SUPPORTED BY FORMAL DATA")
    print(" NO DETECTED CONTRADICTIONS BETWEEN PAPER AND FORMAL CSV")
    print(" SCIENTIFIC INTEGRITY AUDIT COMPLETE")
    print("=" * 80)
    sys.exit(0)

print()
print("=" * 80)
print(" TASK 33 FAILED")
print(f" {len(failures)} CHECK(S) REQUIRE CORRECTION")
print("=" * 80)
print()
print(failures[["check", "evidence"]].to_string(index=False))
sys.exit(1)
