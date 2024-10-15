
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

# Azure provider setup
provider "azurerm" {
  features {}
}

# Kubernetes provider setup (uses the AKS kubeconfig)
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  token                  = azurerm_kubernetes_cluster.aks.kube_config[0].access_token
}

# Azure Resource Group
resource "azurerm_resource_group" "aks_rg" {
  name     = "aks-resource-group"
  location = "East US"
}

# Azure Virtual Network
resource "azurerm_virtual_network" "aks_vnet" {
  name                = "aks-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

# Subnet for AKS Cluster
resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Azure Kubernetes Service (AKS) Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-cluster"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  dns_prefix          = "aks"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.0.2.10"
    service_cidr   = "10.0.2.0/24"
  }
}

# Azure Container Registry (ACR)
resource "azurerm_container_registry" "acr" {
  name                = "myacr"
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = azurerm_resource_group.aks_rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Attach ACR to AKS
resource "azurerm_role_assignment" "aks_acr_assignment" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "aks_log" {
  name                = "aks-log-analytics"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku                 = "PerGB2018"
}

# Persistent Volume (PV) for Kubernetes
resource "kubernetes_persistent_volume" "pv" {
  metadata {
    name = "aks-pv"
  }
  spec {
    capacity = {
      storage = "5Gi"
    }
    access_modes = ["ReadWriteOnce"]
    persistent_volume_source {
      azure_disk {
        disk_name    = "aks-disk"
        disk_uri     = azurerm_managed_disk.data_disk.id
        kind         = "Managed"
        storage_account_type = "Standard_LRS"
      }
    }
  }
}

# Persistent Volume Claim (PVC)
resource "kubernetes_persistent_volume_claim" "pvc" {
  metadata {
    name = "aks-pvc"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

# Pod with Persistent Volume Claim
resource "kubernetes_pod" "nginx" {
  metadata {
    name = "nginx-pod"
  }
  spec {
    container {
      image = "nginx"
      name  = "nginx"
      volume_mount {
        name       = "storage"
        mount_path = "/usr/share/nginx/html"
      }
    }

    volume {
      name = "storage"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim.pvc.metadata[0].name
      }
    }
  }
}

# Azure Managed Disk for PV (Optional)
resource "azurerm_managed_disk" "data_disk" {
  name                 = "aks-disk"
  location             = azurerm_resource_group.aks_rg.location
  resource_group_name  = azurerm_resource_group.aks_rg.name
  storage_account_type = "Standard_LRS"
  disk_size_gb         = 5
  create_option        = "Empty"
}

# Output the Kubernetes configuration for kubectl
output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}
