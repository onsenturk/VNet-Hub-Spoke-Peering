targetScope = 'subscription'

@description('Name prefix applied to resources in both regions.')
param prefix string = 'dualregion'

@description('Tag dictionary applied to all resources created by this template.')
param tags object = {}

@description('Configuration for the Sweden Central hub-and-spoke environment.')
param swedenCentral object = {
	resourceGroupName: '${prefix}-sc-network-rg'
	location: 'Sweden Central'
	hub: {
		name: '${prefix}-sc-hub-vnet'
		addressPrefixes: [
			'10.10.0.0/16'
		]
		firewallSubnetPrefix: '10.10.0.0/24'
		firewallName: '${prefix}-sc-azfw'
		firewallPublicIpName: '${prefix}-sc-azfw-pip'
	}
	spoke: {
		name: '${prefix}-sc-spoke-vnet'
		addressPrefixes: [
			'10.11.0.0/16'
		]
		appSubnetName: 'app'
		appSubnetPrefix: '10.11.0.0/24'
		postgresSubnetName: 'data'
		postgresSubnetPrefix: '10.11.1.0/24'
		routeTableName: '${prefix}-sc-spoke-udr'
	}
}

@description('Configuration for the West Europe hub-and-spoke environment.')
param westEurope object = {
	resourceGroupName: '${prefix}-we-network-rg'
	location: 'West Europe'
	hub: {
		name: '${prefix}-we-hub-vnet'
		addressPrefixes: [
			'10.20.0.0/16'
		]
		firewallSubnetPrefix: '10.20.0.0/24'
		firewallName: '${prefix}-we-azfw'
		firewallPublicIpName: '${prefix}-we-azfw-pip'
	}
	spoke: {
		name: '${prefix}-we-spoke-vnet'
		addressPrefixes: [
			'10.21.0.0/16'
		]
		appSubnetName: 'app'
		appSubnetPrefix: '10.21.0.0/24'
		postgresSubnetName: 'data'
		postgresSubnetPrefix: '10.21.1.0/24'
		routeTableName: '${prefix}-we-spoke-udr'
	}
}

var swedenAllowedPrefixes = concat(
	swedenCentral.spoke.addressPrefixes,
	westEurope.spoke.addressPrefixes,
	swedenCentral.hub.addressPrefixes,
	westEurope.hub.addressPrefixes
)

var westAllowedPrefixes = concat(
	westEurope.spoke.addressPrefixes,
	swedenCentral.spoke.addressPrefixes,
	westEurope.hub.addressPrefixes,
	swedenCentral.hub.addressPrefixes
)

resource swedenCentralRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
	name: swedenCentral.resourceGroupName
	location: swedenCentral.location
	tags: tags
}

resource westEuropeRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
	name: westEurope.resourceGroupName
	location: westEurope.location
	tags: tags
}

module swedenHub 'modules/hubWithFirewall.bicep' = {
	name: '${uniqueString(swedenCentral.resourceGroupName, swedenCentral.hub.name)}-hub'
	scope: swedenCentralRg
	params: {
		vnetName: swedenCentral.hub.name
		location: swedenCentral.location
		addressPrefixes: swedenCentral.hub.addressPrefixes
		firewallSubnetPrefix: swedenCentral.hub.firewallSubnetPrefix
		firewallName: swedenCentral.hub.firewallName
		firewallPublicIpName: swedenCentral.hub.firewallPublicIpName
		allowedSpokePrefixes: swedenAllowedPrefixes
		tags: tags
	}
}

module westHub 'modules/hubWithFirewall.bicep' = {
	name: '${uniqueString(westEurope.resourceGroupName, westEurope.hub.name)}-hub'
	scope: westEuropeRg
	params: {
		vnetName: westEurope.hub.name
		location: westEurope.location
		addressPrefixes: westEurope.hub.addressPrefixes
		firewallSubnetPrefix: westEurope.hub.firewallSubnetPrefix
		firewallName: westEurope.hub.firewallName
		firewallPublicIpName: westEurope.hub.firewallPublicIpName
		allowedSpokePrefixes: westAllowedPrefixes
		tags: tags
	}
}

