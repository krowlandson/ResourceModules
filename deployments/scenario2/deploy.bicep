targetScope = 'subscription'

param prefix string = 'scenario2team5'
param location string = 'centralus'
var agwName = '${prefix}-appGateway'
var keyVaultName = '${prefix}-keyvault'
var vnetName = '${prefix}-vnet'
var vNetAddressPrefixes = [
  '10.0.0.0/16'
]
var subnets = [
  {
    name: 'Web'
    addressPrefix: '10.0.1.0/24'
  }
  {
    name: 'App'
    addressPrefix: '10.0.2.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
  {
    name: 'Data'
    addressPrefix: '10.0.3.0/24'
  }
]
var aksBackendDomainName = 'team5.gov'

// Create Resource Groups

@description('Resource Group for the App Gateway')
module rsg_web_tier '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${prefix}-web'
  params: {
    name: '${prefix}-web'
    location: location
  }
}

@description('Resource Group for the AKS Cluster')
module rsg_app_tier '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${prefix}-app'
  params: {
    name: '${prefix}-app'
    location: location
  }
}

@description('Resource Group for the SQL Databases')
module rsg_data_tier '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${prefix}-data'
  params: {
    name: '${prefix}-data'
    location: location
  }
}

@description('Resource Group for shared services (e.g. Virtual Network, DNS, etc.)')
module rsg_shared '../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: '${prefix}-shared'
  params: {
    name: '${prefix}-shared'
    location: location
  }
}

// Virtual Network
module vnet '../../arm/Microsoft.Network/virtualnetworks/deploy.bicep' = {
  name: '${prefix}-vnet'
  scope: resourceGroup(rsg_shared.name)
  params: {
    location: location
    name: vnetName
    addressPrefixes: vNetAddressPrefixes
    subnets: subnets
  }
  dependsOn: [
    rsg_shared
  ]
}

// Application Gateway

module appGatewayPublicIP '../../arm/Microsoft.Network/publicIPAddresses/deploy.bicep' = {
  name: '${prefix}-appGatewayPublicIP'
  scope: resourceGroup(rsg_web_tier.name)
  params: {
    name: '${prefix}-appGatewayPublicIP'
    location: location
  }
  dependsOn: [
    rsg_web_tier
  ]
}

module appGateway '../../arm/Microsoft.Network/applicationGateways/deploy.bicep' = {
  name: '${prefix}-appGateway'
  params: {
    name: agwName
    location: location
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
          keyVaultSecretId: '${kv.outputs.uri}secrets/appgw-ingress-internal-aks-ingress-tls'
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'apw-ip-configuration'
        properties: {
          subnet: {
            id: '${vnet.outputs.resourceId}/subnets/snet-applicationgateway'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'apw-frontend-ip-configuration'
        properties: {
          publicIPAddress: {
            id: '${appGatewayPublicIP.outputs.resourceId}'
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
          keyVaultSecretId: '${kv.outputs.uri}secrets/gateway-public-cert'
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
        name: '${prefix}-appGatewayBackendAddressPools'
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
            id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/probes/probe-${aksBackendDomainName}'
          }
          trustedRootCertificates: [
            {
              id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/trustedRootCertificates/root-cert-wildcard-aks-ingress'
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
            id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/frontendIPConfigurations/apw-frontend-ip-configuration'
          }
          frontendPort: {
            id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/frontendPorts/port-443'
          }
          protocol: 'Https'
          sslCertificate: {
            id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/sslCertificates/${agwName}-ssl-certificate'
          }
          hostName: 'bicycle.gov'
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
            id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/httpListeners/listener-https'
          }
          backendAddressPool: {
            id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/backendAddressPools/${aksBackendDomainName}'
          }
          backendHttpSettings: {
            id: '${subscription().id}/resourceGroups/${rsg_web_tier.name}/providers/Microsoft.Network/applicationGateways/${agwName}/backendHttpSettingsCollection/aks-ingress-backendpool-httpsettings'
          }
        }
      }
    ]
    zones: pickZones('Microsoft.Network', 'applicationGateways', location, 3)
  }
  scope: resourceGroup(rsg_web_tier.name)
  dependsOn: [
    rsg_web_tier
  ]
}

module appGateway '../../arm/Microsoft.Network/applicationGateways/deploy.bicep' = {
  name: '${prefix}-appGateway'
  scope: resourceGroup(rsg_shared.name)
  params: {
    name: '${prefix}-appGateway'
    location: location
    frontendPorts: [
      '443'
    ]
    frontendIPConfigurations: [
      {
        name: '${prefix}-appGatewayFrontendIPConfigurations'
        properties: {
          privateIPAddress: '10.0.1.1'
          privateIPAllocationMethod: 'static'
        }

        publicIPAddress: {
          id: appGatewayPublicIP.outputs.resourceId
        }
        subnet: {
          id: vnet.outputs.subnetResourceIds[0]
        }
      }
    ]
    backendAddressPools: [
      {
        name: '${prefix}-appGatewayBackendAddressPools'
      }
    ]
  }
}

// Key Vault created Rob (kevin did not write this)
module kv '../../arm/Microsoft.KeyVault/vaults/deploy.bicep' = {
  scope: resourceGroup(rsg_shared.name)
  name: '${prefix}-keyvault'
  params: {
    location: location
    name: keyVaultName
  }
  dependsOn: [
    rsg_shared
  ]
}

// Container Registry
module container_registry '../../arm/Microsoft.ContainerRegistry/registries/deploy.bicep' = {
  scope: resourceGroup(rsg_app_tier.name)
  name: '${prefix}-reg'
  params: {
    name: '${prefix}container'
    location: location
  }
  dependsOn: [
    rsg_app_tier
  ]
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
        vnetSubnetId: vnet.outputs.subnetResourceIds[1] // Target the `App` subnet - will break if input array of subnets is changed
      }
    ]
    aksServicePrincipalProfileClientId: kvresource.getSecret('aksClientId')
    aksServicePrincipalProfileClientSecret: kvresource.getSecret('aksClientSecret')
    enablePrivateCluster: true
  }
  dependsOn: [
    rsg_app_tier
  ]
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

module privateDNS '../../arm/Microsoft.Network/privateDnsZones/deploy.bicep' = {
  name: '${prefix}-privateDnsZone'
  scope: resourceGroup(rsg_shared.name)
  params: {
    name: '${prefix}-privateDnsZone'
    location: 'global'
  }
  dependsOn: [
    rsg_shared
  ]
}

module privateEndpoint '../../arm/Microsoft.Network/privateEndpoints/deploy.bicep' = {
  name: '${prefix}-aksPe'
  scope: resourceGroup(rsg_shared.name)
  params: {
    name: '${prefix}-aksPe'
    location: location
    serviceResourceId: aks.outputs.resourceId
    groupId: []
    targetSubnetResourceId: vnet.outputs.subnetResourceIds[1]
  }
}
