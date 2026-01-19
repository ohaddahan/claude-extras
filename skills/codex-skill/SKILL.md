---
name: codex
description: Send prompts to OpenAI Codex CLI and process the output. Use /codex <prompt> to invoke Codex, then Claude analyzes, reviews, or integrates the results.
user-invocable: true
allowed-tools: Bash(codex:*), Bash(cat:*), Read, Glob, Grep, AskUserQuestion, Edit, Write
---

# Codex Integration Skill

## Purpose
This skill enables a collaborative workflow between Claude and OpenAI's Codex CLI. Send prompts to Codex, capture its output, and have Claude process the results.

## How to Use
Invoke with: `/codex <your prompt here>`

If no prompt is provided, ask the user what they want Codex to do.

## Execution Flow

### Step 1: Determine the prompt
If the user provided a prompt after `/codex`, use it. Otherwise, ask them what task they want Codex to perform.

### Step 2: Ask for processing mode
Ask the user how they want Claude to process Codex's output:

1. **Review** - Analyze Codex's solution for correctness, security, performance, and best practices
2. **Compare** - Have Claude solve the same problem, then compare approaches
3. **Integrate** - Take Codex's output and integrate it into the codebase with Claude's refinements
4. **Raw** - Just show Codex's output without additional processing

### Step 3: Execute Codex
Run Codex in non-interactive mode with the user's prompt.

First, create a unique output file to avoid collisions with parallel invocations:
```bash
CODEX_OUTPUT=$(mktemp /tmp/codex-output-XXXXXX.json)
```

Then execute Codex:
```bash
codex exec --full-auto --json "<prompt>" 2>&1 | tee "$CODEX_OUTPUT"
```

Or as a single command:
```bash
CODEX_OUTPUT=$(mktemp /tmp/codex-output-XXXXXX.json) && codex exec --full-auto --json "<prompt>" 2>&1 | tee "$CODEX_OUTPUT" && echo "Output saved to: $CODEX_OUTPUT"
```

Options to consider:
- `--full-auto`: Enables automatic execution with workspace-write sandbox
- `--json`: Outputs structured JSONL for easier parsing
- `--sandbox read-only`: For safer execution when reviewing only
- `-m <model>`: Specify a different model (e.g., `o3`, `o4-mini`)

### Step 4: Process the output based on mode

#### Review Mode
1. Parse the Codex output
2. Identify any code changes or suggestions made
3. Analyze for:
   - Correctness: Does it solve the stated problem?
   - Security: Any vulnerabilities introduced?
   - Performance: Efficiency concerns?
   - Best practices: Follows project conventions?
   - Edge cases: Are they handled?
4. Provide a structured review with recommendations

#### Compare Mode
1. First, read and understand Codex's solution
2. Independently solve the same problem as Claude
3. Compare both approaches:
   - Similarities and differences
   - Trade-offs of each approach
   - Which is more maintainable/readable
   - Which handles edge cases better
4. Recommend which approach (or hybrid) to use

#### Integrate Mode
1. Parse Codex's output for code changes
2. Review the changes for quality and correctness
3. Make refinements based on:
   - Project coding standards
   - Security best practices
   - Performance optimizations
   - Better naming/structure
4. Apply the refined changes to the codebase
5. Summarize what was changed

#### Raw Mode
1. Display the Codex output directly
2. Offer to do further processing if requested

## Output Parsing
Codex `--json` output is JSONL format. Key event types:
- `message_output_item_added`: Contains agent messages and tool calls
- `message_output_item_done`: Completed items
- `response_completed`: Final response

Extract code changes from `code_interpreter` tool calls or direct file modifications.

## Error Handling
- If Codex fails to run, check that it's installed and authenticated
- If execution times out, suggest using `--sandbox read-only` or a simpler prompt
- If output is too large, summarize key points and offer to dive into specifics

## Example Invocations
- `/codex fix the type error in auth.ts`
- `/codex add input validation to the user form`
- `/codex refactor the database queries for better performance`
