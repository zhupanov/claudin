---
name: loop-halt-rate
description: "Throwaway fixture skill used by scripts/test-loop-improve-skill-halt-rate.sh. Deliberately minimal so /skill-judge consistently grades below A and /loop-improve-skill iterates for halt-rate measurement."
---

# loop-halt-rate (fixture)

Greet the user once. This fixture is intentionally skeletal — it lacks the structure, mechanical rules, and progress reporting a real larch skill carries. `/skill-judge` will consistently grade it well below A, causing `/loop-improve-skill` to iterate, which is exactly what the halt-rate harness needs to exercise the Step-3.j halt surface.

## Step 1

Print "hello" once.
