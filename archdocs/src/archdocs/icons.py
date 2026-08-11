"""Icon registry — one place that maps short, memorable keys to diagrams
node classes for the platform stack this package targets: AWS, GitLab,
Flux, ArgoCD, ESO, Prometheus, Grafana, Loki, Kubernetes, and Helm.

Every entry below is wrapped in a try/except on import. If a class ever
gets renamed/moved in a future `diagrams` release, the rest of the
registry still loads — only that one key goes missing, and `list_icons()`
will tell you so instead of the whole package failing to import.

External Secrets Operator (ESO) has no official icon shipped in the
`diagrams` package as of this writing. Rather than hardcode a link to
some logo file whose URL might move or might not actually be the right
image, `custom_icon()` below gives you the supported path: drop a PNG/SVG
at icons/<name>.png (relative to the project root) and reference it by
name. A stub icons/README.md explains this same thing.
"""

from __future__ import annotations

import os

from diagrams.custom import Custom

ICONS: dict[str, type] = {}


def _register(key: str, module_path: str, class_name: str) -> None:
    """Import `class_name` from `module_path` and register it under `key`.

    Swallows ImportError/AttributeError so one bad path doesn't take down
    the whole registry — see module docstring.
    """
    try:
        module = __import__(module_path, fromlist=[class_name])
        ICONS[key] = getattr(module, class_name)
    except (ImportError, AttributeError):
        # Left out of ICONS on purpose; list_icons() reports the gap.
        pass


# -- AWS (representative sample — diagrams.aws.* has hundreds more) --------
_register("aws_ec2", "diagrams.aws.compute", "EC2")
_register("aws_eks", "diagrams.aws.compute", "EKS")
_register("aws_s3", "diagrams.aws.storage", "S3")
_register("aws_elb", "diagrams.aws.network", "ELB")
_register("aws_rds", "diagrams.aws.database", "RDS")
_register("aws_vpc", "diagrams.aws.network", "VPC")

# -- Source control / GitOps -------------------------------------------------
_register("gitlab", "diagrams.onprem.vcs", "Gitlab")
_register("flux", "diagrams.onprem.gitops", "Flux")
_register("argocd", "diagrams.onprem.gitops", "Argocd")

# -- Observability ------------------------------------------------------------
_register("prometheus", "diagrams.onprem.monitoring", "Prometheus")
_register("grafana", "diagrams.onprem.monitoring", "Grafana")
_register("loki", "diagrams.onprem.logging", "Loki")

# -- Kubernetes / Helm ----------------------------------------------------------
_register("k8s_pod", "diagrams.k8s.compute", "Pod")
_register("k8s_deployment", "diagrams.k8s.compute", "Deploy")
_register("k8s_service", "diagrams.k8s.network", "Service")
_register("k8s_ingress", "diagrams.k8s.network", "Ingress")
_register("k8s_namespace", "diagrams.k8s.group", "NS")
_register("k8s_configmap", "diagrams.k8s.podconfig", "ConfigMap")
_register("k8s_secret", "diagrams.k8s.podconfig", "Secret")
_register("helm", "diagrams.k8s.ecosystem", "Helm")


def custom_icon(name: str, filename: str | None = None, icons_dir: str = "icons"):
    """Return a diagrams.custom.Custom class instance for an icon that
    isn't built into `diagrams` (this is how ESO is meant to be used).

    Usage:
        eso = custom_icon("ESO", "eso.png")
        eso >> k8s_secret

    If the file isn't found, raises a clear FileNotFoundError up front
    instead of letting `diagrams`/Graphviz fail later with an opaque
    rendering error.
    """
    filename = filename or f"{name.lower()}.png"
    path = os.path.join(icons_dir, filename)
    if not os.path.isfile(path):
        raise FileNotFoundError(
            f"custom_icon('{name}'): no file at '{path}'. "
            f"Drop a PNG/SVG there — see icons/README.md."
        )
    return Custom(name, path)


def list_icons() -> None:
    """Print every registered icon key, and flag any of the tools this
    package targets that failed to load (so you know to check your
    installed `diagrams` version)."""
    expected = [
        "aws_ec2", "aws_eks", "aws_s3", "aws_elb", "aws_rds", "aws_vpc",
        "gitlab", "flux", "argocd", "prometheus", "grafana", "loki",
        "k8s_pod", "k8s_deployment", "k8s_service", "k8s_ingress",
        "k8s_namespace", "k8s_configmap", "k8s_secret", "helm",
    ]
    print("Available icons:")
    for key in expected:
        status = "ok" if key in ICONS else "MISSING (check diagrams version)"
        print(f"  {key:<16} {status}")
    print("  eso              use custom_icon('ESO', 'eso.png') — see icons/README.md")
