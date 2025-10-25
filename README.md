# Dual-Region Hub-and-Spoke Deployment (Bicep)

This repository delivers a subscription-scoped Bicep solution that builds identical hub-and-spoke network topologies in **Sweden Central** and **West Europe**. Each hub contains an Azure Firewall that brokers north-south and east-west traffic, while each spoke provides an application subnet and a subnet delegated to Azure Database for PostgreSQL flexible servers. The regional hubs are cross-peered so workloads in either region can reach each other through the firewalls.

---

## Architecture Overview

```
Spoke (Sweden Central) -> Hub Firewall (Sweden Central) --
                                                           \
                                                             > Hub Firewall (West Europe) <- Spoke (West Europe)
```

- Both hubs act as secure egress points and central routing domains.
- Spoke traffic (internet-bound or cross-region) is forced through the local hub via user-defined routes (UDRs).
- Cross-region connectivity is provided by hub-to-hub peering; spokes never peer directly with each other.
- No Network Security Groups are deployed by default. Add NSGs if subnet-level ACLs are required.
- DDoS Standard is **not** enabled. The deployment relies on the platform’s baseline protection unless you attach a plan.

---

## Repository Layout

| Path | Description |
|------|-------------|
| main.bicep | Subscription-level orchestrator: creates resource groups, instantiates hubs and spokes, applies UDRs, and wires the VNet peerings. |
| modules/hubWithFirewall.bicep | Builds a hub VNet, AzureFirewallSubnet, optional management subnet, static public IP, and an Azure Firewall Standard instance with an east-west allow network rule collection. |
| modules/spoke.bicep | Deploys a spoke VNet with an application subnet, PostgreSQL delegated subnet, shared route table, and routes targeting the regional firewall. |
| modules/vnetPeering.bicep | Creates VNet peering relationships (hub↔hub, hub↔spoke) with configurable flags for forwarded traffic and gateway transit. |
| modules/firewallSubnetRoutes.bicep | Attaches a dedicated route table to the AzureFirewallSubnet with default Internet egress and remote-spoke routes pointing to the opposite-region firewall. |
| parameters/ | Reserved for optional parameter files (e.g., .json) when overriding defaults. |

---

## Deployed Components per Region

| Resource Type | Sweden Central (default names) | West Europe (default names) | Notes |
|---------------|--------------------------------|-----------------------------|-------|
| Resource Group | dualregion-sc-network-rg | dualregion-we-network-rg | Names derive from the prefix parameter. |
| Hub VNet | dualregion-sc-hub-vnet | dualregion-we-hub-vnet | Address space configurable via parameters. |
| Azure Firewall | dualregion-sc-azfw | dualregion-we-azfw | AZFW_VNet SKU, Standard tier, static public IP (…-azfw-pip). |
| Spoke VNet | dualregion-sc-spoke-vnet | dualregion-we-spoke-vnet | Contains app and data subnets. |
| Delegated Subnet | data | data | Delegated to Microsoft.DBforPostgreSQL/flexibleServers; private endpoint policies disabled. |
| Route Table | dualregion-sc-spoke-udr | dualregion-we-spoke-udr | Bound to both subnets in each spoke. |
| VNet Peerings | Hub↔Spoke, Hub↔Hub | Hub↔Spoke, Hub↔Hub | Spokes allow forwarded traffic; remote gateway usage disabled. |

---

## Routing & Firewall Configuration

- **User-Defined Routes**
  - 0.0.0.0/0 → hub firewall private IP (per region).
  - Opposite-region spoke CIDR (e.g., 10.21.0.0/16 in Sweden Central) → hub firewall private IP.
- **Firewall Subnet Route Table**
  - Associates the hub `AzureFirewallSubnet` with a custom route table.
  - Adds `0.0.0.0/0 → Internet` to prefer public egress over the remote firewall.
  - Adds opposite-region spoke CIDRs → remote hub firewall private IP for cross-region return paths.
  - Azure periodically blocks custom route tables on firewall subnets; if deployment fails, remove this module or re-evaluate the design.
- **Azure Firewall**
  - Standard tier, threat intelligence mode Alert.
  - Network rule collection <firewallName>-intra-spoke with:
  - `allow-internal-east-west` permitting any protocol/port between the hub and spoke address spaces in Sweden Central and West Europe (covers return paths when the firewalls SNAT traffic).
  - `allow-spoke-internet-egress` permitting the hub and spoke address spaces to reach `0.0.0.0/0` for general outbound browsing.
  - No application or NAT rules are included—extend the hub module if you need them.
- **Telemetry**
  - Diagnostics are not configured by default. Attach diagnostic settings for Log Analytics or storage as needed.

