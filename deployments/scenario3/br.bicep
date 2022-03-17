targetScope = 'subscription'

param prefix string = 'scenario3team5'
param suffix string = 'br'
param location string = 'centralus'

var containerRegistryRsgName = '${prefix}-${suffix}'
var containerRegistryName = '${prefix}${suffix}'

@description('Resource Group for artefact publishing')
module rsg_br_tier '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: containerRegistryRsgName
  params: {
    name: containerRegistryRsgName
    location: location
  }
}

// Container Registry
module container_registry '../../arm/Microsoft.ContainerRegistry/registries/deploy.bicep' = {
  scope: resourceGroup(containerRegistryRsgName)
  name: containerRegistryName
  params: {
    name: containerRegistryName
    location: location
  }
  dependsOn: [
    rsg_br_tier
  ]
}

// module functionApp '../../arm/Microsoft.Web/Sites/deploy.bicep' = {
//   name: '${prefix}-functionApp'
//   params: {
//     name: '${prefix}-functionApp'
//     kind: 'functionapp'
//     appServicePlanObject: {}
//   }
// }
