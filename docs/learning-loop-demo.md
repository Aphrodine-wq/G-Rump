# Learning Loop — 5-minute demo

The loop: **act → observe → distill → persist → apply**. Everything it learns is
visible, attributed, and reversible.

## 1. Watch a lesson get born

1. Open a project and give G-Rump a task that fails once before succeeding
   (e.g. a build with a missing generate step).
2. After the run, a chat notice appears: `Learning: saved 1 lesson…`
   (toggle in Settings → Brain → Learning).
3. Open the **Learning panel** (graduation cap in the right dock) → Lessons:
   the new lesson shows a 50% confidence bar (Laplace prior — no track record yet).

## 2. Watch it ride along and earn confidence

4. Ask for a similar task. The lesson injects into the system prompt
   (`## Learned Lessons` block, top 5 by relevance × confidence).
5. Success → the lesson's win count and bar go up. Say "that's wrong" instead →
   the run is amended in Outcomes and the lesson takes the loss.
6. Lessons that keep losing auto-retire at <30% confidence after 5 rides.

## 3. Watch it propose a skill

7. Once ≥3 lessons cluster around one workflow, reflection may emit a proposal —
   the Learning tab badges, and the Proposals tab shows a **unified diff** of the
   SKILL.md it wants to write, with rationale and the source lessons.
8. **Approve & Enable** writes the skill and turns it on. **Reject** is remembered
   forever — it will never be re-proposed.
9. There is no other path: the agent cannot write SKILL.md, SOUL.md, or MIND.md
   through file tools without an explicit approval prompt.

## 4. Watch the daemon get pickier

10. Queue goals via the `add_goal` tool (or vault `Goals/`). The daemon scores
    `priority + 2 × success-rate` per task type, parks types it keeps failing as
    `needs-attention`, and reflects after every goal.

Manual controls: `reflect` tool for an on-demand pass · pin/retire/edit any
lesson in the panel · the whole loop switches off in Settings → Brain → Learning.
