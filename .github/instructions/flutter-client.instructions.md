---
description: "Use when editing Flutter client code in neuro_ai_cognitive_app/lib/**/*.dart, including screens, engine logic, and API calls. Preserves service-screen-engine boundaries and backend compatibility expectations."
name: "Flutter Client Boundaries"
applyTo: "neuro_ai_cognitive_app/lib/**/*.dart"
---
# Flutter Client Boundaries

## Scope
- Apply these rules for Flutter app changes in neuro_ai_cognitive_app/lib/.
- Keep current architecture split: services for API calls, engine for task logic, screens/widgets for UI.

## Architectural Boundaries
- Do not move business or scoring logic into UI widgets.
- Keep HTTP and payload logic in lib/services/api_service.dart.
- Keep task generation and behavioral feature logic in lib/engine/.

## Backend Contract Expectations
- Preserve compatibility with backend request payload keys and expected response fields.
- Prefer compile-time endpoint overrides using --dart-define=API_BASE_URL=... over hardcoded host changes.
- Respect platform-specific behavior already handled by local launcher scripts.

## Implementation Style
- Keep changes localized and minimal.
- Reuse existing enums/models/utilities instead of duplicating domain constants.
- Preserve naming and structure patterns already used in lib/screens/, lib/services/, and lib/engine/.

## Validation Checklist
- For backend + Flutter local flow: run ./run_local_dev.sh android|ios|web
- Verify key paths: login/register, child profile, assessment flow, results rendering.

## Related Docs
- See secure_deployment.md for HTTPS expectations and endpoint security.
