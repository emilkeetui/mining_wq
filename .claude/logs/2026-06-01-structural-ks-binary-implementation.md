# Session: 2026-06-01 — structural_ks_binary.r implementation

## Objective
Write `code/coal_mining_water_quality/structural_ks_binary.r` per §7 of the binary K&S proposal (2026-05-22), incorporating all §16 implications (Option C pseudo-likelihood for Eq. 4, observation-level NLS for Eq. 5, Eq. 3 demoted to diagnostic, bootstrap SEs).

## Changes Made
- `code/coal_mining_water_quality/structural_ks_binary.r`: NEW — full Eqs. 1–7 + CFs
- `output/struct/primitives_binary.rds`: NEW — all fitted objects + panel (3.6 MB)
- `output/reg/structural_eq7.tex`: NEW — EJ coefficient table (beamer-wrapped)
- `output/fig/binary_counterfactuals.png`: NEW — CF comparison bar chart

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Eq. 4 starting values: μ_intercept = mean(log_delta_e) - qnorm(1-mean(B)) | Default starts (all zeros) place optimizer in degenerate region where all Pr(B=1)→0, causing NLL >> intercept-only baseline (18623 vs 2212). This initialization ensures Pr(B=1) ≈ empirical mean at starting values. |
| Eq. 5 starting values: β_γ[0] = log(mean(θ*)), β_ψ[0] = -4 | With β_γ = 0 the model starts with γ=1 << θ*≈130, so the NLS has no gradient. Intercept at log(mean(θ*)) ≈ 4.87 gives a sensible starting FOC. β_ψ[0]=-4 → ψ≈0.018 (nearly costless). |
| F-stat via wald(fit_1, "z") not fitstat() | fitstat("ivf") only applies to 2SLS objects; Eq. 1 is OLS → use Wald test for z. |
| nlminb status 1 = acceptable | "Singular convergence" means function flat at optimum, not divergence. Only status > 1 triggers a warning. |
| Hazard winsorized at q99 | (1-F)/f diverges in the log-normal right tail (max 7e8). Winsorize prevents NLS from being dominated by a handful of extreme obs. |

## Verification Results
- [x] Script runs end-to-end without error
- [x] First-stage F = 13.6 (matches feasibility check)
- [x] phi_B = 1.151 (t=21.3), xi_B = 1.180 (t=16.7) — enforcement schedule confirmed
- [x] Eq. 4 NLL = 1981 (better than intercept-only baseline ~2212), cor(1-F̂, p̂_eq3) = 0.835
- [x] Eq. 5 converged status 0; SSR = 868
- [x] EJ headline: β_γ[mining] = -2.2e-4 (negative as expected), β_ψ[mining] = +0.32
- [x] CF2 EJ equalization: -0.37 pp, CF5 no-mining: -0.37 pp total
- [x] All three output files exist and non-zero
- [x] structural_eq7.tex compiles with beamer wrapper

## Open Questions / Findings to Investigate
- CF validation OOS cor = 0.028 (poor fit for Q4 bin) — suggests structural assumption
  may be strained at the top of the IV distribution. Worth flagging in the paper.
- β_γ[mining] ≈ 0 (displayed as "-0.000" in table) — needs bootstrap CIs to determine
  if this is statistically different from zero. May need to scale mining variable or
  report in natural units rather than log(1+mines).
- Eq. 4 status 1 (flat likelihood near optimum) — consider switching to optim(L-BFGS-B)
  or gradient-based optimization if needed for bootstrap stability.
- N_BOOT set to 500 in the production script — overnight wall-time estimate ~2-4 hrs
  depending on bootstrap iteration convergence rate.

## Next Steps
1. Run with N_BOOT=500 (overnight) to get bootstrap CIs
2. Investigate β_γ[mining] magnitude — may want to report per-mine rather than log-scale
3. Check CF validation in more detail — is Q4 OOS failure a model spec issue?
4. Add robustness: Option A (GMM) and Option B (NLS on 1-p̂) as table columns
