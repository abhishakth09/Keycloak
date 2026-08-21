terraform {
  required_version = ">= 1.0"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15.0"
    }
  }
}

# 1. Provision Kind Cluster
resource "kind_cluster" "default" {
  name           = "keycloak-local-cluster"
  node_image     = "kindest/node:v1.29.2"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
        protocol       = "TCP"
      }
    }
  }
}

# Configure Helm Provider
provider "helm" {
  kubernetes {
    host                   = kind_cluster.default.endpoint
    client_certificate     = kind_cluster.default.client_certificate
    client_key             = kind_cluster.default.client_key
    cluster_ca_certificate = kind_cluster.default.cluster_ca_certificate
  }
}

# 2. Deploy PostgreSQL Database
resource "helm_release" "postgresql" {
  name             = "postgresql"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "postgresql"
  version          = "15.1.0"
  namespace        = "iam"
  create_namespace = true
  timeout          = 600
  wait             = false

  set {
    name  = "image.registry"
    value = "docker.io"
  }

  set {
    name  = "image.repository"
    value = "bitnami/postgresql"
  }
  
  set {
      name  = "auth.postgresPassword"
      value = "admin123"
    }

  set {
      name  = "auth.username"
      value = "keycloak"
    }

  set {
      name  = "auth.password"
      value = "keycloak123"
    }

  set {
      name  = "auth.database"
      value = "keycloak"
    }

  depends_on = [kind_cluster.default]
}

# 3. Deploy Multi-Pod Keycloak (2 Replicas)
resource "helm_release" "keycloak" {
  name             = "keycloak"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "keycloak"
  version          = "25.2.0"
  namespace        = "iam"
  create_namespace = true
  timeout          = 600
  wait             = false

  set {
    name  = "image.registry"
    value = "docker.io"
  }

  set {
    name  = "image.repository"
    value = "bitnami/keycloak"
  }

  set {
      name  = "replicaCount"
      value = "2"
    }

  set {
      name  = "auth.adminUser"
      value = "admin"
    }

  set {
      name  = "auth.adminPassword"
      value = "Admin123!"
    }

  set{
      name  = "postgresql.enabled"
      value = "false"
    }

  set{
      name  = "externalDatabase.host"
      value = "postgresql.iam.svc.cluster.local"
    }

  set {
      name  = "externalDatabase.port"
      value = "5432"
    }

  set {
      name  = "externalDatabase.user"
      value = "keycloak"
    }

  set {
      name  = "externalDatabase.password"
      value = "keycloak123"
    }

  set {
      name  = "externalDatabase.database"
      value = "keycloak"
    }

  depends_on = [helm_release.postgresql]
}