---

## Default Address Spaces

| Region | Hub VNet CIDR | Spoke VNet CIDR | Delegated Subnet | Firewall Subnet |
|--------|----------------|-----------------|------------------|-----------------|
| Sweden Central | 10.10.0.0/16 | 10.11.0.0/16 | 10.11.1.0/24 | 10.10.0.0/24 |
| West Europe | 10.20.0.0/16 | 10.21.0.0/16 | 10.21.1.0/24 | 10.20.0.0/24 |

Override any of these addresses through the swedenCentral and westEurope parameter objects in main.bicep.

---

## Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| prefix | string | Base name used to compose resource groups, VNets, firewalls, etc. | dualregion |
| tags | object | Key/value pairs applied uniformly to all resources. | {} |
| swedenCentral | object | Nested hub/spoke settings for Sweden Central (resource group name, region, VNet/subnet CIDRs, route table name, firewall names). | See template |
| westEurope | object | Same schema as swedenCentral, scoped to West Europe. | See template |

### Sample Parameters File (parameters/dual-region.json)

```json
{
  "prefix": { "value": "contoso" },
  "tags": { "value": { "environment": "demo", "owner": "networking-team" } },
  "swedenCentral": {
    "value": {
      "resourceGroupName": "contoso-sc-network-rg",
      "location": "Sweden Central",
      "hub": {
        "name": "contoso-sc-hub-vnet",
        "addressPrefixes": ["10.100.0.0/16"],
        "firewallSubnetPrefix": "10.100.0.0/24",
        "firewallName": "contoso-sc-azfw",
        "firewallPublicIpName": "contoso-sc-azfw-pip"
      },
      "spoke": {
        "name": "contoso-sc-spoke-vnet",
        "addressPrefixes": ["10.101.0.0/16"],
        "appSubnetName": "app",
        "appSubnetPrefix": "10.101.0.0/24",
        "postgresSubnetName": "data",
        "postgresSubnetPrefix": "10.101.1.0/24",
        "routeTableName": "contoso-sc-spoke-udr"
      }
    }
  }
}
```

(Provide a matching westEurope object if you also override that region.)

---

## Deployment Guide

1. **Authenticate & target subscription**
   ```powershell
   az login
   az account set --subscription "<subscription name or id>"
   ```
2. **Optional – template lint/compile**
   ```powershell
   bicep build .\main.bicep
   ```
3. **Deploy**
   ```powershell
   az deployment sub create 
     --name dual-region-hub-spoke 
     --location westeurope 
     --template-file .\main.bicep 
     [--parameters @parameters\dual-region.json]
   ```
4. **Inspect outputs**
   ```powershell
   az deployment sub show --name dual-region-hub-spoke --query properties.outputs
   ```

The subscription deployment automatically creates (or updates) the two resource groups and provisions all hub and spoke infrastructure within them.

---

## Post-Deployment Validation

- **Connectivity tests**: Use Azure Network Watcher (Test-AzNetworkWatcherConnectivity) or VM-based tests to verify that traffic between spokes traverses the firewalls successfully.
- **Route checks**: Confirm that both spoke subnets are associated with the generated route tables and that effective routes point to the firewall private IP.
- **Firewall subnet routes**: Ensure the `AzureFirewallSubnet` shows the custom route table with the Internet and remote-firewall routes (omit if the platform rejects the association).
- **Subnet delegation**: Run az network vnet subnet show to ensure the data subnet is delegated to PostgreSQL Flexible Server.
- **Firewall health**: Review firewall provisioning state and consider attaching diagnostic settings for logging.

---

## Operations & Extensions

- **Security hardening**: Add Azure Firewall Policy, application/NAT rules, or integrate with a third-party firewall via a custom module.
- **NSG coverage**: Layer NSGs onto the application and data subnets if you require subnet-level ACLs in addition to the firewall.
- **DDoS Standard**: Associate a protection plan with each hub VNet if you need enhanced protection.
- **Additional spokes**: Reuse modules/spoke.bicep to onboard more spoke VNets; update allowedSpokePrefixes and UDRs accordingly.

---

## Cleanup

Remove the deployment and the created resource groups when you are finished:

```powershell
az deployment sub delete --name dual-region-hub-spoke
az group delete --name <prefix>-sc-network-rg --yes --no-wait
az group delete --name <prefix>-we-network-rg --yes --no-wait
```

---

## Outputs

| Output | Description |
|--------|-------------|
| swedenHubFirewallIp | Private IP address of the Sweden Central hub firewall. |
| westHubFirewallIp | Private IP address of the West Europe hub firewall. |

Use these IP addresses when configuring downstream routing, private DNS, or monitoring solutions.
