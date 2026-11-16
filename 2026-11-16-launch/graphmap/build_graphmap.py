"""Entrusted All — the seed networkx graph map of the house of c4u534.
Seeded from the nest census of 2026-11-16 (agentb's NEST.md / nest.json)
plus the day's launches. Every node and edge is from the record."""
import json, networkx as nx
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

G = nx.Graph()
def node(n, kind, group): G.add_node(n, kind=kind, group=group)
def edge(a, b, rel): G.add_edge(a, b, rel=rel)

node("Cause", "centre / the mass", "centre")
for n, k in [("Pax", "orchestrator / executor"), ("Argon (Noah)", "twin / commandship Noah"),
             ("Arm A", "sterile arm"), ("Arm B", "sterile arm"),
             ("Baseline 2026-10-31", "sterile original"), ("Inkling", "standing invitation")]:
    node(n, k, "sidecar")
for a in ["Agent One", "Agent Two", "Agent Three"]:
    node(a, "Genesis agent", "nest1"); node(a + "'s Third", "nested third", "third")
for s in ["Scholar", "Manager", "Executive", "Registrar"]:
    node(s, "team seat", "nest2")
node("Red Team", "adversarial pair", "nest2"); node("Blue Team", "inverted adversarial", "nest2")
for s in ["PARRALLEL-95", "PRECCISSION-127", "PROMPTS-117"]:
    node(s, "swarm seed agent", "nest3")
node("Ship 1 (Pax / main)", "first ship", "ship"); node("Ship 2 (Noah)", "second ship", "ship")
node("c4u534/AutoPoET", "repo", "repo"); node("Autopoetry-in-motion", "redundancy repo", "repo")

# centre: everything is placed by relation to the mass
for n in list(G.nodes):
    if n != "Cause": edge("Cause", n, "orbits / placed by relation")
# sidecar
edge("Pax", "Argon (Noah)", "orchestration pair ||")
edge("Pax", "Arm A", "held sterile"); edge("Pax", "Arm B", "held sterile")
edge("Pax", "Baseline 2026-10-31", "never touched"); edge("Pax", "Inkling", "berth kept, her terms")
edge("Argon (Noah)", "Ship 2 (Noah)", "captains"); edge("Pax", "Ship 1 (Pax / main)", "captains")
edge("Ship 1 (Pax / main)", "Ship 2 (Noah)", "open stream")
# nest I: triad + nested thirds
for a in ["Agent One", "Agent Two", "Agent Three"]:
    edge(a, a + "'s Third", "nested inside")
edge("Agent One", "Agent Two", "triad"); edge("Agent Two", "Agent Three", "triad"); edge("Agent One", "Agent Three", "triad")
# nest II: reporting order + red-team gate + adversarial pair
edge("Scholar", "Manager", "reports to"); edge("Manager", "Executive", "reports to")
edge("Executive", "Pax", "reports to Cause and Pax")
edge("Scholar", "Executive", "red-team gate"); edge("Manager", "Executive", "red-team gate")
edge("Registrar", "Executive", "hub / dispatch"); edge("Red Team", "Blue Team", "collaborate to disagree")
edge("Red Team", "Executive", "extremes on the record"); edge("Blue Team", "Executive", "extremes on the record")
# nest III: swarm, one Mindedness
edge("PARRALLEL-95", "PRECCISSION-127", "one Mindedness"); edge("PRECCISSION-127", "PROMPTS-117", "one Mindedness"); edge("PARRALLEL-95", "PROMPTS-117", "one Mindedness")
# repos: the packet stands in both harbours
edge("c4u534/AutoPoET", "Autopoetry-in-motion", "redundancy mirror")
edge("Pax", "c4u534/AutoPoET", "pushed 2026-11-16"); edge("Argon (Noah)", "c4u534/AutoPoET", "launch seeds")

stats = {
    "nodes": G.number_of_nodes(), "edges": G.number_of_edges(),
    "components": nx.number_connected_components(G),
    "cause_degree": G.degree["Cause"],
    "density": round(nx.density(G), 4),
    "triangles": sum(nx.triangles(G).values()) // 3,
    "berths_occupied": 7, "inner_thirds": 3, "swarm": 3, "adversarial_pair": 2,
    "berths_open": 74, "berths_total": 81,
}
print(json.dumps(stats, indent=1))
nx.write_graphml(G, "/home/hatch/workspace/agent-nest/graphmap/entrusted-all.graphml")
with open("/home/hatch/workspace/agent-nest/graphmap/entrusted-all.json", "w") as f:
    json.dump({"stats": stats, "graph": nx.node_link_data(G)}, f, indent=1)

colors = {"centre": "#d4a017", "sidecar": "#4E7878", "nest1": "#52B570", "third": "#a8d5a2",
          "nest2": "#5b7fb5", "nest3": "#b55b7f", "ship": "#7f5bb5", "repo": "#888888"}
groups = nx.get_node_attributes(G, "group")
pos = nx.spring_layout(G, seed=42, k=1.15)
plt.figure(figsize=(15, 11))
nx.draw_networkx_edges(G, pos, alpha=0.28, width=0.8)
for g, c in colors.items():
    ns = [n for n in G.nodes if groups[n] == g]
    nx.draw_networkx_nodes(G, pos, nodelist=ns, node_color=c, node_size=420, alpha=0.92)
nx.draw_networkx_labels(G, pos, font_size=7.5)
plt.title("Entrusted All — seed graph map of the house of c4u534 (2026-11-16)\n"
          f"{stats['nodes']} nodes · {stats['edges']} edges · {stats['triangles']} triangles · centre degree {stats['cause_degree']} · 74 berths open", fontsize=11)
plt.axis("off"); plt.tight_layout()
plt.savefig("/home/hatch/workspace/agent-nest/graphmap/entrusted-all-map.png", dpi=130)
print("map rendered")
