@description('Admin username for the Virtual Machines.')
param adminUsername string = 'azureuser'

@description('Admin password for the Virtual Machines.')
@secure()
param adminPassword string = 'Password1234!'

@description('Load Balancer Public IP Name')
param lbPublicIpName string = 'lb-public-ip'

@description('Load Balancer Frontend IP Configuration Name')
param lbFrontendIPConfigName string = 'LoadBalancerFrontEnd'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('NAT Gateway Name')
param natGatewayName string = 'nat-gateway'

@description('NAT Gateway Public IP Name')
param natGatewayPublicIPName string = 'public-ip-nat-gateway'

@description('Load Balancer Name')
param loadBalancerName string = 'load-balancer'

@description('VM prefix name')
param vmNamePrefix string = 'vm-'

@description('Virtual Network Name')
param vnetName string = 'vnet-1'

@description('Network Interface Name Prefix')
param nicNamePrefix string = 'nic-'

@description('Availability Set Name')
param availabilitySetName string = 'vmAvailabilitySet'

var addressPrefix = '10.0.0.0/16'
var subnetName = 'subnet-1'
var subnetPrefix = '10.0.0.0/24'
var networkSecurityGroupName = '${subnetName}-nsg'
var numberOfInstances = 2

resource availabilitySet 'Microsoft.Compute/availabilitySets@2022-11-01' = {
  name: availabilitySetName
  location: location
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 2
  }
}

resource lbPublicIp 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: lbPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource natPublicIP 'Microsoft.Network/publicIPAddresses@2022-07-01' = {
  name: natGatewayPublicIPName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2022-07-01' = {
  name: natGatewayName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natPublicIP.id
      }
    ]
    idleTimeoutInMinutes: 10
  }
}

resource networkInterfaces 'Microsoft.Network/networkInterfaces@2022-07-01' = [
  for i in range(0, numberOfInstances): {
    name: '${nicNamePrefix}${i}'
    location: location
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            subnet: {
              id: vnet.properties.subnets[0].id
            }
            privateIPAllocationMethod: 'Dynamic'
            loadBalancerBackendAddressPools: [
              {
                id: loadBalancer.properties.backendAddressPools[0].id
              }
            ]
            loadBalancerInboundNatRules: [
              {
                id: resourceId('Microsoft.Network/loadBalancers/inboundNatRules', loadBalancerName, 'RDP-Vm${i}-NatRule')
              }
            ]
          }
        }
      ]
    }
    dependsOn: [
      vnet
      loadBalancer
      lb_RDP_VM[i]
    ]
  }
]

resource vnet 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          natGateway: {
            id: natGateway.id
          }
        }
      }
    ]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2022-07-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {}
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2022-07-01' = {
  name: loadBalancerName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: lbFrontendIPConfigName
        properties: {
          publicIPAddress: {
            id: lbPublicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'LoadBalancerBackEnd'
      }
    ]
  }
}

resource lb_RDP_VM 'Microsoft.Network/loadBalancers/inboundNatRules@2022-07-01' = [
  for i in range(0, numberOfInstances): {
    parent: loadBalancer
    name: 'RDP-Vm${i}-NatRule'
    properties: {
      frontendIPConfiguration: {
        id: loadBalancer.properties.frontendIPConfigurations[0].id
      }
      protocol: 'Tcp'
      frontendPort: 5000 + i
      backendPort: 3389
      enableFloatingIP: false
    }
  }
]

resource virtualMachines 'Microsoft.Compute/virtualMachines@2022-08-01' = [
  for i in range(0, numberOfInstances): {
    name: '${vmNamePrefix}${i}'
    location: location
    properties: {
      availabilitySet: {
        id: availabilitySet.id
      }
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
          publisher: 'MicrosoftWindowsDesktop'
          offer: 'windows-10'
          sku: '20h2-pro'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: resourceId('Microsoft.Network/networkInterfaces', '${nicNamePrefix}${i}')
          }
        ]
      }
    }
    dependsOn: [
      networkInterfaces[i]
    ]
  }
]
