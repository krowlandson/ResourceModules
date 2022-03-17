targetScope = 'subscription'

@description('Name of the resource group')
param resourceGroupName string

@description('The location for all platform resources.')
param location string

var orgAppId = 'contoso'
var subRgUniqueString = uniqueString('aks', subscription().subscriptionId, resourceGroupName)
var clusterName = 'aks-${subRgUniqueString}'
var logAnalyticsWorkspaceName = 'la-${clusterName}'
var clusterControlPlaneIdentityName = 'mi-${clusterName}-controlplane'
var keyVaultName = 'kv-${clusterName}'

var keyVaultDeploymentScriptParameters = {
  name: 'sxx-ds-kv-${orgAppId}-01'
  userAssignedIdentities: {
    '${podmi_ingress_controller.outputs.resourceId}': {}
  }
  cleanupPreference: 'OnSuccess'
  arguments: ' -keyVaultName "${kv.name}"'
  scriptContent: '''
      param(
        [string] $keyVaultName
      )
      $passwordString = (New-Guid).Guid.SubString(0,19)
      $password = ConvertTo-SecureString -String $passwordString -AsPlainText -Force
      Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'adminPassword' -SecretValue $password
    '''
}

module rg '../../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  params: {
    name: resourceGroupName
    location: location
  }
}

module law '../../../arm/Microsoft.OperationalInsights/workspaces/deploy.bicep' = {
  name: logAnalyticsWorkspaceName
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    serviceTier: 'PerGB2018'
    dataRetention: 30
    gallerySolutions: [
      {
        name: 'ContainerInsights'
        product: 'OMSGallery'
        publisher: 'Microsoft'
      }
      {
        name: 'KeyVaultAnalytics'
        product: 'OMSGallery'
        publisher: 'Microsoft'
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module clusterControlPlaneIdentity '../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  name: clusterControlPlaneIdentityName
  params: {
    name: clusterControlPlaneIdentityName
    location: location
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module podmi_ingress_controller '../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  name: 'podmi-ingress-controller'
  params: {
    name: 'podmi-ingress-controller'
    location: location
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module kv '../../../arm/Microsoft.KeyVault/vaults/deploy.bicep' = {
  name: keyVaultName
  params: {
    name: keyVaultName
    location: location
    accessPolicies: []
    vaultSku: 'standard'
    enableRbacAuthorization: true
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    enableVaultForTemplateDeployment: true
    enableSoftDelete: false
    diagnosticWorkspaceId: law.outputs.resourceId
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalIds: [
          podmi_ingress_controller.outputs.principalId
        ]
      }
      {
        roleDefinitionIdOrName: 'Key Vault Reader'
        principalIds: [
          podmi_ingress_controller.outputs.principalId
        ]
      }
      {
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalIds: [
          podmi_ingress_controller.outputs.principalId
        ]
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
    podmi_ingress_controller
  ]
}

module keyVaultdeploymentScript '../../../arm/Microsoft.Resources/deploymentScripts/deploy.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: '${uniqueString(deployment().name, location)}-kv-ds'
  params: {
    name: keyVaultDeploymentScriptParameters.name
    location: location
    arguments: keyVaultDeploymentScriptParameters.arguments
    userAssignedIdentities: keyVaultDeploymentScriptParameters.userAssignedIdentities
    scriptContent: keyVaultDeploymentScriptParameters.scriptContent
    cleanupPreference: keyVaultDeploymentScriptParameters.cleanupPreference
  }
  dependsOn: [
    rg
    kv
    podmi_ingress_controller
  ]
}

output rgResourceId string = rg.outputs.resourceId
output lawResourceId string = law.outputs.resourceId
output kvResourceId string = kv.outputs.resourceId
output clusterControlPlaneIdentityResourceId string = clusterControlPlaneIdentity.outputs.resourceId
