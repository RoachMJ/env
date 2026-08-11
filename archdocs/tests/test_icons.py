"""Sanity tests — mostly guarding against the icon registry silently
losing entries if a future `diagrams` release renames/moves a class."""

import pytest

from archdocs import ICONS, Architecture, Cluster, Edge, custom_icon

EXPECTED_KEYS = [
    "aws_ec2", "aws_eks", "aws_s3", "aws_elb", "aws_rds", "aws_vpc",
    "gitlab", "flux", "argocd",
    "prometheus", "grafana", "loki",
    "k8s_pod", "k8s_deployment", "k8s_service", "k8s_ingress",
    "k8s_namespace", "k8s_configmap", "k8s_secret", "helm",
]


@pytest.mark.parametrize("key", EXPECTED_KEYS)
def test_icon_registered(key):
    assert key in ICONS, (
        f"'{key}' failed to load — check whether its class moved in the "
        f"installed `diagrams` version (see icons.py's _register calls)."
    )


def test_builder_reexports():
    assert Architecture is not None
    assert Cluster is not None
    assert Edge is not None


def test_custom_icon_missing_file_raises():
    with pytest.raises(FileNotFoundError):
        custom_icon("Nonexistent", "definitely-not-a-real-file.png")
