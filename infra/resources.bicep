param location string = resourceGroup().location
param name string
param principalId string = ''
param tags object

var resourceToken = toLower(uniqueString(subscription().id, name, location))

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: '${resourceToken}-kvlt'
  location: location
  tags: tags
  dependsOn: [
    iotHub
  ]
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    accessPolicies: !empty(principalId) ? [
      {
        objectId: principalId
        permissions: {
          certificates: [ 'all' ]
          keys: [ 'all' ]
          secrets: [ 'all' ]
        }
        tenantId: subscription().tenantId
      }
    ] : []
  }
}

resource iotHub 'Microsoft.Devices/IotHubs@2022-04-30-preview' = {
  name: '${resourceToken}-iothub'
  location: location
  sku: {
    name: 'B1'
    capacity: 1
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: '${resourceToken}-law'
  location: location
  tags: tags
  properties: any({
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    sku: {
      name: 'PerGB2018'
    }
  })
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourceToken}-ai'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

module api 'modules/api.bicep' = {
  name: 'api'
  dependsOn: [
    applicationInsights
  ]
  params: {
    location: location
    name: name
    tags: tags
  }
}

resource systemTopic 'Microsoft.EventGrid/systemTopics@2021-12-01' = {
  name: '${resourceToken}-kvlt-topic'
  location: location
  dependsOn: [
    applicationInsights
    api
  ]
  properties: {
    source: keyVault.id
    topicType: 'Microsoft.KeyVault.vaults'
  }
}

resource eventSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2021-12-01' = {
  name: '${resourceToken}-kvlt-topic-sub'
  parent: systemTopic
  properties: {
    destination: {
      properties: {
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
        resourceId: api.outputs.FUNCTION_ID
      }
      endpointType: 'AzureFunction'
    }
    filter: {
      includedEventTypes: [
        'Microsoft.KeyVault.CertificateNewVersionCreated'
      ]
    }
  }
}

output API_IDENTITY_PRINCIPAL_ID string = api.outputs.API_IDENTITY_PRINCIPAL_ID
output API_NAME string = api.outputs.API_NAME
output API_URI string = api.outputs.API_URI
