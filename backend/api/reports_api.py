"""
API endpoints for advanced reporting and statistical analysis.
Integrate with app.py to enable research-grade report generation.
"""

from flask import Blueprint, jsonify
import json

from model_evaluation import generate_comprehensive_report
from statistical_analysis import (
    paired_ttest_with_ci, mann_whitney_u_test, improvement_percentage_with_ci,
    generate_clinical_stats_summary
)
from database import get_db
from utils.paths import get_reports_dir

# Create blueprint for reports
reports_bp = Blueprint("reports", __name__, url_prefix="/api/reports")

@reports_bp.route("/model_evaluation", methods=["GET"])
def get_model_evaluation():
    """
    Generate or retrieve comprehensive model evaluation report.
    
    Returns:
        JSON with accuracy, precision, recall, F1, cross-validation results,
        feature importance rankings, and more.
    """
    try:
        # Check if recent evaluation exists
        report_path = get_reports_dir() / "model_evaluation_report.json"
        
        if report_path.exists():
            with open(report_path, "r") as f:
                report = json.load(f)
            
            return jsonify({
                "status": "success",
                "report": report,
                "message": "Model evaluation report"
            })
        else:
            # Generate new report
            report = generate_comprehensive_report()
            
            return jsonify({
                "status": "success",
                "report": report,
                "message": "Model evaluation report generated"
            })
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"Failed to generate evaluation report: {str(e)}"
        }), 500


@reports_bp.route("/assessment_comparison/<int:child_id>", methods=["GET"])
def get_assessment_comparison(child_id: int):
    """
    Generate statistical comparison between two assessments (pre vs post).
    
    Returns:
        Paired t-test results, effect sizes, confidence intervals, significance.
    """
    try:
        with get_db() as conn:
            cur = conn.cursor()
            
            # Get pre and post assessments
            cur.execute(
                """SELECT a.id, a.type, a.memory_score, a.attention_score, a.language_score
                   FROM assessments a
                   WHERE a.child_id = ? AND a.status = 'completed'
                   ORDER BY a.created_at ASC
                   LIMIT 2""",
                (child_id,)
            )
            assessments = cur.fetchall()
        
        if len(assessments) < 2:
            return jsonify({
                "status": "error",
                "message": "Need at least 2 completed assessments for comparison"
            }), 400
        
        pre = assessments[0]
        post = assessments[1]
        
        # Memory analysis
        import numpy as np
        pre_memory = np.array([pre["memory_score"] or 0])
        post_memory = np.array([post["memory_score"] or 0])
        
        # For single sample comparisons, use simpler statistics
        memory_change = float(post["memory_score"] - pre["memory_score"])
        attention_change = float(post["attention_score"] - pre["attention_score"])
        language_change = float(post["language_score"] - pre["language_score"])
        
        # Clinical summary
        clinical_summary = generate_clinical_stats_summary(
            {"memory": pre["memory_score"], "attention": pre["attention_score"], "language": pre["language_score"]},
            {"memory": post["memory_score"], "attention": post["attention_score"], "language": post["language_score"]}
        )
        
        return jsonify({
            "status": "success",
            "child_id": child_id,
            "pre_assessment": {
                "type": pre["type"],
                "memory_score": pre["memory_score"],
                "attention_score": pre["attention_score"],
                "language_score": pre["language_score"],
            },
            "post_assessment": {
                "type": post["type"],
                "memory_score": post["memory_score"],
                "attention_score": post["attention_score"],
                "language_score": post["language_score"],
            },
            "changes": {
                "memory": memory_change,
                "attention": attention_change,
                "language": language_change,
                "average": (memory_change + attention_change + language_change) / 3
            },
            "interpretation": "improved" if memory_change > 3 else ("declined" if memory_change < -3 else "stable"),
            "clinical_summary": clinical_summary
        })
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"Failed to generate comparison: {str(e)}"
        }), 500


@reports_bp.route("/longitudinal_progress/<int:child_id>", methods=["GET"])
def get_longitudinal_progress(child_id: int):
    """
    Generate long-term progress report with trend analysis.
    
    Shows improvement trajectory over multiple assessments.
    """
    try:
        with get_db() as conn:
            cur = conn.cursor()
            cur.execute(
                """SELECT a.created_at, a.memory_score, a.attention_score, a.language_score, a.type
                   FROM assessments a
                   WHERE a.child_id = ? AND a.status = 'completed'
                   ORDER BY a.created_at ASC""",
                (child_id,)
            )
            assessments = cur.fetchall()
        
        if len(assessments) < 2:
            return jsonify({
                "status": "error",
                "message": "Need at least 2 assessments for longitudinal analysis"
            }), 400
        
        # Calculate trends
        import numpy as np
        dates = [a["created_at"] for a in assessments]
        memory_scores = [a["memory_score"] for a in assessments]
        attention_scores = [a["attention_score"] for a in assessments]
        language_scores = [a["language_score"] for a in assessments]
        
        x = np.arange(len(assessments))
        
        # Linear regression for trend
        def get_trend(scores):
            if len(scores) < 2:
                return 0
            scores = np.array(scores, dtype=float)
            z = np.polyfit(x, scores, 1)
            return float(z[0])  # slope
        
        memory_trend = get_trend(memory_scores)
        attention_trend = get_trend(attention_scores)
        language_trend = get_trend(language_scores)
        
        return jsonify({
            "status": "success",
            "child_id": child_id,
            "num_assessments": len(assessments),
            "assessments": [
                {
                    "date": a["created_at"],
                    "type": a["type"],
                    "memory": a["memory_score"],
                    "attention": a["attention_score"],
                    "language": a["language_score"],
                }
                for a in assessments
            ],
            "trend_analysis": {
                "memory_trend": memory_trend,
                "attention_trend": attention_trend,
                "language_trend": language_trend,
                "interpretation": "Positive trends indicate improvement over time; negative trends indicate decline."
            },
            "overall_progress": {
                "initial_average": float(np.mean([memory_scores[0], attention_scores[0], language_scores[0]])),
                "final_average": float(np.mean([memory_scores[-1], attention_scores[-1], language_scores[-1]])),
                "total_improvement": float(np.mean([memory_scores[-1], attention_scores[-1], language_scores[-1]]) - 
                                         np.mean([memory_scores[0], attention_scores[0], language_scores[0]]))
            }
        })
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"Failed to generate longitudinal report: {str(e)}"
        }), 500


@reports_bp.route("/feature_importance", methods=["GET"])
def get_feature_importance():
    """
    Retrieve EEG feature importance rankings.
    
    Shows which brain signal features are most predictive of cognitive load.
    """
    try:
        report_path = get_reports_dir() / "model_evaluation_report.json"
        
        if not report_path.exists():
            return jsonify({
                "status": "error",
                "message": "Model evaluation report not found. Run model evaluation first."
            }), 404
        
        with open(report_path, "r") as f:
            report = json.load(f)
        
        importance_data = report.get("classification_model", {}).get("feature_importance", {})
        
        return jsonify({
            "status": "success",
            "feature_importance": importance_data,
            "message": "EEG feature importance rankings"
        })
    
    except Exception as e:
        return jsonify({
            "status": "error",
            "message": f"Failed to retrieve feature importance: {str(e)}"
        }), 500


# Export blueprint to be registered in main app
__all__ = ["reports_bp"]
