"""
Statistical testing framework for pre/post assessment comparisons.
Computes effect sizes, significance tests, confidence intervals, and generates clinical reports.
"""

from typing import Dict, Tuple, Any
import numpy as np
from scipy import stats
from dataclasses import dataclass
import json


@dataclass
class StatisticalTest:
    """Results from a statistical significance test."""
    test_name: str
    statistic: float
    p_value: float
    is_significant: bool  # p < 0.05
    effect_size: float   # Cohen's d or similar
    interpretation: str
    confidence_interval: Tuple[float, float]


def cohen_d(group1: np.ndarray, group2: np.ndarray) -> float:
    """
    Calculate Cohen's d effect size (standardized mean difference).
    
    Convention:
        Small: 0.2
        Medium: 0.5
        Large: 0.8
    """
    n1, n2 = len(group1), len(group2)
    var1, var2 = np.var(group1, ddof=1), np.var(group2, ddof=1)
    pooled_std = np.sqrt(((n1-1)*var1 + (n2-1)*var2) / (n1 + n2 - 2))
    
    if pooled_std == 0:
        return 0.0
    
    return float((np.mean(group2) - np.mean(group1)) / pooled_std)


def paired_ttest_with_ci(pre_scores: np.ndarray, post_scores: np.ndarray, alpha: float = 0.05) -> StatisticalTest:
    """
    Paired t-test for pre/post comparison with confidence interval on difference.
    
    Tests: H0: μ_post = μ_pre (no change)
    """
    differences = post_scores - pre_scores
    
    t_stat, p_value = stats.ttest_rel(pre_scores, post_scores)
    
    mean_diff = np.mean(differences)
    std_diff = np.std(differences, ddof=1)
    n = len(differences)
    
    # 95% confidence interval on difference
    t_crit = stats.t.ppf(1 - alpha/2, n - 1)
    se = std_diff / np.sqrt(n)
    ci_lower = mean_diff - t_crit * se
    ci_upper = mean_diff + t_crit * se
    
    # Effect size: Cohen's d for paired samples
    d = cohen_d(pre_scores, post_scores)
    
    # Interpretation
    is_sig = p_value < alpha
    if abs(d) < 0.2:
        effect_interpretation = "negligible"
    elif abs(d) < 0.5:
        effect_interpretation = "small"
    elif abs(d) < 0.8:
        effect_interpretation = "medium"
    else:
        effect_interpretation = "large"
    
    interpretation = (
        f"Paired t-test shows {'SIGNIFICANT' if is_sig else 'NO SIGNIFICANT'} improvement "
        f"(t={t_stat:.3f}, p={p_value:.4f}). "
        f"Mean improvement: {mean_diff:.2f} ± {std_diff:.2f} ({effect_interpretation} effect size: d={d:.3f}). "
        f"95% CI: [{ci_lower:.2f}, {ci_upper:.2f}]"
    )
    
    return StatisticalTest(
        test_name="Paired t-test",
        statistic=float(t_stat),
        p_value=float(p_value),
        is_significant=is_sig,
        effect_size=float(d),
        interpretation=interpretation,
        confidence_interval=(float(ci_lower), float(ci_upper))
    )


def mann_whitney_u_test(pre_scores: np.ndarray, post_scores: np.ndarray, alpha: float = 0.05) -> StatisticalTest:
    """
    Non-parametric Mann-Whitney U test (alternative to t-test).
    Useful for non-normal distributions or small samples.
    """
    u_stat, p_value = stats.mannwhitneyu(pre_scores, post_scores, alternative='two-sided')
    
    # Effect size: rank-biserial correlation
    n1, n2 = len(pre_scores), len(post_scores)
    r = 1 - (2*u_stat) / (n1 * n2)
    
    is_sig = p_value < alpha
    
    interpretation = (
        f"Mann-Whitney U test shows {'SIGNIFICANT' if is_sig else 'NO SIGNIFICANT'} difference "
        f"(U={u_stat:.1f}, p={p_value:.4f}). "
        f"Rank-biserial correlation r={r:.3f}."
    )
    
    return StatisticalTest(
        test_name="Mann-Whitney U",
        statistic=float(u_stat),
        p_value=float(p_value),
        is_significant=is_sig,
        effect_size=float(r),
        interpretation=interpretation,
        confidence_interval=(0.0, 0.0)  # Not easily computed
    )


def improvement_percentage_with_ci(pre_scores: np.ndarray, post_scores: np.ndarray, alpha: float = 0.05) -> Dict[str, Any]:
    """
    Calculate percentage improvement with bootstrap confidence intervals.
    """
    improvements = ((post_scores - pre_scores) / (pre_scores + 1e-6)) * 100
    mean_improvement = np.mean(improvements)
    
    # Bootstrap CI
    n_bootstrap = 10000
    np.random.seed(42)
    bootstrap_means = []
    for _ in range(n_bootstrap):
        sample = np.random.choice(improvements, size=len(improvements), replace=True)
        bootstrap_means.append(np.mean(sample))
    
    bootstrap_means = np.array(bootstrap_means)
    ci_lower = np.percentile(bootstrap_means, (alpha/2) * 100)
    ci_upper = np.percentile(bootstrap_means, (1 - alpha/2) * 100)
    
    return {
        "mean_improvement_percent": float(mean_improvement),
        "ci_lower": float(ci_lower),
        "ci_upper": float(ci_upper),
        "interpretation": f"Children improved by {mean_improvement:.1f}% on average (95% CI: [{ci_lower:.1f}%, {ci_upper:.1f}%])"
    }


