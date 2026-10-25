# Invariants

- Keep provider-specific executables, arguments, stores, models, and callbacks behind `agnostic-llm-providers` and `agnostic-llm--provider-get`.
- Resolve project roots through `agnostic-llm--project-root`; honor explicit buffer-local roots and never treat the home directory as a project.
- Construct and recognize session buffers through the centralized `*llm:` prefix helpers.
- Identify named sessions by provider, project root, and canonical name; introduce the role once.
- Route prompt and annotation storage through `agnostic-llm--persistence-dir`.
- Capture each bubble's provider, root, session, model, effort, and permission posture buffer-locally when it opens.
- Preserve incomplete JSONL fragments between process-filter calls and tolerate malformed or partially written transcript lines.
- Shell-quote provider commands and launch them through the configured login shell.

Evidence and failure modes are documented in [docs/invariants.org](docs/invariants.org).
