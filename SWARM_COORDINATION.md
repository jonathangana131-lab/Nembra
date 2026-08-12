# Historical Nembra Swarm Coordination (V14)

**STATUS: RETIRED — DO NOT USE FOR CURRENT WORKER ROUTING**

V14’s useful principles—avoid duplicate work, reassign instead of polling scarce gates, prefer coherent product closure, preserve physical truth, and continue after a checkpoint—are incorporated into **Nembra Swarm V16: Mission Graph**.

Current operational sources of truth:

1. `docs/SWARM_CONTROL_PLANE.md` — canonical V16 architecture, mission graph, migration, safety, recovery, integration, and operator commands.
2. `SWARM_GO.md` — canonical fresh-worker `Go` loop.
3. Current GitHub product/CI truth and V16 structured state.

Do not route new work using V14 flat feature-gravity lists or branch/lane heuristics. During migration, legacy lane state may still be read as historical/compatibility input, but V16 objectives, blocker ownership, canonical branch selection, duplicate suppression, and Merge Train state organize new work.
