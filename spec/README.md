# SpecKit Usage in This Repo

This `spec/` folder follows GitHub’s spec-kit conventions with high-level, implementation-agnostic documents:

- `product-spec.md` — product background, goals/non-goals, audience, user stories, requirements, success metrics, rollout, risks.
- `tech-spec.md` — proposed architecture and constraints at a system level (no code identifiers).
- `flows.md` — core end-to-end flows for text, voice, remote messaging, tools, memory, and sync.
- `llm-requirements.md` — provider-agnostic LLM capabilities and prompting/context rules.
- `data-overview.md` — conceptual entities and relationships (no table or struct names).
- `security.md` — security/privacy principles and guardrails.
- `supabase.md` — high-level integration notes and behaviors.
- `rewrite-plan.md` — scope, phases, milestones, quality bars, and branch plan for the rewrite.

How to work with these specs
- Keep both specs updated as the source of truth before major refactors.
- Link PRs to relevant sections in these docs. Include a short “Spec Impact” section in PR descriptions.
- For large features, add subsections or per-feature appendices under `spec/` and link them from the main specs.

Localization
- Current specs are in Korean. Provide an English mirror if collaborating cross‑team.

References
- Project overview: `README.md`
- Vision/Roadmap: `CONCEPT.md`, `ROADMAP.md`
- Tool schemas: `docs/built-in-tools.md`
