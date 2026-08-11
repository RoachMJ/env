"""Thin convenience wrapper around diagrams.Diagram.

Kept intentionally small — diagrams.Cluster and diagrams.Edge are
re-exported as-is since they're already a clean API; the only thing this
module changes is Diagram's defaults (output directory, don't try to
auto-open a viewer, filename derived from the diagram name).
"""

from __future__ import annotations

import os

from diagrams import Cluster, Diagram, Edge

__all__ = ["Architecture", "Cluster", "Edge"]


class Architecture(Diagram):
    """Same as diagrams.Diagram, with defaults suited to running
    non-interactively (CI, scripts, headless boxes):

    - show=False (never tries to shell out to an image viewer)
    - outformat="png"
    - output_dir="output/" (created if missing), overridable via out_dir
    """

    def __init__(
        self,
        name: str,
        out_dir: str = "output",
        outformat: str = "png",
        direction: str = "LR",
        show: bool = False,
        **kwargs,
    ):
        os.makedirs(out_dir, exist_ok=True)
        filename = os.path.join(out_dir, name.lower().replace(" ", "_"))
        super().__init__(
            name=name,
            filename=filename,
            outformat=outformat,
            direction=direction,
            show=show,
            **kwargs,
        )