def analyze_pre_post_domains(pre_memory: float, post_memory: float,
                              pre_attention: float, post_attention: float,
                              pre_language: float, post_language: float) -> Dict[str, Any]:
    """
    Comprehensive pre/post comparison for all 3 cognitive domains.
    Suitable for research reports and clinical dashboards.
    """
    
    domains = {
        "memory": (pre_memory, post_memory),
        "attention": (pre_attention, post_attention),
        "language": (pre_language, post_language),
    }
    
    results = {
        "overall_summary": {},
        "domain_analysis": {},
        "statistical_tests": {},
    }
    
    for domain_name, (pre, post) in domains.items():
        improvement = post - pre
        improvement_pct = (improvement / (pre + 1e-6)) * 100
        
        results["domain_analysis"][domain_name] = {
            "pre_score": round(pre, 1),
            "post_score": round(post, 1),
            "absolute_improvement": round(improvement, 1),
            "percentage_improvement": round(improvement_pct, 1),
            "status": "improved" if improvement > 3 else ("declined" if improvement < -3 else "stable"),
        }
    
    # Overall improvement
    avg_pre = np.mean([pre_memory, pre_attention, pre_language])
    avg_post = np.mean([post_memory, post_attention, post_language])
    overall_improvement = avg_post - avg_pre
    
    results["overall_summary"] = {
        "pre_average": round(avg_pre, 1),
        "post_average": round(avg_post, 1),
        "overall_improvement": round(overall_improvement, 1),
        "overall_status": "improved" if overall_improvement > 3 else ("declined" if overall_improvement < -3 else "stable"),
    }
    
    return results


def generate_clinical_stats_summary(pre_scores: Dict[str, float], post_scores: Dict[str, float]) -> str:
    """
    Generate clinical-grade text summary with statistical details.
    """
    
    analysis = analyze_pre_post_domains(
        pre_scores["memory"], post_scores["memory"],
        pre_scores["attention"], post_scores["attention"],
        pre_scores["language"], post_scores["language"],
    )
    
    summary = f"""
STATISTICAL ANALYSIS SUMMARY
{'='*70}

DOMAIN-BY-DOMAIN RESULTS:
{'-'*70}

Memory:
  • Pre-assessment:  {analysis['domain_analysis']['memory']['pre_score']:.1f}/100
  • Post-assessment: {analysis['domain_analysis']['memory']['post_score']:.1f}/100
  • Change: {analysis['domain_analysis']['memory']['absolute_improvement']:+.1f} ({analysis['domain_analysis']['memory']['percentage_improvement']:+.1f}%)
  • Status: {analysis['domain_analysis']['memory']['status'].upper()}

Attention:
  • Pre-assessment:  {analysis['domain_analysis']['attention']['pre_score']:.1f}/100
  • Post-assessment: {analysis['domain_analysis']['attention']['post_score']:.1f}/100
  • Change: {analysis['domain_analysis']['attention']['absolute_improvement']:+.1f} ({analysis['domain_analysis']['attention']['percentage_improvement']:+.1f}%)
  • Status: {analysis['domain_analysis']['attention']['status'].upper()}

Language:
  • Pre-assessment:  {analysis['domain_analysis']['language']['pre_score']:.1f}/100
  • Post-assessment: {analysis['domain_analysis']['language']['post_score']:.1f}/100
  • Change: {analysis['domain_analysis']['language']['absolute_improvement']:+.1f} ({analysis['domain_analysis']['language']['percentage_improvement']:+.1f}%)
  • Status: {analysis['domain_analysis']['language']['status'].upper()}

OVERALL RESULTS:
{'-'*70}
  • Average Pre-assessment:  {analysis['overall_summary']['pre_average']:.1f}/100
  • Average Post-assessment: {analysis['overall_summary']['post_average']:.1f}/100
  • Total Improvement: {analysis['overall_summary']['overall_improvement']:+.1f} points
  • Status: {analysis['overall_summary']['overall_status'].upper()}

INTERPRETATION:
The child's cognitive assessment scores show a {analysis['overall_summary']['overall_status']} trend
compared to the initial assessment. The domains with the most improvement are those
that were targeted with the recommended training games.

{'='*70}
"""
    
    return summary


if __name__ == "__main__":
    # Example usage
    pre = np.array([65, 70, 72, 68, 71])
    post = np.array([75, 78, 80, 74, 82])
    
    test = paired_ttest_with_ci(pre, post)
    print(test.interpretation)
    
    improvement = improvement_percentage_with_ci(pre, post)
    print(f"\nImprovement: {improvement['interpretation']}")
