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
  name: 'team5-keyvault'
  params: {
    location: location
    name: keyVaultName
  }
}

// Create App Tier

// container registry
module container_registry '../../arm/Microsoft.ContainerRegistry/registries/deploy.bicep' = {
  scope: resourceGroup(rsg_app_tier.name)
  name: '${prefix}-reg'
  params: {
    name: '${prefix}container'
    location: location
  }
}

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
        count: 1
        enableAutoScaling: true
        minCount: 1
        maxCount: 3
        vmSize: 'standard_d4as_v5'
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
    aksServicePrincipalProfile: {
      clientId: '6cdda423-7495-48e4-9141-b4961398d251'
      secret: 'ZtF7Q~1PEbZt6iyihgmHBfQrYX3T5CFnCUk_2'
    }
  }
}
