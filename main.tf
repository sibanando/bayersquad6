terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group for AKS
resource "azurerm_resource_group" "aks_rg" {
  name     = "bayer-aks-resource-group"
  location = "East US"
}

# Network Security Group (NSG)
resource "azurerm_network_security_group" "aks_nsg" {
  name                = "bayer-aks-nsg"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name

  security_rule {
    name                       = "allow_ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Virtual Network for AKS
resource "azurerm_virtual_network" "aks_vnet" {
  name                = "bayer-aks-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

# Subnet for AKS, ensuring it's private and secure
resource "azurerm_subnet" "aks_subnet" {
  name                 = "bayer-aks-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  enforce_private_link_endpoint_network_policies = true
}

# Associate NSG with the AKS Subnet
resource "azurerm_subnet_network_security_group_association" "aks_subnet_nsg_association" {
  subnet_id                 = azurerm_subnet.aks_subnet.id
  network_security_group_id = azurerm_network_security_group.aks_nsg.id
}

# Azure Kubernetes Service (AKS) Cluster with RBAC and Managed Identity
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "bayer-aks-cluster"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  dns_prefix          = "bayer-aks"

  default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control {
    enabled = true
  }

  network_profile {
    network_plugin     = "azure"
    dns_service_ip     = "10.0.2.10"
    service_cidr       = "10.0.2.0/24"
    docker_bridge_cidr = "172.17.0.1/16"
  }

  addon_profile {
    oms_agent {
      enabled                    = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.aks_log.id
    }
  }

  tags = {
    environment = "Production"
  }
}

# Azure Container Registry (ACR) with private networking and HTTPS enforcement
resource "azurerm_container_registry" "acr" {
  name                = "bayer-acr"
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = azurerm_resource_group.aks_rg.location
  sku                 = "Premium"  # Premium for private networking
  admin_enabled       = false  # Disable admin access for security

  network_rule_set {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.aks_subnet.id]
  }

  retention_policy {
    days    = 30
    enabled = true
  }

  tags = {
    environment = "Production"
  }
}

# Attach ACR to AKS using Managed Identity for security
resource "azurerm_role_assignment" "aks_acr_assignment" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}

# Log Analytics for AKS Monitoring
resource "azurerm_log_analytics_workspace" "aks_log" {
  name                = "bayer-aks-log-analytics"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku                 = "PerGB2018"
}

# GitHub Actions Secret for ACR Credentials (for use in GitHub CI/CD pipelines)
resource "azurerm_key_vault" "kv" {
  name                = "bayer-kv"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  sku_name            = "standard"
}

resource "azurerm_key_vault_secret" "acr_credentials" {
  name         = "acr-push-pull"
  value        = azurerm_container_registry.acr.id
  key_vault_id = azurerm_key_vault.kv.id
}

# Output Kubernetes Configuration
output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

# Output ACR Login Server for GitHub Actions integration
output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}
