targetScope = 'subscription'

@description('Name of the resource group')
param resourceGroupName string

@description('A /16 to contain the cluster')
@minLength(10)
@maxLength(18)
param clusterVnetAddressSpace string

@description('The location for all platform resources.')
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

@description('Optional. Array of Security Rules to deploy to the Network Security Group. When not provided, an NSG including only the built-in roles will be deployed.')
param networkSecurityGroupSecurityRules array = []

@description('A /24 to contain the regional firewall, management, and gateway subnet')
@minLength(10)
@maxLength(18)
param hubVnetAddressSpace string = '10.200.0.0/24'

@description('A /26 under the VNet Address Space for the regional Azure Firewall')
@minLength(10)
@maxLength(18)
param azureFirewallSubnetAddressSpace string = '10.200.0.0/26'

@description('A /27 under the VNet Address Space for our regional On-Prem Gateway')
@minLength(10)
@maxLength(18)
param azureGatewaySubnetAddressSpace string = '10.200.0.64/27'

@description('A /27 under the VNet Address Space for regional Azure Bastion')
@minLength(10)
@maxLength(18)
param azureBastionSubnetAddressSpace string = '10.200.0.96/27'

@description('Allow egress traffic for cluster nodes. See https://docs.microsoft.com/en-us/azure/aks/limit-egress-traffic#required-outbound-network-rules-and-fqdns-for-aks-clusters')
param enableOutboundInternet bool = false

@description('The certificate data for app gateway TLS termination. It is base64')
param appGatewayListenerCertificate string

@description('The Base64 encoded AKS Ingress Controller public certificate (as .crt or .cer) to be stored in Azure Key Vault as secret and referenced by Azure Application Gateway as a trusted root certificate.')
param aksIngressControllerCertificate string

@description('Domain name to use for App Gateway and AKS ingress.')
param domainName string = 'contoso.com'

var orgAppId = 'contoso'
var clusterVNetName = 'vnet-spoke-${orgAppId}-00'
var nsgNodePoolsName = 'nsg-${clusterVNetName}-nodepools'
var nsgAksiLbName = 'nsg-${clusterVNetName}-aksilbs'
var nsgAppGwName = 'nsg-${clusterVNetName}-appgw'
var routeTableName = 'route-${location}-default'
var primaryClusterPipName = 'pip-${orgAppId}-00'
var subRgUniqueString = uniqueString('aks', subscription().subscriptionId, resourceGroupName)
var clusterName = 'aks-${subRgUniqueString}'
var logAnalyticsWorkspaceName = 'la-${clusterName}'
var clusterControlPlaneIdentityName = 'mi-${clusterName}-controlplane'
var keyVaultName = 'kv-${clusterName}'
var toHubPeeringName = 'spoke-${orgAppId}-to-${hubVNet.outputs.name}'
var aksIngressDomainName = 'aks-ingress.${domainName}'
var aksBackendDomainName = 'bu0001a0008-00.${aksIngressDomainName}'
var akvPrivateDnsZonesName = 'privatelink.vaultcore.azure.net'
var agwName = 'apw-${clusterName}'

var baseFwPipName = 'pip-fw-${location}'
var hubFwPipNames = [
  '${baseFwPipName}-default'
  '${baseFwPipName}-01'
  '${baseFwPipName}-02'
]

var hubFwName = 'fw-${location}'
var fwPoliciesBaseName = 'fw-policies-base'
var fwPoliciesName = 'fw-policies-${location}'
var hubVNetName = 'vnet-${location}-hub'
var bastionNetworkNsgName = 'nsg-${location}-bastion'

var networkRuleCollectionGroup = [
  {
    name: 'aks-allow-outbound-network'
    priority: 100
    action: {
      type: 'Allow'
    }
    rules: [
      {
        name: 'SecureTunnel01'
        ipProtocols: [
          'UDP'
        ]
        destinationPorts: [
          '1194'
        ]
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        ruleType: 'NetworkRule'
        destinationIpGroups: []
        destinationAddresses: [
          'AzureCloud.${replace(location, ' ', '')}'
        ]
        destinationFqdns: []
      }
      {
        name: 'SecureTunnel02'
        ipProtocols: [
          'TCP'
        ]
        destinationPorts: [
          '9000'
        ]
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        ruleType: 'NetworkRule'
        destinationIpGroups: []
        destinationAddresses: [
          'AzureCloud.${replace(location, ' ', '')}'
        ]
        destinationFqdns: []
      }
      {
        name: 'NTP'
        ipProtocols: [
          'UDP'
        ]
        destinationPorts: [
          '123'
        ]
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        ruleType: 'NetworkRule'
        destinationIpGroups: []
        destinationAddresses: [
          '*'
        ]
        destinationFqdns: []
      }
    ]
    ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
  }
]

