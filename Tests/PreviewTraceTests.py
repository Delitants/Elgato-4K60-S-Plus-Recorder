"""Validate steady 25 fps preview timing from PREVIEW_DIAGNOSTICS JSON (no media)."""
import json,sys
rows=[r for r in json.load(open(sys.argv[1])) if r[1]>7]
# Scheduled host deadlines when present; otherwise actual immediate enqueue time.
scheduled=any(r[0]==8 for r in rows)
frames=[r for r in rows if r[0]==(8 if scheduled else 5)]
assert len(frames)>100,'Need at least 100 steady-state preview frames'
times=[r[3] if scheduled else r[1] for r in frames]
errors=sorted(abs((b-a)-.04)*1000 for a,b in zip(times,times[1:]))
p95=errors[int((len(errors)-1)*.95)]
assert p95<2,f'25 fps presentation timing error p95 {p95:.2f} ms; expected <2 ms'
assert max(errors)<2,f'Preview skipped a presentation slot: maximum timing error {max(errors):.2f} ms'
print(f'PASS 25 fps presentation timing error p95 {p95:.3f} ms across {len(frames)} frames')
