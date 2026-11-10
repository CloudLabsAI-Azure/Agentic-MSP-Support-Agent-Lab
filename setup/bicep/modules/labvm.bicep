// ====
// Lab VM: Spektra jump VM image (userData bootstrap), Standard_D2s_v5 (2 vCPU, the SOW size) with a
// Premium SSD P10 OS disk (128 GiB), public IP with a DNS label for browser RDP, VNet and an NSG that
// allows RDP only. No Microsoft.DevTestLab/schedules: CloudLabs manages VM uptime.
// The VM carries the provisioning identity (id-prov) and non-secret settings for provisioning as
// msplab-* tags, which the scripts read from the Instance Metadata Service without signing in.
// ====

@description('Azure region of the environment.')
param location string

@description('Tags applied to every resource.')
param tags object

@description('Additional msplab-* tags for the VM (non-secret provisioning settings).')
param vmTags object

param vmName string
param nsgName string
param vnetName string
param nicName string
param publicIpName string

@description('VM size. The SOW sets 2 vCPU (Standard_D2s_v5).')
param vmSize string

@description('Local administrator of the VM.')
param adminUsername string

@description('Password of the local administrator.')
@secure()
param adminPassword string

@description('Base64 userData pointer to psscript-01.ps1 (carries the per-deployment CloudLabs credentials).')
@secure()
param userData string

@description('Resource ID of the provisioning identity (id-prov).')
param provisioningIdentityId string

var image = {
  publisher: 'Spektra'
  offer: 'cloudlabs-windows-jumpvm'
  sku: 'win2022mssd'
  version: '24.04.01'
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'default-allow-rdp'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
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
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: publicIpName
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/subnet'
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  tags: union(tags, vmTags)
  plan: {
    name: image.sku
    publisher: 'spektra'
    product: image.offer
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${provisioningIdentityId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        provisionVMAgent: true
      }
    }
    userData: userData
    storageProfile: {
      imageReference: image
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 128
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

output vmId string = vm.id
output dnsName string = publicIp.properties.dnsSettings.fqdn
