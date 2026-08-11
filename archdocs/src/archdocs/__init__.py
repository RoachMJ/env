"""archdocs — architecture-as-code documentation generator.

Thin, opinionated wrapper around mingrammer/diagrams for building platform
architecture diagrams (AWS + GitOps + Kubernetes + observability stacks)
as plain Python.
"""

from archdocs.builder import Architecture, Cluster, Edge
from archdocs.icons import ICONS, custom_icon, list_icons

__all__ = [
    "Architecture",
    "Cluster",
    "Edge",
    "ICONS",
    "custom_icon",
    "list_icons",
]

__version__ = "0.1.0"