var applicationRuleCollectionGroup = [
  {
    name: 'aks-allow-outbound-app'
    priority: 110
    action: {
      type: 'Allow'
    }
    rules: [
      {
        name: 'NodeToApiServer'
        protocols: [
          {
            protocolType: 'Https'
            port: 443
          }
        ]
        terminateTLS: false
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        targetFqdns: [
          '*.hcp.${replace(location, ' ', '')}.azmk8s.io'
        ]
        targetUrls: []
        fqdnTags: []
        webCategories: []
        ruleType: 'ApplicationRule'
      }
      {
        name: 'MCR'
        protocols: [
          {
            protocolType: 'Https'
            port: 443
          }
        ]
        terminateTLS: false
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        targetFqdns: [
          'mcr.microsoft.com'
        ]
        targetUrls: []
        fqdnTags: []
        webCategories: []
        ruleType: 'ApplicationRule'
      }
      {
        name: 'McrStorage'
        protocols: [
          {
            protocolType: 'Https'
            port: 443
          }
        ]
        terminateTLS: false
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        targetFqdns: [
          '*.data.mcr.microsoft.com'
        ]
        targetUrls: []
        fqdnTags: []
        webCategories: []
        ruleType: 'ApplicationRule'
      }
      {
        name: 'Ops'
        protocols: [
          {
            protocolType: 'Https'
            port: 443
          }
        ]
        terminateTLS: false
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        targetFqdns: [
          'management.azure.com'
        ]
        targetUrls: []
        fqdnTags: []
        webCategories: []
        ruleType: 'ApplicationRule'
      }
      {
        name: 'AAD'
        protocols: [
          {
            protocolType: 'Https'
            port: 443
          }
        ]
        terminateTLS: false
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        targetFqdns: [
          'login.microsoftonline.com'
        ]
        targetUrls: []
        fqdnTags: []
        webCategories: []
        ruleType: 'ApplicationRule'
      }
      {
        name: 'Packages'
        protocols: [
          {
            protocolType: 'Https'
            port: 443
          }
        ]
        terminateTLS: false
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        targetFqdns: [
          'packages.microsoft.com'
        ]
        targetUrls: []
        fqdnTags: []
        webCategories: []
        ruleType: 'ApplicationRule'
      }
      {
        name: 'Repositories'
        protocols: [
          {
            protocolType: 'Https'
            port: 443
          }
        ]
        terminateTLS: false
        sourceAddresses: [
          '*'
        ]
        sourceIpGroups: []
        targetFqdns: [
          'acs-mirror.azureedge.net'
        ]
        targetUrls: []
        fqdnTags: []
        webCategories: []
        ruleType: 'ApplicationRule'
      }
    ]
    ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
  }
]

