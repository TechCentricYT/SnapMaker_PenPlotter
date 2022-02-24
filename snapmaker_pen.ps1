
param ($file)

#Stop and Clear any jobs that maybe be left in memory.
Stop-Job Monitor -ErrorAction SilentlyContinue
Remove-Job Monitor -ErrorAction SilentlyContinue

Clear-Host

#Get The Snapmaker ip address
$udpobject = new-Object system.Net.Sockets.Udpclient

$a = new-object system.text.asciiencoding
$RequestData = $a.GetBytes("discover")

[int] $Port = 0 
$IP = "0.0.0.0" 
$Address = [system.net.IPAddress]::Parse($IP) 
$ServerEp = New-Object System.Net.IPEndPoint $address, $port

$udpobject.EnableBroadcast = $true

[int] $Port = 20054 
$IP = "255.255.255.255" 
$Address = [system.net.IPAddress]::Parse($IP) 

# Create IP Endpoint 
$End = New-Object System.Net.IPEndPoint $address, $port

$r = $udpobject.Send($RequestData, $RequestData.Length, $End)

$ServerResponseData = $udpobject.Receive([ref] $ServerEp);
$a = new-object system.text.asciiencoding
$ServerResponse = $a.GetString($ServerResponseData)

if ($ServerResponse -like '*Snapmaker*')
{
    Write-Host "Snapmaker found..."
    write-host "Select yes on touch screen..."
}
else {
    Write-Host "Snapmaker not found... Exiting."
    exit
}

$ip = $ServerEp.Address.ToString() + ":8080"

$result = Invoke-WebRequest -Uri http://$ip/api/v1/connect -Method POST -ContentType "application/json"
$token = ($result.content | ConvertFrom-Json).token

$result = Invoke-WebRequest -Uri http://$ip/api/v1/status?token=$token -Method GET
DO
{
    $result = Invoke-WebRequest -Uri http://$ip/api/v1/status?token=$token -Method GET
    sleep -Seconds 1
}
while($result.StatusDescription -ne "OK")
write-host "Connected"

#region keep alive
#launcher Monitor Job to keep connection alive
$monitorps = {    
    $exit = $false
    $ip = $args[0]
    $token = $args[1]

    DO
    {   
        try
        {           
            Invoke-WebRequest -Uri http://$ip/api/v1/status?token=$token -Method GET | Out-File C:\temp\pen.log
            Start-Sleep -Seconds 4
        }
        catch { $exit = $true } 
    }
    while ($exit -eq $false)
}

start-job -Name Monitor -scriptblock $monitorps -ArgumentList $ip,$token
#endregion


write-host "Setting to absolute postioning."
$postParams = @{token=$token;code="G90"}
$results = Invoke-WebRequest -Uri http://$ip/api/v1/execute_code -Method POST -Body $postParams

write-host "Setting work origin X0 Y0 Z0."
$postParams = @{token=$token;code="G92 X0 Y0 Z0"}
$results = Invoke-WebRequest -Uri http://$ip/api/v1/execute_code -Method POST -Body $postParams


#Process CNC file.
foreach($line in Get-Content "$file") {
    if ($line.Contains(";") -eq $false -and ($line -eq "") -eq $false -and ($line.Contains("M3") -eq $false) -and ($line.Contains("M5") -eq $false)
    {
        write-host $line
        $postParams = @{token=$token;code=$line}
        $results = Invoke-WebRequest -Uri http://$ip/api/v1/execute_code -Method POST -Body $postParams
        
    }
}

$postParams = @{token=$token;code="G0 Z50 F1800"}
$results = Invoke-WebRequest -Uri http://$ip/api/v1/execute_code -Method POST -Body $postParams

$postParams = @{token=$token;code="G0 X0 Y0 F1800"}
$results = Invoke-WebRequest -Uri http://$ip/api/v1/execute_code -Method POST -Body $postParams

#Stop and clear monitoring job
Stop-Job Monitor -ErrorAction SilentlyContinue
Remove-Job Monitor -ErrorAction SilentlyContinue