"""Local-LLM harness for Homer's LOTR.

Offloads bulk prose generation and mechanical triage to a Gemma 4 Ollama server
on the LAN. All task logic is predefined in `bin/llm/tasks/` so that running a
task costs no agent tokens at all -- see CLAUDE-llm-harness.md.
"""
