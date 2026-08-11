"""Example: a GitOps platform stack diagram using most of the icon set
this package targets — AWS, GitLab, Flux/ArgoCD, Kubernetes, Helm, ESO,
and the Prometheus/Grafana/Loki observability trio.

Run it with either:
    archdocs render examples/platform_stack.py
    python examples/platform_stack.py

Output lands in output/platform_stack.png (see archdocs.builder.Architecture).
"""

from archdocs import Architecture, Cluster, Edge, ICONS, custom_icon

with Architecture("Platform Stack"):
    gitlab = ICONS["gitlab"]("GitLab\n(source of truth)")

    with Cluster("GitOps controllers"):
        flux = ICONS["flux"]("Flux")
        argocd = ICONS["argocd"]("ArgoCD")

    with Cluster("AWS"):
        vpc = ICONS["aws_vpc"]("VPC")
        elb = ICONS["aws_elb"]("ALB")
        eks = ICONS["aws_eks"]("EKS")

        with Cluster("Kubernetes cluster"):
            helm = ICONS["helm"]("Helm releases")

            with Cluster("app namespace"):
                deploy = ICONS["k8s_deployment"]("Deployment")
                svc = ICONS["k8s_service"]("Service")
                ingress = ICONS["k8s_ingress"]("Ingress")
                secret = ICONS["k8s_secret"]("Secret")

            # ESO has no built-in diagrams icon — see icons/README.md.
            # Falls back to a plain labeled box if icons/eso.png isn't
            # present yet, so this example still runs out of the box.
            try:
                eso = custom_icon("ESO", "eso.png")
            except FileNotFoundError:
                from diagrams.generic.blank import Blank

                eso = Blank("ESO\n(add icons/eso.png)")

    with Cluster("Observability"):
        prometheus = ICONS["prometheus"]("Prometheus")
        loki = ICONS["loki"]("Loki")
        grafana = ICONS["grafana"]("Grafana")

    # -- wiring --------------------------------------------------------
    gitlab >> Edge(label="reconciles") >> [flux, argocd]
    [flux, argocd] >> helm >> deploy
    deploy >> svc >> ingress >> elb >> vpc
    eks >> Edge(style="dashed", label="hosts") >> helm
    eso >> Edge(label="syncs") >> secret >> deploy

    deploy >> Edge(label="metrics") >> prometheus >> grafana
    deploy >> Edge(label="logs") >> loki >> grafana
