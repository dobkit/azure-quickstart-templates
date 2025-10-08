@description('Virtual Machine admin username')
param adminUsername string

@description('Virtual Machine admin password or SSH public key')
@secure()
param adminPasswordOrKey string

@description('Load Balancer DNS Name')
param dnsName string

@description('Number of Virtual Machines')
@minValue(1)
@maxValue(10)
param numberOfVms int = 3

@description('Virtual Machine size')
param vmSize string = 'Standard_D2s_v3'

@description('Operating System for the Virtual Machine')
@allowed([
  'Windows'
  'Ubuntu'
])
param windowsOrUbuntu string = 'Ubuntu'

@description('Load Balancer name')
param lbName string = 'myLoadBalancer'

@description('Load Balancer frontend IP configuration name')
param lbFrontEndName string = 'LoadBalancerFrontEnd'

@description('Load Balancer backend address pool name')
param lbBackEndName string = 'LoadBalancerBackEnd'

@description('Load Balancer probe name')
param lbProbeName string = 'HealthProbe'

@description('Load Balancer rule name')
param lbRuleName string = 'LoadBalancerRule'

@description('Virtual Network name')
param vnetName string = 'myVNet'

@description('Virtual Network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet name')
param subnetName string = 'mySubnet'

@description('Subnet address prefix')
param subnetAddressPrefix string = '10.0.0.0/24'

@description('Network Security Group name')
param nsgName string = 'myNetworkSecurityGroup'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Security Type of the Virtual Machine.')
@allowed([
  'Standard'
  'TrustedLaunch'
])
param securityType string = 'TrustedLaunch'

@description('Type of authentication to use on the Virtual Machine. SSH key is recommended.')
@allowed([
  'sshPublicKey'
  'password'
])
param authenticationType string = 'sshPublicKey'

@description('The Windows version for the VM. This will pick a fully patched image of this given Windows version.')
@allowed([
  '2022-datacenter-azure-edition'
  '2022-datacenter-azure-edition-core'
  '2022-datacenter-azure-edition-core-smalldisk'
  '2022-datacenter-azure-edition-smalldisk'
  '2022-datacenter-core-g2'
  '2022-datacenter-core-smalldisk-g2'
  '2022-datacenter-g2'
  '2022-datacenter-smalldisk-g2'
])
param OSVersion string = '2022-datacenter-azure-edition'

var linuxConfiguration = {
  disablePasswordAuthentication: authenticationType == 'sshPublicKey'
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: adminPasswordOrKey
      }
    ]
  }
}

var windowsImage = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: OSVersion
  version: 'latest'
}

var ubuntuImage = {
  publisher: 'Canonical'
  offer: 'UbuntuServer'
  sku: '22_04-lts-gen2'
  version: 'latest'
}

var securityProfileJson = {
  uefiSettings: {
    secureBootEnabled: true
    vTpmEnabled: true
  }
  securityType: securityType
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'diags${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${lbName}-publicIP'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower(dnsName)
    }
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2024-05-01' = {
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
            id: publicIP.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: lbBackEndName
      }
    ]
    probes: [
      {
        name: lbProbeName
        properties: {
          protocol: 'Tcp'
          port: (windowsOrUbuntu == 'Windows') ? 3389 : 22
          intervalInSeconds: 15
          numberOfProbes: 4
        }
      }
    ]
    loadBalancingRules: [
      {
        name: lbRuleName
        properties: {
          protocol: 'Tcp'
          frontendPort: (windowsOrUbuntu == 'Windows') ? 3389 : 22
          backendPort: (windowsOrUbuntu == 'Windows') ? 3389 : 22
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFrontEndName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBackEndName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, lbProbeName)
          }
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-RDP-SSH'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: (windowsOrUbuntu == 'Windows') ? '3389' : '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-All-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
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
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2024-05-01' = [
  for i in range(0, numberOfVms): {
    name: 'nic-${i}'
    location: location
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            subnet: {
              id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
            }
            privateIPAllocationMethod: 'Dynamic'
            loadBalancerBackendAddressPools: [
              {
                id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, lbBackEndName)
              }
            ]
          }
        }
      ]
    }
    dependsOn: [
      vnet
      loadBalancer
      inboundNatRule
    ]
  }
]

resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-04-01' = [
  for i in range(0, numberOfVms): {
    name: 'vm-${i}'
    location: location
    zones: string((i % 3) + 1)
    properties: {
      hardwareProfile: {
        vmSize: vmSize
      }
      osProfile: {
        computerName: 'vm-${i}'
        adminUsername: adminUsername
        adminPassword: adminPasswordOrKey
        linuxConfiguration: (authenticationType == 'password') ? null : linuxConfiguration
      }
      storageProfile: {
        imageReference: (windowsOrUbuntu == 'Windows') ? windowsImage : ubuntuImage
        osDisk: {
          createOption: 'FromImage'
        }
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: resourceId('Microsoft.Network/networkInterfaces', 'nic-${i}')
          }
        ]
      }
      securityProfile: (securityType == 'TrustedLaunch') ? securityProfileJson : null
      diagnosticsProfile: {
        bootDiagnostics: {
          enabled: true
          storageUri: storageAccount.properties.primaryEndpoints.blob
        }
      }
    }
    dependsOn: [
      networkInterface
    ]
  }
]

resource inboundNatRule 'Microsoft.Network/loadBalancers/inboundNatRules@2024-05-01' = [
  for i in range(0, numberOfVms): {
    parent: loadBalancer
    name: 'natRule-${i}'
    properties: {
      frontendIPConfiguration: {
        id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, lbFrontEndName)
      }
      protocol: 'Tcp'
      frontendPort: (i + 50000)
      backendPort: (windowsOrUbuntu == 'Windows') ? 3389 : 22
      enableFloatingIP: false
    }
  }
]

