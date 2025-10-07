@description('Virtual Machine admin username')
param adminUsername string

@description('Virtual Machine admin password')
@secure()
param adminPassword string

@description('VM name prefix')
param vmNamePrefix string = 'vm-'

@description('Load Balancer name')
param lbName string = 'load-balancer'

@description('Load Balancer frontend IP configuration name')
param lbFrontEndName string = 'LoadBalancerFrontEnd'

@description('Load Balancer backend address pool name')
param lbBackEndPoolName string = 'LoadBalancerBackEndPool'

@description('Load Balancer probe name')
param lbProbeName string = 'HealthProbe'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Virtual network name')
param vnetName string = 'vnet-1'

@description('Subnet name')
param subnetName string = 'subnet-1'

var vnetAddressPrefix = '10.0.0.0/16'
var subnetAddressPrefix = '10.0.0.0/24'
var numberOfInstances = 2


resource lbPublicIP 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: '${lbName}-public-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${lbName}-dns')
    }
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: lbName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: lbFrontEndName
        properties: {
          publicIPAddress: {
            id: lbPublicIP.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: lbBackEndPoolName
      }
    ]
    loadBalancingRules: [
      {
        name: 'HTTPRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFrontEndName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBackEndPoolName)
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default'
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, lbProbeName)
          }
        }
      }
    ]
    probes: [
      {
        name: lbProbeName
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 15
          numberOfProbes: 4
        }
      }
    ]
  }
}

resource availabilitySet 'Microsoft.Compute/availabilitySets@2022-03-01' = {
  name: 'vmAvailabilitySet'
  location: location
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
    sku: {
      name: 'Aligned'
    }
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
        }
      }
    ]
  }
  dependsOn: [
    loadBalancer
  ]
}

resource networkInterfaces 'Microsoft.Network/networkInterfaces@2023-11-01' = [
  for i in range(0, numberOfInstances): {
    name: '${vmNamePrefix}${i}-nic'
    location: location
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            privateIPAllocationMethod: 'Dynamic'
            subnet: {
              id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
            }
            loadBalancerBackendAddressPools: [
              {
                id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBackEndPoolName)
              }
            ]
          }
        }
      ]
    }
    dependsOn: [
      loadBalancer
      virtualNetwork
    ]
  }
]

resource virtualMachines 'Microsoft.Compute/virtualMachines@2022-03-01' = [
  for i in range(0, numberOfInstances): {
    name: '${vmNamePrefix}${i}'
    location: location
    properties: {
      hardwareProfile: {
        vmSize: 'Standard_DS1_v2'
      }
      osProfile: {
        computerName: '${vmNamePrefix}${i}'
        adminUsername: adminUsername
        adminPassword: adminPassword
      }
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2019-Datacenter'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
          diskSizeGB: 127
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: resourceId('Microsoft.Network/networkInterfaces', '${vmNamePrefix}${i}-nic')
          }
        ]
      }
      availabilitySet: {
        id: availabilitySet.id
      }
    }
    dependsOn: [
      networkInterfaces[i]
      availabilitySet
    ]
  }
]
