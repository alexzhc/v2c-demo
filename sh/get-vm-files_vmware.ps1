#!/bin/pwsh

# Use PowerCLI

# Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP $false -Confirm:$false
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false

if (!$args) {
    Write-Host -ForegroundColor red "Must Provide a VM name!"
    Exit
}
$vmName=$args[0]

# Write-Host -ForegroundColor blue "Cleanp up ./vm/$vmName"
# Remove-Item ./vm/$vmName -Recurse -Force
# New-Item ./vm -ItemType "directory" -Force

Write-Host -ForegroundColor blue "Login into VCSA Server"
Connect-VIServer -Server $Env:VCSA_HOST -verbose -user $Env:VCSA_USERNAME -Password $Env:VCSA_PASSWORD

Write-Host -ForegroundColor blue "Shut down VM '$($vmName)'"

Try{
    $vm = Get-VM -Name $vmName -ErrorAction Stop
    switch($vm.PowerState){
        'poweredon' {
            Shutdown-VMGuest -VM $vm -Confirm:$false
            while($vm.PowerState -eq 'PoweredOn'){
                sleep 5
                $vm = Get-VM -Name $vmName
            }
        }
        Default {
            Write-Host -ForegroundColor red "VM '$($vmName)' is not powered on!"
        }
   }
   Write-Host -ForegroundColor blue "VM '$($vmName)' has shutdown."
}

Catch{
   Write-Host -ForegroundColor red "VM '$($vmName)' not found!"
}

Write-Host -ForegroundColor blue "Export VM '$($vmName)' to .ovf"
Get-VM -Name $vmName | Export-VApp -Destination ./vm/ -CreateSeparateFolder:$false -Confirm:$false

Write-Host -ForegroundColor blue "Obtained VM files:"
ls -lh ./vm