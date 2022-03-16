targetScope = 'subscription'

param prefix string = 'scenario2team5'
param location string = 'centralus'

var keyVaultName = '${prefix}-keyvault'

//managedidentity for SQL PaaS
module sqlpaas_managedid '../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  scope: resourceGroup('scenario2team5-shared')
  name: '${prefix}-sqlmanagedid'
  params: {
    name: '${prefix}sqlid'
    location: location
  }
}

// kv secrets
module kv_accesspol '../../arm/Microsoft.KeyVault/vaults/accessPolicies/deploy.bicep' = {
  scope: resourceGroup('scenario2team5-shared')
  name: '${prefix}-accesspol'
  params: {
    keyVaultName: keyVaultName
    name: 'add'

    accessPolicies: [
      {
        objectId: sqlpaas_managedid.outputs.principalId
        permissions: {
          secrets: [
            'All'
          ]
        }
      }
    ]
  }
}
