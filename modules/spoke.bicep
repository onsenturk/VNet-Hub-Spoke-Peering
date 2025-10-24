targetScope = 'resourceGroup'

@description('Name of the spoke virtual network.')
param vnetName string

@description('Azure region for spoke resources.')
param location string

@description('Address prefixes assigned to the spoke virtual network.')
param addressPrefixes array

@description('Name of the application subnet.')
param appSubnetName string

@description('CIDR prefix for the application subnet.')
param appSubnetPrefix string

@description('Name of the PostgreSQL delegated subnet.')
param postgresSubnetName string

@description('CIDR prefix for the PostgreSQL delegated subnet.')
param postgresSubnetPrefix string

@description('Name of the route table applied to spoke subnets.')
param routeTableName string

@description('Private IP address of the regional hub firewall used as next hop.')
param firewallPrivateIp string

@description('Remote spoke address prefixes that should route through the firewall.')
param remoteSpokePrefixes array = []

@description('Tags to apply to spoke resources.')
param tags object = {}

var remoteRoutes = [
	for prefix in remoteSpokePrefixes: {
		name: length(format('to-{0}', toLower(replace(replace(prefix, '.', '-'), '/', '-')))) > 80
			? substring(format('to-{0}', toLower(replace(replace(prefix, '.', '-'), '/', '-'))), 0, 80)
			: format('to-{0}', toLower(replace(replace(prefix, '.', '-'), '/', '-')))
		properties: {
			addressPrefix: prefix
			nextHopType: 'VirtualAppliance'
			nextHopIpAddress: firewallPrivateIp
		}
	}
]

var routes = concat(
	[
		{
			name: 'default-to-firewall'
			properties: {
				addressPrefix: '0.0.0.0/0'
				nextHopType: 'VirtualAppliance'
				nextHopIpAddress: firewallPrivateIp
			}
		}
	],
	remoteRoutes
)

resource spokeRouteTable 'Microsoft.Network/routeTables@2023-05-01' = {
	name: routeTableName
	location: location
	tags: tags
	properties: {
		disableBgpRoutePropagation: false
		routes: routes
	}
}

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
	name: vnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: addressPrefixes
		}
		subnets: [
			{
				name: appSubnetName
				properties: {
					addressPrefix: appSubnetPrefix
					routeTable: {
						id: spokeRouteTable.id
					}
				}
			}
			{
				name: postgresSubnetName
				properties: {
					addressPrefix: postgresSubnetPrefix
					delegations: [
						{
							name: 'pg-flexible-delegation'
							properties: {
								serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
							}
						}
					]
					privateEndpointNetworkPolicies: 'Disabled'
					privateLinkServiceNetworkPolicies: 'Disabled'
					routeTable: {
						id: spokeRouteTable.id
					}
				}
			}
		]
	}
}

output spokeVnetId string = spokeVnet.id
output appSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, appSubnetName)
output postgresSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, postgresSubnetName)
output routeTableId string = spokeRouteTable.id
