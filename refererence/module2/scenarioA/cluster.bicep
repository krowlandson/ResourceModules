targetScope = 'subscription'

@description('Resource ID of the resource group')
param rgResourceId string

@description('Resource ID of the log analytics workspace')
param lawResourceId string

@description('Resource ID of the key vault')
param kvResourceId string

@description('Resource ID of the control plane identity')
param clusterControlPlaneIdentityResourceId string

@description('The kubernetes version that will be used.')
param kubernetesVersion string = '1.22.4'

var subRgUniqueString = uniqueString('aks', subscription().subscriptionId, rg.name)
var nodeResourceGroupName = 'rg-${clusterName}-nodepools'
var clusterName = 'aks-${subRgUniqueString}'
var acrName = 'acr${subRgUniqueString}'
var dbServerName = 'sql-${subRgUniqueString}'
var dbName = 'sql-${subRgUniqueString}-01'

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: '${split(rgResourceId, '/')[4]}'
}

resource law 'Microsoft.OperationalInsights/workspaces@2020-08-01' existing = {
  scope: resourceGroup(rg.name)
  name: '${split(lawResourceId, '/')[8]}'
}

resource clusterControlPlaneIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  scope: resourceGroup(rg.name)
  name: '${split(clusterControlPlaneIdentityResourceId, '/')[8]}'
}

resource kv 'Microsoft.KeyVault/vaults@2019-09-01' existing = {
  scope: rg
  name: '${split(kvResourceId, '/')[8]}'
}

module sql '../../../arm/Microsoft.Sql/servers/deploy.bicep' = {
  name: 'sql1'
  params: {
    name: dbServerName
    location: rg.location
    administratorLogin: 'userAdmin'
    administratorLoginPassword: kv.getSecret('adminPassword')
    databases: [
      {
        name: dbName
        collation: 'SQL_Latin1_General_CP1_CI_AS'
        tier: 'GeneralPurpose'
        skuName: 'GP_Gen5_2'
        maxSizeBytes: 34359738368
        licenseType: 'LicenseIncluded'
        workspaceId: law.id
      }
    ]
  }
  scope: resourceGroup(rg.name)
  dependsOn: [
    rg
  ]
}

module acrAks '../../../arm/Microsoft.ContainerRegistry/registries/deploy.bicep' = {
  name: 'acraks'
  params: {
    name: acrName
    location: rg.location
    acrSku: 'Basic'
    diagnosticWorkspaceId: law.id
  }
  scope: resourceGroup(rg.name)
  dependsOn: [
    rg
    law
  ]
}

module cluster '../../../arm/Microsoft.ContainerService/managedClusters/deploy.bicep' = {
  name: 'cluster'
  params: {
    name: 'cluster'
    location: rg.location
    aksClusterSkuTier: 'Paid'
    aksClusterKubernetesVersion: kubernetesVersion
    aksClusterDnsPrefix: uniqueString(rg.name)
    primaryAgentPoolProfile: [
      {
        name: 'npsystem'
        count: 3
        vmSize: 'Standard_DS2'
        osDiskSizeGB: 80
        osDiskType: 'Ephemeral'
        osType: 'Linux'
        minCount: 3
        maxCount: 4
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        scaleSetPriority: 'Regular'
        scaleSetEvictionPolicy: 'Delete'
        orchestratorVersion: '1.22.4'
        enableNodePublicIP: false
        maxPods: 30
        upgradeSettings: {
          maxSurge: '33%'
        }
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
      }
    ]
    systemAssignedIdentity: true
    diagnosticWorkspaceId: law.id
    tags: {
      'Business unit': 'contoso'
    }
  }
  scope: resourceGroup(rg.name)
  dependsOn: [
    rg
    law
  ]
}
