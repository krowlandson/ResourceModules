targetScope = 'subscription'

@description('Resource ID of the resource group')
param rgResourceId string

@description('Resource ID of the log analytics workspace')
param lawResourceId string

@description('Resource ID of the virtual network')
param vnetResourceId string

@description('Resource ID of the control plane identity')
param clusterControlPlaneIdentityResourceId string

@description('The location for all cluster resources.')
@allowed([
  'australiaeast'
  'canadacentral'
  'centralus'
  'eastus'
  'eastus2'
  'westus2'
  'francecentral'
  'germanywestcentral'
  'northeurope'
  'southafricanorth'
  'southcentralus'
  'uksouth'
  'westeurope'
  'japaneast'
  'southeastasia'
])
param location string

@secure()
@description('The user name for the SQL DB.')
param dbLogin string

@secure()
@description('The password for the SQL DB.')
param dbPassword string

@description('The kubernetes version that will be used.')
param kubernetesVersion string = '1.22.4'

@description('Azure AD Group in the identified tenant that will be granted the highly privileged cluster-admin role. If Azure RBAC is used, then this group will get a role assignment to Azure RBAC, else it will be assigned directly to the cluster\'s admin group.')
param clusterAdminAadGroupObjectId string

@description('Azure AD Group in the identified tenant that will be granted the read only privileges in the a0008 namespace that exists in the cluster. This is only used when Azure RBAC is used for Kubernetes RBAC.')
param a0008NamespaceReaderAadGroupObjectId string

@description('Your AKS control plane Cluster API authentication tenant')
param k8sControlPlaneAuthorizationTenantId string

@description('IP ranges authorized to contact the Kubernetes API server. Passing an empty array will result in no IP restrictions. If any are provided, remember to also provide the public IP of the egress Azure Firewall otherwise your nodes will not be able to talk to the API server (e.g. Flux).')
param clusterAuthorizedIPRanges array = []

var subRgUniqueString = uniqueString('aks', subscription().subscriptionId, rg.name)
var nodeResourceGroupName = 'rg-${clusterName}-nodepools'
var clusterName = 'aks-${subRgUniqueString}'
var acrName = 'acr${subRgUniqueString}'
var dbServerName = 'sql-${subRgUniqueString}'
var dbName = 'sql-${subRgUniqueString}-01'
var isUsingAzureRBACasKubernetesRBAC = (subscription().tenantId == k8sControlPlaneAuthorizationTenantId)

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

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  scope: rg
  name: '${last(split(vnetResourceId, '/'))}'

  resource snetClusterNodes 'subnets@2021-05-01' existing = {
    name: 'snet-clusternodes'
  }
}

module mi_appgateway_frontend '../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  name: 'mi-appgateway-frontend'
  params: {
    name: 'mi-appgateway-frontend'
    location: location
  }
  scope: resourceGroup(rg.name)
  dependsOn: [
    rg
  ]
}