module swedenSpoke 'modules/spoke.bicep' = {
	name: '${uniqueString(swedenCentral.resourceGroupName, swedenCentral.spoke.name)}-spoke'
	scope: swedenCentralRg
	params: {
		vnetName: swedenCentral.spoke.name
		location: swedenCentral.location
		addressPrefixes: swedenCentral.spoke.addressPrefixes
		appSubnetName: swedenCentral.spoke.appSubnetName
		appSubnetPrefix: swedenCentral.spoke.appSubnetPrefix
		postgresSubnetName: swedenCentral.spoke.postgresSubnetName
		postgresSubnetPrefix: swedenCentral.spoke.postgresSubnetPrefix
		routeTableName: swedenCentral.spoke.routeTableName
		firewallPrivateIp: swedenHub.outputs.firewallPrivateIp
		remoteSpokePrefixes: westEurope.spoke.addressPrefixes
		tags: tags
	}
}

module westSpoke 'modules/spoke.bicep' = {
	name: '${uniqueString(westEurope.resourceGroupName, westEurope.spoke.name)}-spoke'
	scope: westEuropeRg
	params: {
		vnetName: westEurope.spoke.name
		location: westEurope.location
		addressPrefixes: westEurope.spoke.addressPrefixes
		appSubnetName: westEurope.spoke.appSubnetName
		appSubnetPrefix: westEurope.spoke.appSubnetPrefix
		postgresSubnetName: westEurope.spoke.postgresSubnetName
		postgresSubnetPrefix: westEurope.spoke.postgresSubnetPrefix
		routeTableName: westEurope.spoke.routeTableName
		firewallPrivateIp: westHub.outputs.firewallPrivateIp
		remoteSpokePrefixes: swedenCentral.spoke.addressPrefixes
		tags: tags
	}
}

// Hub-to-hub peering
module swedenHubToWestHub 'modules/vnetPeering.bicep' = {
	name: '${uniqueString(swedenCentral.hub.name, westEurope.hub.name)}-hub-to-hub'
	scope: swedenCentralRg
	params: {
		localVnetId: swedenHub.outputs.hubVnetId
		peeringName: 'to-${westEurope.hub.name}'
		remoteVnetId: westHub.outputs.hubVnetId
		allowGatewayTransit: false
		useRemoteGateways: false
	}
}

module westHubToSwedenHub 'modules/vnetPeering.bicep' = {
	name: '${uniqueString(westEurope.hub.name, swedenCentral.hub.name)}-hub-to-hub'
	scope: westEuropeRg
	params: {
		localVnetId: westHub.outputs.hubVnetId
		peeringName: 'to-${swedenCentral.hub.name}'
		remoteVnetId: swedenHub.outputs.hubVnetId
		allowGatewayTransit: false
		useRemoteGateways: false
	}
}

// Hub-to-spoke peering - Sweden Central
module swedenHubToSpoke 'modules/vnetPeering.bicep' = {
	name: '${uniqueString(swedenCentral.hub.name, swedenCentral.spoke.name)}-hub-to-spoke'
	scope: swedenCentralRg
	params: {
		localVnetId: swedenHub.outputs.hubVnetId
		peeringName: 'to-${swedenCentral.spoke.name}'
		remoteVnetId: swedenSpoke.outputs.spokeVnetId
		allowGatewayTransit: true
		useRemoteGateways: false
	}
}

module swedenSpokeToHub 'modules/vnetPeering.bicep' = {
	name: '${uniqueString(swedenCentral.spoke.name, swedenCentral.hub.name)}-spoke-to-hub'
	scope: swedenCentralRg
	params: {
		localVnetId: swedenSpoke.outputs.spokeVnetId
		peeringName: 'to-${swedenCentral.hub.name}'
		remoteVnetId: swedenHub.outputs.hubVnetId
		allowGatewayTransit: false
		useRemoteGateways: false
	}
}

// Hub-to-spoke peering - West Europe
module westHubToSpoke 'modules/vnetPeering.bicep' = {
	name: '${uniqueString(westEurope.hub.name, westEurope.spoke.name)}-hub-to-spoke'
	scope: westEuropeRg
	params: {
		localVnetId: westHub.outputs.hubVnetId
		peeringName: 'to-${westEurope.spoke.name}'
		remoteVnetId: westSpoke.outputs.spokeVnetId
		allowGatewayTransit: true
		useRemoteGateways: false
	}
}

module westSpokeToHub 'modules/vnetPeering.bicep' = {
	name: '${uniqueString(westEurope.spoke.name, westEurope.hub.name)}-spoke-to-hub'
	scope: westEuropeRg
	params: {
		localVnetId: westSpoke.outputs.spokeVnetId
		peeringName: 'to-${westEurope.hub.name}'
		remoteVnetId: westHub.outputs.hubVnetId
		allowGatewayTransit: false
		useRemoteGateways: false
	}
}

output swedenHubFirewallIp string = swedenHub.outputs.firewallPrivateIp
output westHubFirewallIp string = westHub.outputs.firewallPrivateIp
