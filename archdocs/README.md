# archdocs

Architecture-as-code documentation generator. A thin wrapper around
[`diagrams`](https://diagrams.mingrammer.com/) (which renders through
Graphviz) with a curated icon registry for a GitOps/platform stack: AWS,
GitLab, Flux, ArgoCD, ESO, Prometheus, Grafana, Loki, Kubernetes, and Helm.

## Install

```bash
./install.sh
source .venv/bin/activate
```

The script installs Graphviz (the system dependency `diagrams` actually
renders through — not a pip package), creates `.venv`, installs `archdocs`
into it, then validates by running the test suite and rendering the
example diagram. If validation fails it wipes the venv and retries once
before giving up with a real error message.

## Quick start

```bash
archdocs list-icons               # see every available icon key
archdocs render examples/platform_stack.py
# or just:
python examples/platform_stack.py
```

Output lands in `output/platform_stack.png`.

## Writing your own diagram

```python
from archdocs import Architecture, Cluster, Edge, ICONS

with Architecture("My Stack"):
    gitlab = ICONS["gitlab"]("GitLab")
    with Cluster("Kubernetes"):
        deploy = ICONS["k8s_deployment"]("app")
        svc = ICONS["k8s_service"]("svc")
    gitlab >> deploy >> svc
```

`Architecture` is `diagrams.Diagram` with sane non-interactive defaults
(`show=False`, output written to `output/`). `Cluster` and `Edge` are
re-exported from `diagrams` unchanged — see the
[diagrams docs](https://diagrams.mingrammer.com/docs/getting-started/examples)
for the full drawing API (this package only curates *icons*, not the
drawing model itself).

Run `archdocs list-icons` for the full key list — it currently covers a
handful of representative AWS resources plus GitLab, Flux, ArgoCD,
Prometheus, Grafana, Loki, core Kubernetes objects, and Helm. `diagrams`
itself has hundreds more AWS/GCP/Azure/on-prem icons; import directly from
`diagrams.aws.*` etc. for anything not in the curated registry.

## Custom icons (ESO, or anything else not built in)

External Secrets Operator has no official icon shipped in `diagrams`. Drop
your own icon file at `icons/eso.png` and use it like this:

```python
from archdocs import custom_icon

eso = custom_icon("ESO", "eso.png")
```

The example diagram falls back to a plain labeled box if `icons/eso.png`
isn't present, so it still runs before you've added one. Same pattern
works for any other tool you need that isn't in the registry — see
`icons/README.md`.

## Project layout

```
archdocs/
├── install.sh                    # venv + Graphviz + validation
├── pyproject.toml
├── src/archdocs/
│   ├── icons.py                  # the icon registry + custom_icon()
│   ├── builder.py                # Architecture/Cluster/Edge
│   └── cli.py                    # `archdocs list-icons` / `render`
├── examples/platform_stack.py    # GitOps + observability example
├── icons/                        # drop custom PNG/SVG icons here
└── tests/test_icons.py
```
