# Task 33 — Scientific Integrity Audit

- Checks passed: **14 / 14**
- Checks failed: **0**

| Check | Status | Evidence |
|---|---|---|
| 01_36_formal_trials | PASS | rows=36; unique_ids=36 |
| 02_pilot_excluded_from_formal_results | PASS | pilot_ids_in_formal=0; paper_discloses_separation=True |
| 03_no_fake_measurements_raw_evidence | PASS | placeholder_cells=0; raw_evidence=216/216; rows_missing_commit_trace=0; missing_raw_examples=[] |
| 04_no_missing_formal_values | PASS | empty_cells=0; TO_BE_MEASURED=0; examples=[] |
| 05_every_table_traceable_to_dataset | PASS | table_csvs=6/6; table_mds=6/6; generator=True; source_link=True; table_audit_failures=0; manifests=1 |
| 06_every_figure_traceable_to_dataset | PASS | png=7/7; pdf=7/7; generator=True; source_link=True; manifests=1 |
| 07_no_changed_workload_parameters | PASS | none |
| 08_three_trials_per_condition | PASS | groups=12; bad_groups={} |
| 09_lambda_quota_limitation_disclosed | PASS | section_7_4=True; prohibited_claims=[] |
| 10_closed_loop_locust_behavior_disclosed | PASS | closed_loop=True; achieved_throughput=True; fixed_offered_caution=True |
| 11_cost_assumptions_disclosed | PASS | missing_tokens=[] |
| 12_research_questions_answered | PASS | rq_intro=True; rq_answers=True; answer_section=True |
| 13_conclusions_supported_by_data | PASS | EC2_lower_cost_workloads=6/6; EC2_not_worse_reliability=6/6; W04_W05_burst_support=True; W06_mixed=True; conclusion_text_ok=True |
| 14_no_contradictions_text_vs_csv | PASS | none |

## Interpretation

All automated scientific-integrity checks passed. This audit confirms internal repository/data/paper consistency under the explicit checks implemented here; it does not replace external peer review.