module sql '../../../arm/Microsoft.Sql/servers/deploy.bicep' = {
  name: 'sql1'
  params: {
    name: dbServerName
    location: location
    administratorLogin: dbLogin
    administratorLoginPassword: dbPassword
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
    location: location
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
    location: location
    aksClusterSkuTier: 'Paid'
    aksClusterKubernetesVersion: kubernetesVersion
    aksClusterDnsPrefix: uniqueString(rg.name)
    primaryAgentPoolProfile: [
      {
        name: 'npsystem'
        count: 3
        vmSize: 'Standard_DS2_v2'
        osDiskSizeGB: 80
        osDiskType: 'Ephemeral'
        osType: 'Linux'
        minCount: 3
        maxCount: 4
        vnetSubnetID: vnet::snetClusterNodes.id
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        scaleSetPriority: 'Regular'
        scaleSetEvictionPolicy: 'Delete'
        orchestratorVersion: kubernetesVersion
        enableNodePublicIP: false
        maxPods: 30
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '33%'
        }
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
      }
    ]
    agentPools: [
      {
        name: 'npuser01'
        count: 2
        vmSize: 'Standard_DS3_v2'
        osDiskSizeGB: 120
        osDiskType: 'Ephemeral'
        osType: 'Linux'
        minCount: 2
        maxCount: 5
        vnetSubnetID: vnet::snetClusterNodes.id
        enableAutoScaling: true
        type: 'VirtualMachineScaleSets'
        mode: 'User'
        scaleSetPriority: 'Regular'
        scaleSetEvictionPolicy: 'Delete'
        orchestratorVersion: kubernetesVersion
        enableNodePublicIP: false
        maxPods: 30
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '33%'
        }
      }
    ]
    aksServicePrincipalProfile: {
      clientId: 'msi'
    }
    httpApplicationRoutingEnabled: false
    monitoringWorkspaceId: law.id
    aciConnectorLinuxEnabled: false
    azurePolicyEnabled: true
    azurePolicyVersion: 'v2'
    enableKeyvaultSecretsProvider: true
    enableSecretRotation: 'false'
    nodeResourceGroup: nodeResourceGroupName
    aksClusterNetworkPlugin: 'azure'
    aksClusterNetworkPolicy: 'azure'
    aksClusterOutboundType: 'userDefinedRouting'
    aksClusterLoadBalancerSku: 'standard'
    aksClusterServiceCidr: '172.16.0.0/16'
    aksClusterDnsServiceIP: '172.16.0.10'
    aksClusterDockerBridgeCidr: '172.18.0.1/16'
    aadProfileManaged: true
    aadProfileEnableAzureRBAC: isUsingAzureRBACasKubernetesRBAC
    aadProfileAdminGroupObjectIDs: ((!isUsingAzureRBACasKubernetesRBAC) ? array(clusterAdminAadGroupObjectId) : [])
    aadProfileTenantId: k8sControlPlaneAuthorizationTenantId
    autoScalerProfileBalanceSimilarNodeGroups: 'false'
    autoScalerProfileExpander: 'random'
    autoScalerProfileMaxEmptyBulkDelete: '10'
    autoScalerProfileMaxNodeProvisionTime: '15m'
    autoScalerProfileMaxTotalUnreadyPercentage: '45'
    autoScalerProfileNewPodScaleUpDelay: '0s'
    autoScalerProfileOkTotalUnreadyCount: '3'
    autoScalerProfileSkipNodesWithLocalStorage: 'true'
    autoScalerProfileSkipNodesWithSystemPods: 'true'
    autoScalerProfileScanInterval: '10s'
    autoScalerProfileScaleDownDelayAfterAdd: '10m'
    autoScalerProfileScaleDownDelayAfterDelete: '20s'
    autoScalerProfileScaleDownDelayAfterFailure: '3m'
    autoScalerProfileScaleDownUnneededTime: '10m'
    autoScalerProfileScaleDownUnreadyTime: '20m'
    autoScalerProfileUtilizationThreshold: '0.5'
    autoScalerProfileMaxGracefulTerminationSec: '600'
    enablePrivateCluster: false
    authorizedIPRanges: clusterAuthorizedIPRanges
    podIdentityProfileEnable: false
    podIdentityProfileUserAssignedIdentities: []
    podIdentityProfileUserAssignedIdentityExceptions: []
    // enableAzureDefender: true
    // enableOidcIssuerProfile:true
    // maxAgentPools: 2
    // enablePodSecurityPolicy: false
    disableLocalAccounts: true
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Azure Kubernetes Service RBAC Cluster Admin'
        principalIds: [
          clusterAdminAadGroupObjectId
        ]
      }
      {
        roleDefinitionIdOrName: 'Azure Kubernetes Service Cluster User Role'
        principalIds: [
          clusterAdminAadGroupObjectId
        ]
      }
      {
        roleDefinitionIdOrName: 'Azure Kubernetes Service RBAC Reader'
        principalIds: [
          a0008NamespaceReaderAadGroupObjectId
        ]
      }
      {
        roleDefinitionIdOrName: 'Azure Kubernetes Service Cluster User Role'
        principalIds: [
          a0008NamespaceReaderAadGroupObjectId
        ]
      }
    ]
    userAssignedIdentities: {
      '${clusterControlPlaneIdentity.id}': {}
    }
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
