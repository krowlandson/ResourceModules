targetScope = 'subscription'

param prefix string = 's3t5'
param suffix string = 'datascience'
param location string = 'centralus'

var rsgName = '${prefix}-${suffix}'
var storageAccountName = '${prefix}${suffix}'
var laRsgName = 'team5-shared'
var laName = 'team5-ws'

@description('Resource Group for data science resources')
module rsg_data_science 'br:scenario3team5br.azurecr.io/bicep/modules/microsoft.resources.resourcegroups:0.4' = {
  name: rsgName
  params: {
    name: rsgName
    location: location
  }
}

resource law 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' existing = {
  scope: resourceGroup(laRsgName)
  name: laName
}

module storage 'br:scenario3team5br.azurecr.io/bicep/modules/microsoft.storage.storageaccounts:0.4' = {
  scope: resourceGroup(rsgName)
  name: storageAccountName
  params: {
    name: storageAccountName
    location: location
    storageAccountSku: 'Standard_LRS'
    diagnosticWorkspaceId: law.id
  }
  dependsOn: [
    rsg_data_science
  ]
}

module storage_blob_service 'br:scenario3team5br.azurecr.io/bicep/modules/microsoft.storage.storageaccounts.blobservices:0.4' = {
  scope: resourceGroup(rsgName)
  name: 'default'
  params: {
    name: 'default'
    storageAccountName: storage.outputs.name
  }
}

module storage_container_staging 'br:scenario3team5br.azurecr.io/bicep/modules/microsoft.storage.storageaccounts.blobservices.containers:0.4' = {
  scope: resourceGroup(rsgName)
  name: 'staging'
  params: {
    name: 'staging'
    storageAccountName: storage.outputs.name
  }
}

module storage_container_publish 'br:scenario3team5br.azurecr.io/bicep/modules/microsoft.storage.storageaccounts.blobservices.containers:0.4' = {
  scope: resourceGroup(rsgName)
  name: 'publish'
  params: {
    name: 'publish'
    storageAccountName: storage.outputs.name
  }
}
