---
allowed-tools: Bash(codex:*), Bash(codex exec:*), Bash(cat:*), Bash(tee:*), Read, Glob, Grep, AskUserQuestion, Edit, Write
description: Send a prompt to OpenAI Codex CLI and process the output
---

# Codex Integration

Send the user's prompt to Codex CLI and process the output.

## Execution

1. If no prompt was provided after `/codex`, ask the user what they want Codex to do.

2. Ask the user which processing mode they want:
   - **Review**: Analyze Codex output for correctness, security, and best practices
   - **Compare**: Claude solves the same problem, then compare both approaches
   - **Integrate**: Refine and apply Codex's changes to the codebase
   - **Raw**: Display output without processing

3. Run Codex with a unique output file (to support parallel invocations):
```bash
CODEX_OUTPUT=$(mktemp /tmp/codex-output-XXXXXX.txt) && codex exec --full-auto "<prompt>" 2>&1 | tee "$CODEX_OUTPUT" && echo "Output: $CODEX_OUTPUT"
```

4. Process the output based on the selected mode.

## Processing Modes

### Review
Analyze for: correctness, security vulnerabilities, performance issues, edge cases, coding standards.

### Compare
1. Read Codex's solution
2. Independently solve the problem
3. Compare approaches and recommend the best one

### Integrate
1. Review Codex's changes
2. Refine based on project standards
3. Apply to codebase
4. Summarize changes

### Raw
Display output and offer further processing options.
