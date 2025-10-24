targetScope = 'resourceGroup'

@description('Name of the hub virtual network.')
param vnetName string

@description('Azure region for hub resources.')
param location string

@description('Address prefixes assigned to the hub virtual network.')
param addressPrefixes array

@description('Address prefix reserved for the Azure Firewall subnet.')
param firewallSubnetPrefix string

@description('Optional address prefix for the Azure Firewall management subnet.')
param firewallManagementSubnetPrefix string = ''

@description('Name of the Azure Firewall resource.')
param firewallName string

@description('Name of the public IP address resource for the Azure Firewall.')
param firewallPublicIpName string

@description('CIDR ranges that should be permitted to traverse the hub firewall.')
param allowedSpokePrefixes array = []

@description('Tags to apply to hub resources.')
param tags object = {}

var managementSubnet = empty(firewallManagementSubnetPrefix)
	? []
	: [
			{
				name: 'AzureFirewallManagementSubnet'
				properties: {
					addressPrefix: firewallManagementSubnetPrefix
				}
			}
		]

var hubSubnets = concat(
	[
		{
			name: 'AzureFirewallSubnet'
			properties: {
				addressPrefix: firewallSubnetPrefix
			}
		}
	],
	managementSubnet
)

var eastWestRule = {
	name: 'allow-internal-east-west'
	description: 'Allow east-west traffic between regional spokes'
	sourceAddresses: allowedSpokePrefixes
	destinationAddresses: allowedSpokePrefixes
	destinationPorts: [
		'*'
	]
	protocols: [
		'Any'
	]
}

var internetEgressRule = {
	name: 'allow-spoke-internet-egress'
	description: 'Permit spoke address spaces to reach the public Internet through the firewall'
	sourceAddresses: allowedSpokePrefixes
	destinationAddresses: [
		'0.0.0.0/0'
	]
	destinationPorts: [
		'*'
	]
	protocols: [
		'Any'
	]
}

var networkRuleCollections = length(allowedSpokePrefixes) == 0
	? []
	: [
			{
				name: '${firewallName}-intra-spoke'
				properties: {
					priority: 200
					action: {
						type: 'Allow'
					}
					rules: [eastWestRule, internetEgressRule]
				}
			}
		]

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
	name: vnetName
	location: location
	tags: tags
	properties: {
		addressSpace: {
			addressPrefixes: addressPrefixes
		}
		subnets: hubSubnets
	}
}

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
	name: firewallPublicIpName
	location: location
	tags: tags
	sku: {
		name: 'Standard'
	}
	properties: {
		publicIPAllocationMethod: 'Static'
		idleTimeoutInMinutes: 10
	}
}

resource hubFirewall 'Microsoft.Network/azureFirewalls@2023-05-01' = {
	name: firewallName
	location: location
	tags: tags
	properties: {
		sku: {
			name: 'AZFW_VNet'
			tier: 'Standard'
		}
		threatIntelMode: 'Alert'
		ipConfigurations: [
			{
				name: 'azureFirewallIpConfig'
				properties: {
					subnet: {
						id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'AzureFirewallSubnet')
					}
					publicIPAddress: {
						id: firewallPublicIp.id
					}
				}
			}
		]
		networkRuleCollections: networkRuleCollections
	}
}

output hubVnetId string = hubVnet.id
output hubVnetName string = hubVnet.name
output firewallId string = hubFirewall.id
output firewallPrivateIp string = hubFirewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'AzureFirewallSubnet')
output firewallPublicIpId string = firewallPublicIp.id