var keyVaultDeploymentScriptParameters = {
  name: 'sxx-ds-kv-${orgAppId}-01'
  userAssignedIdentities: {
    '${podmi_ingress_controller.outputs.resourceId}': {}
  }
  cleanupPreference: 'OnSuccess'
  arguments: ' -keyVaultName "${keyVault.name}"'
  scriptContent: '''
      param(
        [string] $keyVaultName
      )
      $usernameString = (-join ((65..90) + (97..122) | Get-Random -Count 9 -SetSeed 1 | % {[char]$_ + "$_"})).substring(0,19) # max length
      $passwordString = (New-Guid).Guid.SubString(0,19)
      $userName = ConvertTo-SecureString -String $usernameString -AsPlainText -Force
      $password = ConvertTo-SecureString -String $passwordString -AsPlainText -Force
      # VirtualMachines and VMSS
      Set-AzKeyVaultSecret -VaultName $keyVaultName -Name 'adminUsername' -SecretValue $username
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

module bastionNsg '../../../arm/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  name: bastionNetworkNsgName
  params: {
    name: bastionNetworkNsgName
    location: location
    networkSecurityGroupSecurityRules: networkSecurityGroupSecurityRules
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module hubVNet '../../../arm/Microsoft.Network/virtualNetworks/deploy.bicep' = {
  name: hubVNetName
  params: {
    name: hubVNetName
    location: location
    addressPrefixes: array(hubVnetAddressSpace)
    diagnosticWorkspaceId: law.outputs.resourceId
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        addressPrefix: azureFirewallSubnetAddressSpace
      }
      {
        name: 'GatewaySubnet'
        addressPrefix: azureGatewaySubnetAddressSpace
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: azureBastionSubnetAddressSpace
        networkSecurityGroupName: bastionNsg.outputs.name
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module hubFwPips '../../../arm/Microsoft.Network/publicIPAddresses/deploy.bicep' = [for item in hubFwPipNames: {
  name: item
  params: {
    name: item
    location: location
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
    zones: [
      '1'
      '2'
      '3'
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}]

module fwPoliciesBase '../../../arm/Microsoft.Network/firewallPolicies/deploy.bicep' = {
  name: fwPoliciesBaseName
  params: {
    name: fwPoliciesBaseName
    location: location
    tier: 'Standard'
    threatIntelMode: 'Deny'
    ipAddresses: []
    enableProxy: true
    servers: []
    ruleCollectionGroups: [
      {
        name: 'DefaultNetworkRuleCollectionGroup'
        priority: 200
        ruleCollections: [
          {
            ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
            action: {
              type: 'Allow'
            }
            rules: [
              {
                ruleType: 'NetworkRule'
                name: 'DNS'
                ipProtocols: [
                  'UDP'
                ]
                sourceAddresses: [
                  '*'
                ]
                sourceIpGroups: []
                destinationAddresses: [
                  '*'
                ]
                destinationIpGroups: []
                destinationFqdns: []
                destinationPorts: [
                  '53'
                ]
              }
            ]
            name: 'org-wide-allowed'
            priority: 100
          }
        ]
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module fwPolicies '../../../arm/Microsoft.Network/firewallPolicies/deploy.bicep' = {
  name: fwPoliciesName
  params: {
    name: fwPoliciesName
    location: location
    basePolicyResourceId: fwPoliciesBase.outputs.resourceId
    tier: 'Standard'
    threatIntelMode: 'Deny'
    ipAddresses: []
    enableProxy: true
    servers: []
    ruleCollectionGroups: [
      {
        name: 'DefaultDnatRuleCollectionGroup'
        priority: 100
        ruleCollections: []
      }
      {
        name: 'DefaultNetworkRuleCollectionGroup'
        priority: 200
        ruleCollections: enableOutboundInternet ? networkRuleCollectionGroup : []
      }
      {
        name: 'DefaultApplicationRuleCollectionGroup'
        priority: 300
        ruleCollections: enableOutboundInternet ? applicationRuleCollectionGroup : []
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
    fwPoliciesBase
  ]
}

module hubFw '../../../arm/Microsoft.Network/azureFirewalls/deploy.bicep' = {
  name: hubFwName
  scope: resourceGroup(resourceGroupName)
  params: {
    name: hubFwName
    location: location
    zones: [
      '1'
      '2'
      '3'
    ]
    azureSkuName: 'AZFW_VNet'
    azureSkuTier: 'Standard'
    threatIntelMode: 'Deny'
    ipConfigurations: [
      {
        name: hubFwPipNames[0]
        publicIPAddressResourceId: hubFwPips[0].outputs.resourceId
        subnetResourceId: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/virtualNetworks/${hubVNetName}/subnets/AzureFirewallSubnet'
      }
      {
        name: hubFwPipNames[1]
        publicIPAddressResourceId: hubFwPips[1].outputs.resourceId
      }
      {
        name: hubFwPipNames[2]
        publicIPAddressResourceId: hubFwPips[2].outputs.resourceId
      }
    ]
    natRuleCollections: []
    networkRuleCollections: []
    applicationRuleCollections: []
    firewallPolicyId: fwPolicies.outputs.resourceId
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  dependsOn: [
    rg
  ]
}

module nsgNodePools '../../../arm/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  name: nsgNodePoolsName
  params: {
    name: nsgNodePoolsName
    location: location
    networkSecurityGroupSecurityRules: []
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module nsgAksiLb '../../../arm/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  name: nsgAksiLbName
  params: {
    name: nsgAksiLbName
    location: location
    networkSecurityGroupSecurityRules: []
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module nsgAppGw '../../../arm/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  name: nsgAppGwName
  params: {
    name: nsgAppGwName
    location: location
    networkSecurityGroupSecurityRules: [
      {
        name: 'Allow443InBound'
        properties: {
          description: 'Allow ALL web traffic into 443. (If you wanted to allow-list specific IPs, this is where you\'d list them.)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationPortRange: '443'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowControlPlaneInBound'
        properties: {
          description: 'Allow Azure Control Plane in. (https://docs.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '65200-65535'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHealthProbesInBound'
        properties: {
          description: 'Allow Azure Health Probes in. (https://docs.microsoft.com/azure/application-gateway/configuration-infrastructure#network-security-groups)'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationPortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAllOutBound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationPortRange: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Outbound'
        }
      }
    ]
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module routeTable '../../../arm/Microsoft.Network/routeTables/deploy.bicep' = {
  name: routeTableName
  params: {
    name: routeTableName
    location: location
    routes: [
      {
        name: 'r-nexthop-to-fw'
        properties: {
          nextHopType: 'VirtualAppliance'
          addressPrefix: '0.0.0.0/0'
          nextHopIpAddress: hubFw.outputs.privateIp
        }
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
    hubFw
  ]
}

module clusterVNet '../../../arm/Microsoft.Network/virtualNetworks/deploy.bicep' = {
  name: clusterVNetName
  params: {
    name: clusterVNetName
    location: location
    addressPrefixes: array(clusterVnetAddressSpace)
    diagnosticWorkspaceId: law.outputs.resourceId
    subnets: [
      {
        name: 'snet-clusternodes'
        addressPrefix: '10.240.0.0/22'
        routeTableName: routeTable.outputs.name
        networkSecurityGroupName: nsgNodePools.outputs.name
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
      }
      {
        name: 'snet-clusteringressservices'
        addressPrefix: '10.240.4.0/28'
        routeTableName: routeTable.outputs.name
        networkSecurityGroupName: nsgAksiLb.outputs.name
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Disabled'
      }
      {
        name: 'snet-applicationgateway'
        addressPrefix: '10.240.4.16/28'
        networkSecurityGroupName: nsgAppGw.outputs.name
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Disabled'
      }
    ]
    virtualNetworkPeerings: [
      {
        remoteVirtualNetworkId: hubVNet.outputs.resourceId
        remotePeeringName: toHubPeeringName
        allowForwardedTraffic: true
        allowVirtualNetworkAccess: true
        allowGatewayTransit: false
        remotePeeringEnabled: true
        useRemoteGateways: false
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module primaryClusterPip '../../../arm/Microsoft.Network/publicIPAddresses/deploy.bicep' = {
  name: primaryClusterPipName
  params: {
    name: primaryClusterPipName
    location: location
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    zones: [
      '1'
      '2'
      '3'
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

module mi_appgateway_frontend '../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  name: 'mi-appgateway-frontend'
  params: {
    name: 'mi-appgateway-frontend'
    location: location
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module keyVault '../../../arm/Microsoft.KeyVault/vaults/deploy.bicep' = {
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
    secrets: {
      secureList: [
        {
          name: 'gateway-public-cert'
          value: appGatewayListenerCertificate
        }
        {
          name: 'appgw-ingress-internal-aks-ingress-tls'
          value: aksIngressControllerCertificate
        }
      ]
    }
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
    privateEndpoints: [
      {
        name: 'nodepools-to-akv'
        subnetResourceId: clusterVNet.outputs.subnetResourceIds[0]
        service: 'vault'
        privateDnsZoneResourceIds: [
          akvPrivateDnsZones.outputs.resourceId
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

module akvPrivateDnsZones '../../../arm/Microsoft.Network/privateDnsZones/deploy.bicep' = {
  name: akvPrivateDnsZonesName
  params: {
    name: akvPrivateDnsZonesName
    location: 'global'
    virtualNetworkLinks: [
      {
        name: 'to_${clusterVNet.outputs.name}'
        virtualNetworkResourceId: clusterVNet.outputs.resourceId
        registrationEnabled: false
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module aksIngressDomain '../../../arm/Microsoft.Network/privateDnsZones/deploy.bicep' = {
  name: aksIngressDomainName
  params: {
    name: aksIngressDomainName
    a: [
      {
        name: 'bu0001a0008-00'
        ttl: 3600
        aRecords: [
          {
            ipv4Address: '10.240.4.4'
          }
        ]
      }
    ]
    location: 'global'
    virtualNetworkLinks: [
      {
        name: 'to_${clusterVNet.outputs.name}'
        virtualNetworkResourceId: clusterVNet.outputs.resourceId
        registrationEnabled: false
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module agw '../../../arm/Microsoft.Network/applicationGateways/deploy.bicep' = {
  name: agwName
  params: {
    name: agwName
    location: location
    userAssignedIdentities: {
      '${mi_appgateway_frontend.outputs.resourceId}': {}
    }
    sku: 'WAF_v2'
    sslPolicyType: 'Custom'
    sslPolicyCipherSuites: [
      'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
      'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
    ]
    sslPolicyMinProtocolVersion: 'TLSv1_2'
    trustedRootCertificates: [
      {
        name: 'root-cert-wildcard-aks-ingress'
        properties: {
          keyVaultSecretId: '${keyVault.outputs.uri}secrets/appgw-ingress-internal-aks-ingress-tls'
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'apw-ip-configuration'
        properties: {
          subnet: {
            id: '${clusterVNet.outputs.resourceId}/subnets/snet-applicationgateway'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'apw-frontend-ip-configuration'
        properties: {
          publicIPAddress: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/publicIpAddresses/pip-BU0001A0008-00'
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
    ]
    autoscaleMinCapacity: 0
    autoscaleMaxCapacity: 10
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      exclusions: []
      fileUploadLimitInMb: 10
      disabledRuleGroups: []
    }
    enableHttp2: false
    sslCertificates: [
      {
        name: '${agwName}-ssl-certificate'
        properties: {
          keyVaultSecretId: '${keyVault.outputs.uri}secrets/gateway-public-cert'
        }
      }
    ]
    probes: [
      {
        name: 'probe-${aksBackendDomainName}'
        properties: {
          protocol: 'Https'
          path: '/favicon.ico'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {}
        }
      }
    ]
    backendAddressPools: [
      {
        name: aksBackendDomainName
        properties: {
          backendAddresses: [
            {
              fqdn: aksBackendDomainName
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'aks-ingress-backendpool-httpsettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 20
          probe: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/probes/probe-${aksBackendDomainName}'
          }
          trustedRootCertificates: [
            {
              id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/trustedRootCertificates/root-cert-wildcard-aks-ingress'
            }
          ]
        }
      }
    ]
    httpListeners: [
      {
        name: 'listener-https'
        properties: {
          frontendIPConfiguration: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/frontendIPConfigurations/apw-frontend-ip-configuration'
          }
          frontendPort: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/frontendPorts/port-443'
          }
          protocol: 'Https'
          sslCertificate: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/sslCertificates/${agwName}-ssl-certificate'
          }
          hostName: 'bicycle.${domainName}'
          hostNames: []
          requireServerNameIndication: true
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'apw-routing-rules'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/httpListeners/listener-https'
          }
          backendAddressPool: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/backendAddressPools/${aksBackendDomainName}'
          }
          backendHttpSettings: {
            id: '${subscription().id}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${agwName}/backendHttpSettingsCollection/aks-ingress-backendpool-httpsettings'
          }
        }
      }
    ]
    zones: pickZones('Microsoft.Network', 'applicationGateways', location, 3)
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
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
    keyVault
    podmi_ingress_controller
  ]
}

output rgResourceId string = rg.outputs.resourceId
output lawResourceId string = law.outputs.resourceId
output vnetResourceId string = clusterVNet.outputs.resourceId
output clusterControlPlaneIdentityResourceId string = clusterControlPlaneIdentity.outputs.resourceId
