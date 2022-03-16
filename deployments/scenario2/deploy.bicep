targetScope = 'subscription'

param prefix string = 'scenario2team5'
param location string = 'centralus'

var keyVaultName = '${prefix}-keyvault'

// Create Resource Groups

@description('The Resource Groups to create')

module rsg_app_tier '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${prefix}-app'
  params: {
    name: '${prefix}-app'
    location: location
  }
}

module rsg_data_tier '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${prefix}-data'
  params: {
    name: '${prefix}-data'
    location: location
  }
}

module rsg_shared '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${prefix}-shared'
  params: {
    name: '${prefix}-shared'
    location: location
  }
}

// Key Vault
module kv '../../arm/Microsoft.KeyVault/vaults/deploy.bicep' = {
  scope: resourceGroup(rsg_shared.name)
  name: '${prefix}-keyvault'
  params: {
    location: location
    name: keyVaultName
  }
}

// Container Registry
module container_registry '../../arm/Microsoft.ContainerRegistry/registries/deploy.bicep' = {
  scope: resourceGroup(rsg_app_tier.name)
  name: '${prefix}-reg'
  params: {
    name: '${prefix}container'
    location: location
  }
}

// AKS Cluster
module aks '../../arm/Microsoft.ContainerService/managedClusters/deploy.bicep' = {
  scope: resourceGroup(rsg_app_tier.name)
  name: '${prefix}-aks'
  params: {
    name: '${prefix}-aks'
    location: location
    primaryAgentPoolProfile: [
      {
        name: 'systempool'
        osDiskSizeGB: 0
        osDiskType: 'Managed'
        osSKU: 'Ubuntu'
        count: 1
        enableAutoScaling: true
        scaleSetPriority: 'Regular'
        minCount: 1
        maxCount: 3
        vmSize: 'Standard_D4AS_v5'
        osType: 'Linux'
        storageProfile: 'ManagedDisks'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        maxPods: 30
        availabilityZones: [
          '1'
        ]
      }
    ]
    aksServicePrincipalProfileClientId: kvresource.getSecret('aksClientId')
    aksServicePrincipalProfileClientSecret: kvresource.getSecret('aksClientSecret')
  }
}

resource kvresource 'Microsoft.KeyVault/vaults@2021-11-01-preview' existing = {
  scope: resourceGroup(rsg_shared.name)
  name: '${prefix}-keyvault'
}

module db '../../arm/Microsoft.Sql/servers/deploy.bicep' = {
  name: '${prefix}-db'
  scope: resourceGroup(rsg_data_tier.name)
  params: {
    location: location
    name: '${prefix}-db'
    administratorLogin: 'sampleadminloginname'
    administratorLoginPassword: kvresource.getSecret('sqlsecret')
  }
  dependsOn: [
    rsg_data_tier
  ]
}
