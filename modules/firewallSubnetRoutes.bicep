targetScope = 'resourceGroup'

@description('Name of the hub virtual network that hosts the Azure Firewall.')
param vnetName string

@description('Azure region for the route table resource.')
param location string

@description('Name of the route table applied to the firewall subnet.')
param routeTableName string

@description('CIDR prefix for the Azure Firewall subnet.')
param firewallSubnetPrefix string

@description('Remote spoke address prefixes that should route through the destination firewall.')
param remoteSpokePrefixes array = []

@description('Private IP address of the remote hub firewall acting as next hop for cross-region traffic.')
param remoteFirewallIp string

@description('Tags applied to created resources.')
param tags object = {}

var remoteRoutes = [
    for prefix in remoteSpokePrefixes: {
        name: length(format('to-remote-fw-{0}', toLower(replace(replace(prefix, '.', '-'), '/', '-')))) > 80
            ? substring(format('to-remote-fw-{0}', toLower(replace(replace(prefix, '.', '-'), '/', '-'))), 0, 80)
            : format('to-remote-fw-{0}', toLower(replace(replace(prefix, '.', '-'), '/', '-')))
        properties: {
            addressPrefix: prefix
            nextHopType: 'VirtualAppliance'
            nextHopIpAddress: remoteFirewallIp
        }
    }
]

var routes = concat(
    [
        {
            name: 'default-to-internet'
            properties: {
                addressPrefix: '0.0.0.0/0'
                nextHopType: 'Internet'
            }
        }
    ],
    remoteRoutes
)

resource firewallRouteTable 'Microsoft.Network/routeTables@2023-05-01' = {
    name: routeTableName
    location: location
    tags: tags
    properties: {
        disableBgpRoutePropagation: false
        routes: routes
    }
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
    name: vnetName
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
    name: 'AzureFirewallSubnet'
    parent: hubVnet
    properties: {
        addressPrefix: firewallSubnetPrefix
        routeTable: {
            id: firewallRouteTable.id
        }
        delegations: []
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
    }
}

output routeTableId string = firewallRouteTable.id
