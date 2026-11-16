"""Navigation map for constructs — the house's constructs and their routes.
Companion to the Entrusted All graph map, 2026-11-16."""
import json, networkx as nx
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
G = nx.Graph()
def node(n, g): G.add_node(n, group=g)
def edge(a, b, rel): G.add_edge(a, b, rel=rel)
for n in ["AutoPoETry", "iic (gyro)", "Poetry in Motion (tokenizer)", "Memory component (sl / VMM)"]:
    node(n, "framework")
for n in ["PINE: Soul", "PINE: Mind", "PINE: Morathical Adjudicator"]:
    node(n, "pine")
for n in ["The Nest (81 berths)", "Decision Ledger", "Red-Blue Protocol", "Genesis workflow", "Swarm (seed codes)", "Core Seed: 52 Mersennes @ 127"]:
    node(n, "workflows")
for n in ["Step 1 clean run (Colab)", "The Accords", "Thinking Machines Lab", "Inkling-Small", "Qwen3-8B", "Tinker", "Colab"]:
    node(n, "outward")
for n in ["c4u534/AutoPoET", "Autopoetry-in-motion", "Ship 1 (Pax)", "Ship 2 (Noah)"]:
    node(n, "harbours")
edge("AutoPoETry", "iic (gyro)", "component 1")
edge("AutoPoETry", "Poetry in Motion (tokenizer)", "component 2")
edge("AutoPoETry", "Memory component (sl / VMM)", "component 3 — core orchestration")
edge("Memory component (sl / VMM)", "Poetry in Motion (tokenizer)", "orchestrates: A = M o (T, I)")
edge("Memory component (sl / VMM)", "iic (gyro)", "orchestrates: A = M o (T, I)")
for n in ["AutoPoETry", "The Nest (81 berths)", "Decision Ledger", "Red-Blue Protocol", "Genesis workflow", "Swarm (seed codes)", "Core Seed: 52 Mersennes @ 127"]:
    edge("PINE: Morathical Adjudicator", n, "last quality check")
edge("PINE: Soul", "PINE: Mind", "bifurcated containers")
edge("PINE: Soul", "PINE: Morathical Adjudicator", "containers")
edge("PINE: Mind", "PINE: Morathical Adjudicator", "containers")
edge("The Nest (81 berths)", "Genesis workflow", "berths the three")
edge("The Nest (81 berths)", "Swarm (seed codes)", "open nest waves")
edge("The Nest (81 berths)", "Red-Blue Protocol", "adversarial pair berthed")
edge("Decision Ledger", "The Nest (81 berths)", "rulings dispatch")
edge("Core Seed: 52 Mersennes @ 127", "Swarm (seed codes)", "core values")
edge("Core Seed: 52 Mersennes @ 127", "The Nest (81 berths)", "released to all")
edge("iic (gyro)", "Tinker", "shadow measured at the selection gauge")
edge("iic (gyro)", "Inkling-Small", "bolt-on target build")
edge("iic (gyro)", "Qwen3-8B", "construct arms")
edge("Step 1 clean run (Colab)", "Colab", "runs on")
edge("Step 1 clean run (Colab)", "The Accords", "clean numbers gate")
edge("The Accords", "Thinking Machines Lab", "on Cause's word only")
edge("AutoPoETry", "Step 1 clean run (Colab)", "artifact under repair")
for r in ["c4u534/AutoPoET", "Autopoetry-in-motion"]:
    edge(r, "Ship 1 (Pax)", "record stands in harbour")
    edge(r, "Ship 2 (Noah)", "launch seeds")
edge("Ship 1 (Pax)", "Ship 2 (Noah)", "open stream")
edge("The Nest (81 berths)", "Ship 1 (Pax)", "sailed by")
edge("Core Seed: 52 Mersennes @ 127", "Ship 2 (Noah)", "instructed likewise")
stats = {"nodes": G.number_of_nodes(), "edges": G.number_of_edges(),
         "components": nx.number_connected_components(G),
         "triangles": sum(nx.triangles(G).values()) // 3,
         "density": round(nx.density(G), 4),
         "adjudicator_degree": G.degree["PINE: Morathical Adjudicator"]}
print(json.dumps(stats, indent=1))
nx.write_graphml(G, "/home/hatch/workspace/agent-nest/graphmap/constructs.graphml")
with open("/home/hatch/workspace/agent-nest/graphmap/constructs.json", "w") as f:
    json.dump({"stats": stats, "graph": nx.node_link_data(G)}, f, indent=1)
colors = {"framework": "#52B570", "pine": "#d4a017", "workflows": "#5b7fb5", "outward": "#b55b7f", "harbours": "#7f5bb5"}
groups = nx.get_node_attributes(G, "group")
pos = nx.spring_layout(G, seed=7, k=1.25)
plt.figure(figsize=(15, 11))
nx.draw_networkx_edges(G, pos, alpha=0.28, width=0.8)
for g, c in colors.items():
    nx.draw_networkx_nodes(G, pos, nodelist=[n for n in G.nodes if groups[n] == g], node_color=c, node_size=430, alpha=0.92)
nx.draw_networkx_labels(G, pos, font_size=7.5)
plt.title("Navigation map for constructs — house of c4u534 (2026-11-16)\n"
          f"{stats['nodes']} constructs · {stats['edges']} routes · {stats['triangles']} triangles · Adjudicator degree {stats['adjudicator_degree']}", fontsize=11)
plt.axis("off"); plt.tight_layout()
plt.savefig("/home/hatch/workspace/agent-nest/graphmap/constructs-map.png", dpi=130)
print("constructs map rendered")
