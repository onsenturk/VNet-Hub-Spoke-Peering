targetScope = 'resourceGroup'

@description('Resource ID of the local virtual network.')
param localVnetId string

@description('Name assigned to the VNet peering resource.')
param peeringName string

@description('Resource ID of the remote virtual network to peer with.')
param remoteVnetId string

@description('Allow forwarded traffic across the peering connection.')
param allowForwardedTraffic bool = true

@description('Allow gateway transit on the peering connection.')
param allowGatewayTransit bool = false

@description('Use remote gateways from the peered virtual network.')
param useRemoteGateways bool = false

@description('Allow virtual network access across the peering connection.')
param allowVirtualNetworkAccess bool = true

var localVnetName = last(split(localVnetId, '/'))

resource localVnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: localVnetName
}

resource vnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: peeringName
  parent: localVnet
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
  }
}

output peeringId string = vnetPeering.id
